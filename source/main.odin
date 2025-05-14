package main

import "base:runtime"

import "core:os"
import "core:log"
import "core:image/png"
import "core:slice"

import slog  "sokol/log"
import sapp  "sokol/app"
import sg    "sokol/gfx"
import sglue "sokol/glue"

import "web"

_ :: web
_ :: os

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

state: struct {
    pipeline   : sg.Pipeline,
    bind       : sg.Bindings,
    pass_action: sg.Pass_Action,
    tint_params: Tint_Params,
}


Tint_Params :: struct { tint : [4]f32 }


init :: proc "c" () {
    context = runtime.default_context()

    sg.setup({
        environment = sglue.environment(),
        logger      = { func = slog.func },
    })

    // Define Triangle Position
    quad_vertices := [?]f32 {
        // Positions      // Color0            // textcoord0
        -0.5,  0.5, 0.5,  1.0, 0.0, 0.0, 1.0,  0.0, 0.0,
         0.5,  0.5, 0.5,  0.0, 1.0, 0.0, 1.0,  1.0, 0.0,
         0.5, -0.5, 0.5,  0.0, 0.0, 1.0, 1.0,  1.0, 1.0,
        -0.5, -0.5, 0.5,  1.0, 1.0, 0.0, 1.0,  0.0, 1.0,
    }

    quad_indices := [?]u16{
        0,1,2,
        0,2,3,
    }

    // Bind the data
    state.bind.vertex_buffers[0] = sg.make_buffer({
        data = { 
            ptr  = &quad_vertices,
            size = size_of(quad_vertices),
        },
    })

    state.bind.index_buffer = sg.make_buffer({
        type = .INDEXBUFFER,
        data = { ptr = &quad_indices, size = size_of(quad_indices) },
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

    state.bind.samplers[SMP_smp] = sg.make_sampler({})

    state.pipeline = sg.make_pipeline({
        shader = sg.make_shader( quad_shader_desc(sg.query_backend()) ),
        index_type = .UINT16,
        layout = {
            attrs = {
                ATTR_quad_position    = { format = .FLOAT3 },
                ATTR_quad_color0      = { format = .FLOAT4 },
                ATTR_quad_textcoord0  = { format = .FLOAT2 },
            },
        },
    })

    state.tint_params.tint = [4]f32{ 1.0, 1.0, 1.0, 1.0 }

    state.pass_action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {0,0,0,1}},
        },
    }
}

frame :: proc "c" () {
    context = runtime.default_context()
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
    sg.draw(0,6,1)
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