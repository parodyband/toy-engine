package main
import "core:os/os2"
import "core:os"
import "core:fmt"
import "core:strings"
import "base:runtime"
import "core:path/filepath"

// Build configuration parameters
CONFIG :: struct {
    // Project structure
    source_dir:        string,
    assets_dir:        string,
    output_dir:        string,
    
    // Output executables
    executable_name:   string,
    
    // Shader compilation
    shader_input:      string,
    shader_output:     string,
    shader_formats:    string,
    
    // Build options
    debug_build:       bool,
    optimization:      string,
}

// Default configuration
SETTINGS := CONFIG{
    source_dir        = "source",
    assets_dir        = "assets",
    output_dir        = "build/desktop",
    
    executable_name   = "ToyGame",
    
    shader_input      = "source/shader.glsl",
    shader_output     = "source/shader.odin",
    shader_formats    = "glsl300es:hlsl4:glsl430",
    
    debug_build       = true,
    optimization      = "none",
}

// Platform-specific paths
PLATFORM_CONFIG :: struct {
    separator:           string,
    sokol_shdc_path:     string,
    executable_ext:      string,
    debug_file_ext:      string,
}

PLATFORM: PLATFORM_CONFIG
init_platform_config :: proc() {
    when ODIN_OS == .Windows {
        PLATFORM.separator = "\\"
        PLATFORM.sokol_shdc_path = "sokol-shdc\\win32\\sokol-shdc"
        PLATFORM.executable_ext = ".exe"
        PLATFORM.debug_file_ext = ".pdb"
    } else {
        PLATFORM.separator = "/"
        PLATFORM.sokol_shdc_path = "./sokol-shdc/linux/sokol-shdc"
        PLATFORM.executable_ext = ".bin"
        PLATFORM.debug_file_ext = ""
    }
}

run_command :: proc(command: []string) -> bool {
    fmt.println("Running:", strings.join(command, " "))
    
    desc := os2.Process_Desc{
        command = command,
    }

    state, stdout, stderr, err := os2.process_exec(desc, runtime.default_allocator())
    defer delete(stdout)
    defer delete(stderr)
    
    if err != nil {
        fmt.println("Error:", err)
        return false
    }
    
    fmt.println(string(stdout))
    if len(stderr) > 0 {
        fmt.println("Command error output:\n", string(stderr))
    }
    
    return state.exit_code == 0
}

join_path :: proc(components: []string, allocator := context.allocator) -> string {
    if len(components) == 0 {
        return ""
    }
    
    return filepath.join(components, allocator)
}

main :: proc() {
    init_platform_config()
    
    current_dir := os.get_current_directory()
    defer delete(current_dir)
    
    fmt.println("Starting build in directory:", current_dir)
    
    // Create output directory
    out_dir := SETTINGS.output_dir
    when ODIN_OS == .Windows {
        out_dir_tmp, _ := strings.replace_all(out_dir, "/", "\\")
        out_dir = out_dir_tmp
    }
    
    if !os.exists(out_dir) {
        os.make_directory(out_dir, 0)
    }
    
    // Build shaders
    fmt.println("Building shaders...")
    shader_command: []string
    when ODIN_OS == .Windows {
        shader_command = []string{
            "sokol-shdc\\win32\\sokol-shdc", 
            "-i", SETTINGS.shader_input, 
            "-o", SETTINGS.shader_output, 
            "-l", SETTINGS.shader_formats, 
            "-f", "sokol_odin",
        }
    } else {
        shader_command = []string{
            "./sokol-shdc/linux/sokol-shdc", 
            "-i", SETTINGS.shader_input, 
            "-o", SETTINGS.shader_output, 
            "-l", SETTINGS.shader_formats, 
            "-f", "sokol_odin",
        }
    }
    
    if !run_command(shader_command) {
        fmt.println("Shader compilation failed")
        return
    }
    
    // Build the executable
    fmt.println("Building application...")
    build_command: []string
    when ODIN_OS == .Windows {
        exe_path := fmt.tprintf("%s\\%s.exe", out_dir, SETTINGS.executable_name)
        pdb_path := fmt.tprintf("%s\\%s.pdb", out_dir, SETTINGS.executable_name)
        
        if SETTINGS.debug_build {
            build_command = []string{
                "odin", "build", SETTINGS.source_dir, 
                fmt.tprintf("-out:%s", exe_path), 
                "-debug", 
                fmt.tprintf("-o:%s", SETTINGS.optimization),
                fmt.tprintf("-extra-linker-flags:-pdb:%s", pdb_path),
            }
        } else {
            build_command = []string{
                "odin", "build", SETTINGS.source_dir, 
                fmt.tprintf("-out:%s", exe_path), 
                fmt.tprintf("-o:%s", SETTINGS.optimization),
            }
        }
    } else {
        exe_path := fmt.tprintf("%s/%s.bin", out_dir, SETTINGS.executable_name)
        
        if SETTINGS.debug_build {
            build_command = []string{
                "odin", "build", SETTINGS.source_dir, 
                fmt.tprintf("-out:%s", exe_path),
                "-debug",
                fmt.tprintf("-o:%s", SETTINGS.optimization),
            }
        } else {
            build_command = []string{
                "odin", "build", SETTINGS.source_dir, 
                fmt.tprintf("-out:%s", exe_path),
                fmt.tprintf("-o:%s", SETTINGS.optimization),
            }
        }
    }
    
    if !run_command(build_command) {
        fmt.println("Build failed")
        return
    }
    
    // Copy assets
    fmt.println("Copying assets...")
    copy_command: []string
    when ODIN_OS == .Windows {
        assets_dir := fmt.tprintf("%s\\assets", out_dir)
        copy_command = []string{"xcopy", "/y", "/e", "/i", SETTINGS.assets_dir, assets_dir}
    } else {
        source_assets := fmt.tprintf("./%s/", SETTINGS.assets_dir)
        target_assets := fmt.tprintf("./%s/assets/", out_dir)
        copy_command = []string{"cp", "-R", source_assets, target_assets}
    }
    
    if !run_command(copy_command) {
        fmt.println("Failed to copy assets")
        return
    }
    
    fmt.println("Desktop build created in", out_dir)
}