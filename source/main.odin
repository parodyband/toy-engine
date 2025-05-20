package main

import "base:runtime"

import "core:os"
import "core:log"
//import "core:image/png"
//import "core:slice"
import "core:math/linalg"

import "core:fmt"

import "glTF2"

import slog  "sokol/log"
import sapp  "sokol/app"
import sg    "sokol/gfx"
import sglue "sokol/glue"

import "engine_core/render"

import "web"

_ :: web
_ :: os
_ :: glTF2

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

draw_call :: struct {
    index      : int,
    pipeline   : sg.Pipeline,
    bind       : sg.Bindings,
    tint_params: Tint_Params,
    index_count: int,
    skip_render: bool,
}

draw_calls : [dynamic]draw_call

Tint_Params :: struct { tint : [4]f32 }

init :: proc "c" () {
    context = runtime.default_context()

    when IS_WEB {
        context.allocator = web.emscripten_allocator()
        context.temp_allocator = context.allocator
        runtime.default_temp_allocator_destroy(&runtime.global_default_temp_allocator_data)
        runtime.default_temp_allocator_init(&runtime.global_default_temp_allocator_data, 1*runtime.Megabyte, context.allocator)
    }

    sg.setup({
        environment = sglue.environment(),
        logger      = { func = slog.func },
    })

    glb_data      := render.load_glb_data_from_file("assets/test.glb")
    glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
    glb_texture   := render.load_texture_from_glb_data(glb_data)

    flask_mesh_renderer := render.mesh_renderer {
        render_materials = {
            0 = {
                tint_color     = {1,1,1,1},
                albedo_texture = glb_texture,
            }
        },
        render_mesh = glb_mesh_data,
        render_transfrom = {
            position = {0,0,0},
            rotation = {0,0,0},
            scale    = {1,1,1},
        }
    }

    add_draw_call(flask_mesh_renderer)

    defer glTF2.unload(glb_data)
}

add_draw_call :: proc(m : render.mesh_renderer) {

    state : draw_call

    state.index_count = m.render_mesh.index_count

    albedo_texture := m.render_materials[0].albedo_texture
    state.bind.images[IMG_tex] = sg.make_image({
        width  = i32(albedo_texture.width),
        height = i32(albedo_texture.height),
        data = { subimage = { 0 = { 0 = {
            ptr  = albedo_texture.final_pixels_ptr,
            size = albedo_texture.final_pixels_size,
        }}}},
    })

    if len(m.render_mesh.vertex_buffer_bytes) > 0 {
        state.bind.vertex_buffers[0] = sg.make_buffer({
            data = {
                ptr  = raw_data(m.render_mesh.vertex_buffer_bytes),
                size = uint(len(m.render_mesh.vertex_buffer_bytes)),
            },
        })
    } else {
        log.error("Vertex buffer is empty. Cannot create GPU buffer.")
    }

    // Create and bind normal buffer if data was loaded
    if len(m.render_mesh.normal_buffer_bytes) > 0 {
        state.bind.vertex_buffers[1] = sg.make_buffer({
            data = {
                ptr  = raw_data(m.render_mesh.normal_buffer_bytes),
                size = uint(len(m.render_mesh.normal_buffer_bytes)),
            },
            label = "normal-buffer", // Optional: for debugging
        })
    } else {
    // Not necessarily an error if normals are optional for the model/shader
        fmt.println("Normal buffer is empty or not loaded. Skipping GPU buffer creation for normals.")
    }

    // Create and bind UV buffer if data was loaded
    if len(m.render_mesh.uv_buffer_bytes) > 0 {
        state.bind.vertex_buffers[2] = sg.make_buffer({
            data = {
                ptr  = raw_data(m.render_mesh.uv_buffer_bytes),
                size = uint(len(m.render_mesh.uv_buffer_bytes)),
            },
            label = "uv-buffer", // Optional: for debugging
        })
    } else {
        fmt.println("UV buffer is empty or not loaded. Skipping GPU buffer creation for UVs.")
    }

    if len(m.render_mesh.index_buffer_bytes) > 0 {
        state.bind.index_buffer = sg.make_buffer({
            type = .INDEXBUFFER,
            data = {
                ptr = raw_data(m.render_mesh.index_buffer_bytes),
                size = uint(len(m.render_mesh.index_buffer_bytes)),
            },
        })
    } else {
        log.error("Index buffer is empty. Cannot create GPU buffer.")
    }

    state.bind.samplers[SMP_smp] = sg.make_sampler({
        max_anisotropy = 8,
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mipmap_filter = .LINEAR,
    })

    state.pipeline = sg.make_pipeline({
        shader = sg.make_shader( cube_shader_desc(sg.query_backend()) ),
        layout = {
            attrs = {
                ATTR_cube_position    = { format = .FLOAT3 },
                ATTR_cube_normal      = { format = .FLOAT3, buffer_index = 1 },
                ATTR_cube_texcoord0   = { format = .FLOAT2, buffer_index = 2 },
            },
        },
        index_type = .UINT16,
        face_winding = .CCW,
        cull_mode  = .BACK,
        depth = {
            write_enabled = true,
            compare = .LESS_EQUAL,
        },
    })

    state.tint_params.tint = [4]f32{ 1.0, 1.0, 1.0, 1.0 }
    
    state.index = len(draw_calls)

    append(&draw_calls, state)
}

frame :: proc "c" () {
    context = runtime.default_context()

    dt := f32(sapp.frame_duration())

    clear_pass :sg.Pass_Action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {.4,.6,1,1}},
        },
    }

    sg.begin_pass({
        action    = clear_pass, // only clear once, from first draw call
        swapchain = sglue.swapchain(),
    })
    
    vs_params := Vs_Params {
        mvp = compute_mvp_matrix(0, 0),
    }
    
    for i in 0..<len(draw_calls) {
        
        if draw_calls[i].skip_render {
            continue
        }

        sg.apply_pipeline(draw_calls[i].pipeline)
        sg.apply_bindings(draw_calls[i].bind)
    
        sg.apply_uniforms(
            ub_slot = UB_Tint,
            data = { ptr = &draw_calls[i].tint_params, size = size_of(draw_calls[i].tint_params) },
        )
    
        sg.apply_uniforms(
            ub_slot = UB_vs_params,
            data = {
                ptr = &vs_params,
                size = size_of(vs_params),
            },
        )
    
        sg.draw(0, i32(draw_calls[i].index_count), 1)
    }
    
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
        // Use same allocator for temporary allocations to avoid wasm allocator usage
        context.temp_allocator = context.allocator
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
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 100.0)
    view := linalg.matrix4_look_at_f32({0.0, -1.5, -25.0}, {}, {0.0, 1.0, 0.0})
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