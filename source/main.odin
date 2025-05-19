package main

import "base:runtime"

import "core:os"
import "core:log"
import "core:image/png"
import "core:slice"
import "core:math/linalg"

import "core:fmt"

import "glTF2"

import slog  "sokol/log"
import sapp  "sokol/app"
import sg    "sokol/gfx"
import sglue "sokol/glue"

import "web"

_ :: web
_ :: os
_ :: glTF2

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

state: struct {
    pipeline   : sg.Pipeline,
    bind       : sg.Bindings,
    pass_action: sg.Pass_Action,
    tint_params: Tint_Params,
    rx         : f32,
    ry         : f32,
}


Tint_Params :: struct { tint : [4]f32 }


init :: proc "c" () {
    context = runtime.default_context()

    sg.setup({
        environment = sglue.environment(),
        logger      = { func = slog.func },
    })

    // Define Triangle Position
    cube_vertices := [?]f32 {
        // Positions        // Color0             // texcoord0
        // Front face
        -1.0, -1.0, -1.0,   0.0, 1.0, 0.0, 1.0,   0.0, 0.0,
         1.0, -1.0, -1.0,   0.0, 1.0, 0.0, 1.0,   1.0, 0.0,
         1.0,  1.0, -1.0,   0.0, 1.0, 0.0, 1.0,   1.0, 1.0,
        -1.0,  1.0, -1.0,   0.0, 1.0, 0.0, 1.0,   0.0, 1.0,

        // Back face
        -1.0, -1.0,  1.0,   1.0, 0.0, 0.0, 1.0,   1.0, 0.0,
         1.0, -1.0,  1.0,   1.0, 0.0, 0.0, 1.0,   0.0, 0.0,
         1.0,  1.0,  1.0,   1.0, 0.0, 0.0, 1.0,   0.0, 1.0,
        -1.0,  1.0,  1.0,   1.0, 0.0, 0.0, 1.0,   1.0, 1.0,

        // Left face
        -1.0, -1.0, -1.0,   0.0, 0.0, 1.0, 1.0,   0.0, 0.0,
        -1.0,  1.0, -1.0,   0.0, 0.0, 1.0, 1.0,   1.0, 0.0,
        -1.0,  1.0,  1.0,   0.0, 0.0, 1.0, 1.0,   1.0, 1.0,
        -1.0, -1.0,  1.0,   0.0, 0.0, 1.0, 1.0,   0.0, 1.0,

        // Right face
         1.0, -1.0, -1.0,   1.0, 0.5, 0.0, 1.0,   1.0, 0.0,
         1.0,  1.0, -1.0,   1.0, 0.5, 0.0, 1.0,   0.0, 0.0,
         1.0,  1.0,  1.0,   1.0, 0.5, 0.0, 1.0,   0.0, 1.0,
         1.0, -1.0,  1.0,   1.0, 0.5, 0.0, 1.0,   1.0, 1.0,

        // Bottom face
        -1.0, -1.0, -1.0,   0.0, 0.5, 1.0, 1.0,   0.0, 1.0,
        -1.0, -1.0,  1.0,   0.0, 0.5, 1.0, 1.0,   0.0, 0.0,
         1.0, -1.0,  1.0,   0.0, 0.5, 1.0, 1.0,   1.0, 0.0,
         1.0, -1.0, -1.0,   0.0, 0.5, 1.0, 1.0,   1.0, 1.0,

        // Top face
        -1.0,  1.0, -1.0,   1.0, 0.0, 0.5, 1.0,   0.0, 1.0,
        -1.0,  1.0,  1.0,   1.0, 0.0, 0.5, 1.0,   0.0, 0.0,
         1.0,  1.0,  1.0,   1.0, 0.0, 0.5, 1.0,   1.0, 0.0,
         1.0,  1.0, -1.0,   1.0, 0.0, 0.5, 1.0,   1.0, 1.0,
    }

    cube_indices := [?]u16{
      0,  1,  2,   0, 2, 3,
  		6,  5,  4,   7, 6, 4,
  		8,  9,  10,  8, 10, 11,
  		14, 13, 12,  15, 14, 12,
  		16, 17, 18,  16, 18, 19,
  		22, 21, 20,  23, 22, 20,
    }

    glb_data, error := glTF2.load_from_file("assets/test.glb")

    switch err in error {
        case glTF2.GLTF_Error: {
            fmt.printfln("GLTF Error: %d", err)
        }
        case glTF2.JSON_Error: {
            fmt.printfln("GLTF Json Error: %d", err)
        }
    }


    defer glTF2.unload(glb_data)

    for mesh in glb_data.meshes {
      fmt.printfln("Mesh found! Name: %s", mesh.name)
    }


    // Bind the data
    state.bind.vertex_buffers[0] = sg.make_buffer({
        data = { 
            ptr  = &cube_vertices,
            size = size_of(cube_vertices),
        },
    })

    state.bind.index_buffer = sg.make_buffer({
        type = .INDEXBUFFER,
        data = { ptr = &cube_indices, size = size_of(cube_indices) },
    })

    if img_data, img_data_ok := read_entire_file("assets/test.png", context.temp_allocator); img_data_ok {

        if img, img_err := png.load_from_bytes(img_data, allocator = context.temp_allocator); img_err == nil {
            // Handle nonsquare images by using the actual width and height from the image
            state.bind.images[IMG_tex] = sg.make_image({
                width = i32(img.width),
                height = i32(img.height),
                data = {
                    subimage = {
                        0 = {
                            0 = { ptr = raw_data(img.pixels.buf), size = uint(slice.size(img.pixels.buf[:])) },
                        },
                    },
                },
            })
            
            // Optionally, you may want to store the width/height for later use (e.g., for UV scaling)
            // state.image_width = img.width;
            // state.image_height = img.height;
        } else {
            log.error(img_err)
        }
    } else {
        log.error("Failed Loading Texture")
    }
    //limits := sg.query_limits()
    state.bind.samplers[SMP_smp] = sg.make_sampler({
        max_anisotropy = 8,
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mipmap_filter = .LINEAR
    })

    state.pipeline = sg.make_pipeline({
        shader = sg.make_shader( cube_shader_desc(sg.query_backend()) ),
        layout = {
            attrs = {
                ATTR_cube_position    = { format = .FLOAT3 },
                ATTR_cube_color0      = { format = .FLOAT4 },
                ATTR_cube_textcoord0  = { format = .FLOAT2 },
            },
        },
        index_type = .UINT16,
        cull_mode  = .BACK,
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL,
        },
    })

    state.tint_params.tint = [4]f32{ 1.0, 1.0, 1.0, 1.0 }

    state.pass_action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {.5,0,0,1}},
        },
    }
}

