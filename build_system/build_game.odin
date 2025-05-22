package main
import "core:os/os2"
import "core:os"
import "core:fmt"
import "core:strings"
import "base:runtime"
import "core:path/filepath"
import "core:time"
import "core:strconv"

// Supported build targets
BuildType :: enum {
    Desktop,
    Web,
}

// Configuration for the build process
CONFIG :: struct {
    source_dir:         string,
    assets_dir:         string,
    output_dir:         string,
    
    executable_name:    string,
    
    shader_input:       string,
    shader_output:      string,
    shader_formats:     string,
    
    emscripten_sdk_dir: string,
    emscripten_flags:   string,
    
    build_type:         BuildType,
    debug_build:        bool,
    optimization:       string,
}

when ODIN_OS == .Windows {
    DEFAULT_EMSCRIPTEN_DIR :: "c:/emsdk"
    DEFAULT_EMSCRIPTEN_FLAGS :: "-sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sMAX_WEBGL_VERSION=2 -sASSERTIONS"
} else {
    DEFAULT_EMSCRIPTEN_DIR :: "$HOME/emsdk"
    DEFAULT_EMSCRIPTEN_FLAGS :: "-sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sMAX_WEBGL_VERSION=2 -sASSERTIONS -sALLOW_MEMORY_GROWTH=1"
}

SETTINGS := CONFIG{
    source_dir        = "source",
    assets_dir        = "assets",
    output_dir        = "",
    
    executable_name   = "ToyGame",
    
    shader_input      = "source/shaders/shader.glsl",
    shader_output     = "source/shader.odin",
    shader_formats    = "glsl300es:hlsl4:glsl430:metal_macos",
    
    emscripten_sdk_dir = DEFAULT_EMSCRIPTEN_DIR,
    emscripten_flags   = DEFAULT_EMSCRIPTEN_FLAGS,
    
    build_type        = .Desktop,
    debug_build       = true,
    optimization      = "none",
}

// Platform-specific configurations
PLATFORM_CONFIG :: struct {
    separator:             string,
    sokol_shdc_path:       string,
    executable_ext:        string,
    debug_file_ext:        string,
    emscripten_env_script: string,
}

PLATFORM: PLATFORM_CONFIG