frame :: proc "c" () {
    context = runtime.default_context()

    dt := f32(sapp.frame_duration())
    state.rx += 60 * dt
    state.ry += 120 * dt

    vs_params := Vs_Params {
        mvp = compute_mvp_matrix(state.rx, state.ry),
    }

    sg.begin_pass({
        action    = state.pass_action,
        swapchain = sglue.swapchain(),
    })
    sg.apply_pipeline(state.pipeline)
    sg.apply_bindings(state.bind)
    sg.apply_uniforms(
        ub_slot = UB_Tint,
        data    = { ptr = &state.tint_params, size = size_of(state.tint_params) }, 
    )
    sg.apply_uniforms(
        ub_slot = UB_vs_params,
        data = {
            ptr = &vs_params,
            size = size_of(vs_params),
        },
    )
    sg.draw(0,36,1)
    sg.end_pass()
    sg.commit()
}

cleanup :: proc "c" () {
    context = runtime.default_context()
    sg.shutdown()
}

main :: proc() {
    when IS_WEB {
        context.allocator = web.emscripten_allocator()

        runtime.init_global_temporary_allocator(1*runtime.Megabyte)
    }
    context.logger = log.create_console_logger(lowest = .Info, opt = {.Level, .Short_File_Path, .Line, .Procedure})
    sapp.run({
        init_cb      = init,
        frame_cb     = frame,
        cleanup_cb   = cleanup,
        width        = 700,
        height       = 700,
        window_title = "Window",
        icon         = { sokol_default = true },
        logger       = { func = slog.func },
        high_dpi     = true,
        html5_update_document_title = true,
    })
}

compute_mvp_matrix :: proc (rx, ry: f32) -> Mat4 {
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 10.0)
	view := linalg.matrix4_look_at_f32({0.0, -1.5, -6.0}, {}, {0.0, 1.0, 0.0})
	view_proj := proj * view
	rxm := linalg.matrix4_rotate_f32(rx * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	rym := linalg.matrix4_rotate_f32(ry * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
	model := rxm * rym
	return view_proj * model
}

@(require_results)
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	when IS_WEB {
		return web.read_entire_file(name, allocator, loc)
	} else {
		return os.read_entire_file(name, allocator, loc)
	}
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	when IS_WEB {
		return web.write_entire_file(name, data, truncate)
	} else {
		return os.write_entire_file(name, data, truncate)
	}
}