init_platform_config :: proc() {
    when ODIN_OS == .Windows {
        PLATFORM.separator = "\\"
        PLATFORM.sokol_shdc_path = "sokol-shdc\\win32\\sokol-shdc"
        PLATFORM.executable_ext = ".exe"
        PLATFORM.debug_file_ext = ".pdb"
        PLATFORM.emscripten_env_script = "emsdk_env.bat"
    } else when ODIN_OS == .Darwin {
        PLATFORM.separator = "/"
        PLATFORM.sokol_shdc_path = "./sokol-shdc/osx_arm64/sokol-shdc"
        PLATFORM.executable_ext = ".bin"
        PLATFORM.debug_file_ext = ""
        PLATFORM.emscripten_env_script = "emsdk_env.sh"
    } else {
        PLATFORM.separator = "/"
        PLATFORM.sokol_shdc_path = "./sokol-shdc/linux/sokol-shdc"
        PLATFORM.executable_ext = ".bin"
        PLATFORM.debug_file_ext = ""
        PLATFORM.emscripten_env_script = "emsdk_env.sh"
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

// Sets up Emscripten environment for web builds
setup_emscripten :: proc() -> bool {
    fmt.println("Setting up Emscripten environment...")
    
    when ODIN_OS == .Windows {
        os.set_env("EMSDK_QUIET", "1")
        env_cmd := []string{"cmd", "/c", "call", fmt.tprintf("%s\\emsdk_env.bat", SETTINGS.emscripten_sdk_dir)}
        if !run_command(env_cmd) {
            fmt.println("Failed to setup Emscripten environment")
            return false
        }
    } else {
        os.set_env("EMSDK_QUIET", "1")
        env_script := fmt.tprintf("%s/emsdk_env.sh", SETTINGS.emscripten_sdk_dir)
        if os.exists(env_script) {
            env_cmd := []string{"sh", "-c", fmt.tprintf("source %s", env_script)}
            if !run_command(env_cmd) {
                fmt.println("Failed to setup Emscripten environment")
                return false
            }
        }
    }
    
    return true
}

// Compiles shaders using sokol-shdc
build_shaders :: proc() -> bool {
    fmt.println("Building shaders...")
    
    shader_command := []string{
        PLATFORM.sokol_shdc_path, 
        "-i", SETTINGS.shader_input, 
        "-o", SETTINGS.shader_output, 
        "-l", SETTINGS.shader_formats, 
        "-f", "sokol_odin",
    }
    
    return run_command(shader_command)
}

build_desktop :: proc() -> bool {
    out_dir := SETTINGS.output_dir
    
    if !os.exists(out_dir) {
        os.make_directory(out_dir, 0)
    }
    
    fmt.println("Building desktop application...")
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
        return false
    }
    
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
    
    return run_command(copy_command)
}

// Handles platform-specific path separators
replace_path_separators :: proc(path: string) -> string {
    when ODIN_OS == .Windows {
        new_path, _ := strings.replace_all(path, "/", "\\")
        return new_path
    } else {
        return path
    }
}

build_web :: proc() -> bool {
    out_dir := SETTINGS.output_dir
    
    if !os.exists(out_dir) {
        os.make_directory(out_dir, 0)
    }
    
    when ODIN_OS == .Windows {
        os.set_env("EMSDK_QUIET", "1")
    } else {
        os.set_env("EMSDK_QUIET", "1")
    }
    
    fmt.println("Building WASM object...")
    
    game_out_path := fmt.tprintf("%s/game", out_dir)
    when ODIN_OS == .Windows {
        game_out_path, _ = strings.replace_all(game_out_path, "/", "\\")
    }
    
    // Build the Odin code targeting wasm
    build_command := make([dynamic]string, 0, 16)
    append(&build_command, "odin")
    append(&build_command, "build")
    append(&build_command, SETTINGS.source_dir)
    append(&build_command, "-target:js_wasm32")
    append(&build_command, "-build-mode:obj")
    append(&build_command, "-vet")
    append(&build_command, "-strict-style")
    append(&build_command, fmt.tprintf("-out:%s", game_out_path))
    
    append(&build_command, "-debug")
    
    if !run_command(build_command[:]) {
        fmt.println("WASM build failed")
        return false
    }
    
    fmt.println("Copying Odin JS runtime...")
    odin_root_cmd := []string{"odin", "root"}
    desc := os2.Process_Desc{
        command = odin_root_cmd,
    }
    
    state, stdout, stderr, err := os2.process_exec(desc, runtime.default_allocator())
    defer delete(stdout)
    defer delete(stderr)
    
    if err != nil || state.exit_code != 0 {
        fmt.println("Failed to get Odin root path")
        return false
    }
    
    odin_root := strings.trim_space(string(stdout))
    
    odin_js_path := fmt.tprintf("%s/core/sys/wasm/js/odin.js", odin_root)
    out_js_path := fmt.tprintf("%s/odin.js", out_dir)
    
    when ODIN_OS == .Windows {
        odin_js_path, _ = strings.replace_all(odin_js_path, "/", "\\")
        out_js_path, _ = strings.replace_all(out_js_path, "/", "\\")
        
        cp_cmd := []string{"cmd", "/c", "copy", odin_js_path, out_js_path}
        if !run_command(cp_cmd) {
            fmt.println("Failed to copy Odin JS runtime")
            return false
        }
    } else {
        cp_cmd := []string{"cp", odin_js_path, out_js_path}
        if !run_command(cp_cmd) {
            fmt.println("Failed to copy Odin JS runtime")
            return false
        }
    }
    
    // Link with Emscripten to create final wasm + HTML
    fmt.println("Linking with Emscripten...")
    
    wasm_obj := fmt.tprintf("%s/game.wasm.o", out_dir)
    html_out := fmt.tprintf("%s/index.html", out_dir)
    
    // Prepare sokol library paths for linking
    sokol_libs := []string{
        fmt.tprintf("%s/sokol/app/sokol_app_wasm_gl_release.a", SETTINGS.source_dir),
        fmt.tprintf("%s/sokol/glue/sokol_glue_wasm_gl_release.a", SETTINGS.source_dir),
        fmt.tprintf("%s/sokol/gfx/sokol_gfx_wasm_gl_release.a", SETTINGS.source_dir),
        fmt.tprintf("%s/sokol/shape/sokol_shape_wasm_gl_release.a", SETTINGS.source_dir),
        fmt.tprintf("%s/sokol/log/sokol_log_wasm_gl_release.a", SETTINGS.source_dir),
        fmt.tprintf("%s/sokol/gl/sokol_gl_wasm_gl_release.a", SETTINGS.source_dir),
    }
    
    when ODIN_OS == .Windows {
        for i := 0; i < len(sokol_libs); i += 1 {
            sokol_libs[i], _ = strings.replace_all(sokol_libs[i], "/", "\\")
        }
        wasm_obj, _ = strings.replace_all(wasm_obj, "/", "\\")
        html_out, _ = strings.replace_all(html_out, "/", "\\")
    }
    
    emcc_cmd := make([dynamic]string, 0, 32)
    
    when ODIN_OS == .Windows {
        append(&emcc_cmd, fmt.tprintf("%s\\upstream\\emscripten\\emcc.bat", SETTINGS.emscripten_sdk_dir))
    } else {
        append(&emcc_cmd, fmt.tprintf("%s/upstream/emscripten/emcc", SETTINGS.emscripten_sdk_dir))
    }
    
    append(&emcc_cmd, "-g")
    append(&emcc_cmd, "-o")
    append(&emcc_cmd, html_out)
    append(&emcc_cmd, wasm_obj)
    
    for lib in sokol_libs {
        append(&emcc_cmd, lib)
    }
    
    flags := strings.split(SETTINGS.emscripten_flags, " ")
    for flag in flags {
        append(&emcc_cmd, flag)
    }
    
    shell_file := fmt.tprintf("%s/web/index_template.html", SETTINGS.source_dir)
    when ODIN_OS == .Windows {
        shell_file, _ = strings.replace_all(shell_file, "/", "\\")
    }
    append(&emcc_cmd, "--shell-file")
    append(&emcc_cmd, shell_file)
    
    append(&emcc_cmd, "--preload-file")
    append(&emcc_cmd, SETTINGS.assets_dir)
    
    emcc_success := false
    when ODIN_OS == .Windows {
        if !run_command(emcc_cmd[:]) {
            fmt.println("Emscripten linking failed")
            return false
        }
        emcc_success = true
    } else {
        emcc_success = run_command(emcc_cmd[:])
    }
    
    if !emcc_success {
        fmt.println("Emscripten linking failed")
        return false
    }
    
    fmt.println("Cleaning up...")
    when ODIN_OS == .Windows {
        del_cmd := []string{"cmd", "/c", "del", wasm_obj}
        run_command(del_cmd)
    } else {
        rm_cmd := []string{"rm", wasm_obj}
        run_command(rm_cmd)
    }
    
    return true
}

// Runs a command in background (platform specific)
run_command_background :: proc(command: []string) -> bool {
    fmt.println("Running in background:", strings.join(command, " "))
    
    when ODIN_OS == .Windows {
        // Windows requires special handling for background processes
        start_cmd := make([dynamic]string)
        defer delete(start_cmd)
        
        append(&start_cmd, "cmd")
        append(&start_cmd, "/c")
        append(&start_cmd, "start")
        append(&start_cmd, "cmd")
        append(&start_cmd, "/c")
        
        for arg in command {
            append(&start_cmd, arg)
        }
        
        return run_command(start_cmd[:])
    } else {
        // Unix background process with &
        bg_cmd := make([dynamic]string)
        defer delete(bg_cmd)
        
        append(&bg_cmd, "sh")
        append(&bg_cmd, "-c")
        
        cmd_str := fmt.tprintf("%s &", strings.join(command, " "))
        append(&bg_cmd, cmd_str)
        
        return run_command(bg_cmd[:])
    }
}

// Starts a web server to serve the web build, trying ports until one works
start_web_server :: proc(dir: string, initial_port: int) -> bool {
    port := initial_port
    max_port := initial_port + 10
    
    abs_dir := dir
    fmt.println("Starting web server in directory:", abs_dir)
    
    when ODIN_OS == .Windows {
        for port <= max_port {
            fmt.println("Attempting to start web server on port", port)
            
            url := fmt.tprintf("http://localhost:%d", port)
            
            // PowerShell script to launch both server and browser
            ps_script := fmt.tprintf(
                `$ErrorActionPreference = 'SilentlyContinue'; 
                $server = Start-Process python -ArgumentList '-m','http.server','%d','-d','%s' -WindowStyle Normal -PassThru;
                Start-Sleep -Milliseconds 500;
                Start-Process '%s';`,
                port, abs_dir, url
            )
            
            ps_cmd := []string{
                "powershell", "-Command", ps_script
            }
            
            if run_command(ps_cmd) {
                fmt.println("Web server started at", url)
                fmt.println("")
                fmt.println("If your browser doesn't open automatically, please copy and paste this URL:")
                fmt.println(url)
                fmt.println("")
                fmt.println("Close the Python server window when done")
                return true
            }
            
            port += 1
        }
        
        fmt.println("Failed to start web server after trying multiple ports")
        return false
    } else {
        for port <= max_port {
            fmt.println("Attempting to start web server on port", port)
            
            url := fmt.tprintf("http://localhost:%d", port)
            
            server_cmd := []string{
                "sh", "-c", 
                fmt.tprintf("cd %s && nohup python -m http.server %d >/dev/null 2>&1 &", abs_dir, port)
            }
            
            if run_command(server_cmd) {
                time.sleep(2 * time.Second)
                
                browser_cmd := []string{
                    "sh", "-c",
                    fmt.tprintf("nohup xdg-open %s >/dev/null 2>&1 &", url)
                }
                run_command(browser_cmd)
                
                fmt.println("Web server started at", url)
                fmt.println("")
                fmt.println("If your browser doesn't open automatically, please copy and paste this URL:")
                fmt.println(url)
                fmt.println("")
                fmt.println("Use 'pkill -f \"python -m http.server\"' to stop the server when done")
                return true
            }
            
            port += 1
        }
        
        fmt.println("Failed to start web server after trying multiple ports")
        return false
    }
}

main :: proc() {
    context.allocator = runtime.default_allocator()
    
    web_build := false
    start_server := false
    server_port := 8000
    run_executable := false
    
    // Parse command line arguments
    args := os.args
    if len(args) > 1 {
        for i := 1; i < len(args); i += 1 {
            arg := args[i]
            
            if arg == "--web" || arg == "-web" {
                web_build = true
            } else if arg == "--serve" || arg == "-serve" || arg == "--server" || arg == "-server" {
                start_server = true
                if i + 1 < len(args) {
                    if port, ok := strconv.parse_int(args[i+1]); ok {
                        server_port = int(port)
                        i += 1
                    }
                }
            } else if strings.has_prefix(arg, "--port=") {
                if port_str := strings.trim_prefix(arg, "--port="); port_str != "" {
                    if port, ok := strconv.parse_int(port_str); ok {
                        server_port = int(port)
                    }
                }
            } else if strings.has_prefix(arg, "--debug=") {
                value := strings.trim_prefix(arg, "--debug=")
                SETTINGS.debug_build = value == "true" || value == "1"
            } else if strings.has_prefix(arg, "--opt=") {
                SETTINGS.optimization = strings.trim_prefix(arg, "--opt=")
            } else if strings.has_prefix(arg, "--out=") {
                SETTINGS.output_dir = strings.trim_prefix(arg, "--out=")
            } else if strings.has_prefix(arg, "--emsdk=") {
                SETTINGS.emscripten_sdk_dir = strings.trim_prefix(arg, "--emsdk=")
            } else if arg == "--run" {
                run_executable = true
            } else if arg == "--help" || arg == "-h" {
                fmt.println("Usage: build_game [options]")
                fmt.println("Options:")
                fmt.println("  --web           Build for web instead of desktop")
                fmt.println("  --serve         Start a web server after build (web only)")
                fmt.println("  --port=<num>    Specify port for web server (default: 8000)")
                fmt.println("  --debug=<bool>  Build with debug information (true/false)")
                fmt.println("  --opt=<level>   Optimization level (none, speed, size)")
                fmt.println("  --out=<dir>     Override output directory")
                fmt.println("  --emsdk=<dir>   Path to Emscripten SDK directory")
                fmt.println("  --run           Run the executable after a successful desktop build")
                os.exit(0)
            }
        }
    }
    
    // Configure build settings based on arguments
    if web_build {
        SETTINGS.build_type = .Web
        SETTINGS.output_dir = "build/web"
    } else {
        SETTINGS.build_type = .Desktop
        SETTINGS.output_dir = "build/desktop"
    }
    
    init_platform_config()
    
    when ODIN_OS == .Windows {
        SETTINGS.output_dir, _ = strings.replace_all(SETTINGS.output_dir, "/", "\\")
    }
    
    current_dir := os.get_current_directory()
    defer delete(current_dir)
    
    fmt.println("Starting build in directory:", current_dir)
    fmt.println("Build type:", SETTINGS.build_type)
    fmt.println("Output directory:", SETTINGS.output_dir)
    
    if !build_shaders() {
        fmt.println("Shader compilation failed")
        os.exit(1)
    }
    
    build_success := false
    
    switch SETTINGS.build_type {
        case .Desktop:
            build_success = build_desktop()
            if build_success {
                fmt.println("Desktop build created in", SETTINGS.output_dir)
            }
        
        case .Web:
            build_success = build_web()
            if build_success {
                fmt.println("Web build created in", SETTINGS.output_dir)
            }
    }
    
    if !build_success {
        fmt.println("Build failed!")
        os.exit(1)
    }
    
    if build_success && web_build && start_server {
        start_web_server(SETTINGS.output_dir, server_port)
    }

    // Run the executable if requested
    if build_success && !web_build && run_executable {
        exe_path: string
        when ODIN_OS == .Windows {
            exe_path = fmt.tprintf("%s\\%s%s", SETTINGS.output_dir, SETTINGS.executable_name, PLATFORM.executable_ext)
        } else {
            exe_path = fmt.tprintf("%s/%s%s", SETTINGS.output_dir, SETTINGS.executable_name, PLATFORM.executable_ext)
        }
        fmt.println("Running executable:", exe_path)
        run_command_background([]string{exe_path})
    }
} 