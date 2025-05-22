package main

import "base:runtime"

import "core:os"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"

import "core:fmt"
import "core:math"

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
    index_count: int,
    skip_render: bool,
    renderer   : render.mesh_renderer,
    shadow     : shadow_pass,
}

shadow_pass :: struct {
    pipeline    : sg.Pipeline,
    bind        : sg.Bindings
}

// Global resources for the shadow map pass
shadow_map        : sg.Image
shadow_depth_img  : sg.Image
shadow_attachments: sg.Attachments
shadow_clear_pass : sg.Pass_Action
shadow_sampler    : sg.Sampler

draw_calls : [dynamic]draw_call

light :: struct {
    direction : [3]f32,
    color     : [4]f32,
}

mainLight :: light {
    direction = {-.5,1,-.5},
    color     = {1,1,1,1},
}

camera :: struct {
    fov : f32,
    position : [3]f32,
    rotation : [3]f32,
}

mainCamera := camera {
    fov = 60,
    position = {0,20,-40},
    rotation = {0,0,0},
}

input_state :: struct {
    mouse_delta: Vec3,
    keys_down: map[sapp.Keycode]bool,
    mouse_buttons_down: map[sapp.Mousebutton]bool,
    mouse_locked: bool,
}

game_input := input_state{
    mouse_delta = {0, 0, 0},
    keys_down = make(map[sapp.Keycode]bool),
    mouse_buttons_down = make(map[sapp.Mousebutton]bool),
    mouse_locked = false,
}


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

    // --- Shadow map resources ---
    shadow_clear_pass = {
        colors = {
            0 = {
                load_action  = .CLEAR,
                clear_value  = {1.0, 1.0, 1.0, 1.0},
            },
        },
    }

    shadow_map = sg.make_image({
        render_target = true,
        width         = 2048,
        height        = 2048,
        pixel_format  = .RGBA8,
        sample_count  = 1,
        label         = "shadow-map",
    })

    shadow_depth_img = sg.make_image({
        render_target = true,
        width         = 2048,
        height        = 2048,
        pixel_format  = .DEPTH,
        sample_count  = 1,
        label         = "shadow-depth-buffer",
    })

    shadow_attachments = sg.make_attachments(sg.Attachments_Desc{
        colors = {
            0 = { image = shadow_map },
        },
        depth_stencil = { image = shadow_depth_img },
        label = "shadow-pass",
    })

    // Sampler for shadow map sampling
    shadow_sampler = sg.make_sampler({
        wrap_u         = .CLAMP_TO_EDGE,
        wrap_v         = .CLAMP_TO_EDGE,
        min_filter     = .LINEAR,
        mag_filter     = .LINEAR,
        mipmap_filter  = .LINEAR,
    })

    {
        glb_data      := render.load_glb_data_from_file("assets/test.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        flask_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {-10,0,-10},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(flask_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }

    {
        glb_data      := render.load_glb_data_from_file("assets/floor.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {0,0,0},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }

    {
        glb_data      := render.load_glb_data_from_file("assets/sphere.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {0,0,0},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }

    {
        glb_data      := render.load_glb_data_from_file("assets/monkey.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {0,0,0},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }

    {
        glb_data      := render.load_glb_data_from_file("assets/car.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {0,0,0},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }

    {
        glb_data      := render.load_glb_data_from_file("assets/1x1 cube.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {0,0,0},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }
    {
        glb_data      := render.load_glb_data_from_file("assets/1x1 cube.glb")
        glb_mesh_data := render.load_mesh_from_glb_data(glb_data)
        glb_texture   := render.load_texture_from_glb_data(glb_data)

        floor_mesh_renderer := render.mesh_renderer {
            render_materials = []render.material{
                { // Element 0
                    tint_color     = {1.0,1.0,1.0,1.0},
                    albedo_texture = glb_texture,
                },
            },
            render_mesh = glb_mesh_data,
            render_transform = {
                position = {1,0,1},
                rotation = {0,0,0},
                scale    = {1,1,1},
            }
        }

        add_draw_call(floor_mesh_renderer, context.allocator)
        defer glTF2.unload(glb_data)
    }
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    
    #partial switch event.type {
        case .MOUSE_MOVE:
            game_input.mouse_delta = {event.mouse_dx, event.mouse_dy, 0}
            
        case .KEY_DOWN:
            game_input.keys_down[event.key_code] = true
            
        case .KEY_UP:
            game_input.keys_down[event.key_code] = false
            
        case .MOUSE_DOWN:
            game_input.mouse_buttons_down[event.mouse_button] = true
            
            if event.mouse_button == .RIGHT {
                sapp.lock_mouse(!game_input.mouse_locked)
                game_input.mouse_locked = !game_input.mouse_locked
            }
            
        case .MOUSE_UP:
            game_input.mouse_buttons_down[event.mouse_button] = false
    }
}

update :: proc(time: f32, deltaTime: f32) {
    move_speed: f32 = 50.0
    rot_speed:  f32 = 0.3

    // Mouse look
    mouse_dx := game_input.mouse_delta.x
    mouse_dy := game_input.mouse_delta.y
    if game_input.mouse_locked {
        mainCamera.rotation.y += mouse_dx * rot_speed
        mainCamera.rotation.x += mouse_dy * rot_speed
        mainCamera.rotation.x = glsl.clamp(mainCamera.rotation.x, -89.0, 89.0)
    }

    game_input.mouse_delta = {0, 0, 0}

    // for WASD
    pitch_rad := glsl.radians(mainCamera.rotation.x)
    yaw_rad   := glsl.radians(mainCamera.rotation.y)

    // forward vector (camera forward) based on yaw (Y) and pitch (X)
    forward: Vec3 = {
        glsl.sin(yaw_rad) * glsl.cos(pitch_rad),
        -glsl.sin(pitch_rad),
        glsl.cos(yaw_rad) * glsl.cos(pitch_rad)
    }

    // right vector (camera right) perpendicular to forward and world up
    right: Vec3 = {
        glsl.cos(yaw_rad),
        0,
        -glsl.sin(yaw_rad)
    }

    up: Vec3 = {0, 1, 0}
    move: Vec3 = {0, 0, 0}

    if game_input.keys_down[.W] {
        move += forward
    }
    if game_input.keys_down[.S] {
        move -= forward
    }
    if game_input.keys_down[.A] {
        move -= right
    }
    if game_input.keys_down[.D] {
        move += right
    }
    if game_input.keys_down[.Q] {
        move += up
    }
    if game_input.keys_down[.E] {
        move -= up
    }

    // if game_input.keys_down[.ESCAPE] {
    //     game_input.mouse_locked = false
    //     sapp.show_mouse(true)
    // }

    // normalize if moving diagonally
    if glsl.length(move) > 0.001 {
        move = glsl.normalize(move)
        mainCamera.position += move * move_speed * deltaTime
    }

    if len(draw_calls) > 0 {
        draw_calls[0].renderer.render_transform.rotation.y += deltaTime * 50
        //draw_calls[0].renderer.render_transform.position.y = math.abs(math.sin(time * 0.05))
    }
}

add_draw_call :: proc(m : render.mesh_renderer, allocator: runtime.Allocator) {

    state : draw_call

    state.index_count = m.render_mesh.index_count

    if len(m.render_materials) == 0 {
        log.error("add_draw_call: mesh_renderer (m) has no materials. Cannot create draw call.");
        return;
    }

    // buffer bindings
    {
        current_material_from_m := m.render_materials[0] 

        albedo_texture := current_material_from_m.albedo_texture
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
    }

    // Shadow Bindings
    {
        state.shadow.pipeline = sg.make_pipeline({
            shader = sg.make_shader(shadow_shader_desc(sg.query_backend())),
            layout = {
                buffers = {
                    0 = {
                        stride = 3 * size_of(f32), // pos+normal stride like original vertex buffer
                    }
                },
                attrs = {
                    ATTR_cube_position    = { format = .FLOAT3 },
                },
            },
            index_type = .UINT16,
            cull_mode = .FRONT,
            sample_count = 1,
            face_winding = .CCW,
            colors = {
                0 = {
                    pixel_format = .RGBA8
                }
            },
            depth = {
                pixel_format = .DEPTH,
                write_enabled = true,
                compare = .LESS_EQUAL,
                bias = 0.5,
                bias_slope_scale = 1.0,
            },
            label = "shadow-pipeline"
        })

        state.shadow.bind = {
            vertex_buffers = {
                0 = state.bind.vertex_buffers[0]
            },
            index_buffer = state.bind.index_buffer
        }
    }
    
    // Opaque Bindings
    {
        state.bind.samplers[SMP_smp] = sg.make_sampler({
            max_anisotropy = 8,
            min_filter = .LINEAR,
            mag_filter = .LINEAR,
            mipmap_filter = .LINEAR,
        })

        // Bind shadow map and sampler
        state.bind.images[IMG_shadow_map]   = shadow_map
        state.bind.samplers[SMP_shadow_smp] = shadow_sampler

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
            face_winding = .CW,
            cull_mode  = .BACK,
            depth = {
                write_enabled = true,
                compare = .LESS_EQUAL,
            },
        })
    }

    
    state.index = len(draw_calls)

    // Prepare state.renderer for long-term storage in draw_calls
    state.renderer.render_mesh = m.render_mesh;           // Copy mesh struct (contains slices, but their data comes from glb_data which is alive)
    state.renderer.render_transform = m.render_transform; // Copy transform struct

    // Deep copy materials
    if len(m.render_materials) > 0 {
        cloned_materials_slice := make([]render.material, len(m.render_materials), allocator);
        copy(cloned_materials_slice, m.render_materials); // This copies the material structs themselves
        state.renderer.render_materials = cloned_materials_slice;
    } else {
        state.renderer.render_materials = nil; 
    }

    append(&draw_calls, state)
}

frame :: proc "c" () {
    context = runtime.default_context()

	t  := f32(sapp.frame_count())
    dt := f32(sapp.frame_duration())

	update(t, dt)

    // --- Shadow Pass ---
    // Compute a single-cascade (close-up) shadow camera that tracks the main camera.

    // Light view (use mainLight.direction directly)
    light_dir : Vec3 = linalg.normalize(mainLight.direction)

    // Camera forward (same calculation as in update())
    pitch_rad := glsl.radians(mainCamera.rotation.x)
    yaw_rad   := glsl.radians(mainCamera.rotation.y)
    cam_forward : Vec3 = {
        glsl.sin(yaw_rad) * glsl.cos(pitch_rad),
        glsl.sin(pitch_rad),
        glsl.cos(yaw_rad) * glsl.cos(pitch_rad)
    }

    // Choose a slice up to 100 units from the camera
    cascade_range : f32 = 30.0
    slice_center  : Vec3 = mainCamera.position + (cam_forward * (cascade_range * 0.5))

    // Place the light eye so that it looks toward the slice center
    light_eye_pos : Vec3 = slice_center + (light_dir * cascade_range)

    // Determine a robust up vector for the light's view matrix
    light_up_vector: Vec3
    // If light_dir is too close to world Y-axis (e.g. light pointing straight up/down)
    if math.abs(linalg.dot(light_dir, Vec3{0,1,0})) > 0.99 {
        light_up_vector = Vec3{0,0,1} // Use Z-axis as up
    } else {
        light_up_vector = Vec3{0,1,0} // Otherwise, use Y-axis as up
    }
    light_view := linalg.matrix4_look_at(light_eye_pos, slice_center, light_up_vector)

    // Orthographic extents large enough to cover the slice (simple bounding sphere)
    ortho_extent : f32 = cascade_range * 1.5
    light_projection := linalg.matrix_ortho3d_f32(-ortho_extent, ortho_extent,
                                                  -ortho_extent, ortho_extent,
                                                  0.1, 2.0 * cascade_range)

    light_view_proj := light_projection * light_view

    // Render depth
    sg.push_debug_group("Directional Light Depth Pass")
    sg.begin_pass({
        action      = shadow_clear_pass,
        attachments = shadow_attachments,
        label = "Directional Light Depth Pass"
    })

    for i in 0..<len(draw_calls) {
        if draw_calls[i].skip_render {
            continue
        }

        sg.apply_pipeline(draw_calls[i].shadow.pipeline)
        sg.apply_bindings(draw_calls[i].shadow.bind)

        model := compute_model_matrix(draw_calls[i].renderer.render_transform)

        shadow_params : Vs_Shadow_Params = {
            mvp = light_view_proj * model,
        }

        sg.apply_uniforms(UB_vs_shadow_params, {
            ptr = &shadow_params,
            size = size_of(Vs_Shadow_Params),
        })

        sg.draw(0, i32(draw_calls[i].index_count), 1)
    }
    sg.end_pass()
    sg.pop_debug_group()


    // Opaque

    clear_pass :sg.Pass_Action = {
        colors = {
            0 = {load_action = .CLEAR, clear_value = {.4,.6,1,1}},
        },
    }

    sg.begin_pass({
        action    = clear_pass,
        swapchain = sglue.swapchain(),
    })
    
    vp_matrix := compute_camera_view_projection_matrix(mainCamera.position, mainCamera.rotation)

    for i in 0..<len(draw_calls) {
        
        if draw_calls[i].skip_render {
            continue
        }

        sg.apply_pipeline(draw_calls[i].pipeline)
        sg.apply_bindings(draw_calls[i].bind)
    
        vs_params : Vsparams
        vs_params.mvp   = vp_matrix
        vs_params.model = compute_model_matrix(draw_calls[i].renderer.render_transform)
        vs_params.light_mvp = light_view_proj
        vs_params.diff_color = draw_calls[i].renderer.render_materials[0].tint_color

        aligned_tint_uniform: Tintblock
        aligned_tint_uniform.tint = draw_calls[i].renderer.render_materials[0].tint_color
        //fmt.printf("Debug tint: %v\n", aligned_tint_uniform.tint) // DEBUG LINE

        light_direction_uniform: Mainlightparams
        light_direction_uniform.light_direction = mainLight.direction
        light_direction_uniform.light_color     = mainLight.color

        sg.apply_uniforms(
            ub_slot = UB_VSParams,
            data = {
                ptr = &vs_params,
                size = size_of(vs_params),
            },
        )

        sg.apply_uniforms(
            ub_slot = UB_TintBlock,
            data = {
                ptr = &aligned_tint_uniform,
                size = size_of(Tintblock),
            },
        )

        sg.apply_uniforms(
            ub_slot = UB_MainLightParams,
            data = {
                ptr = &light_direction_uniform,
                size = size_of(Mainlightparams)
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
        context.temp_allocator = context.allocator
    }
    context.logger = log.create_console_logger(lowest = .Info, opt = {.Level, .Short_File_Path, .Line, .Procedure})
    sapp.run({
        init_cb      = init,
        frame_cb     = frame,
        cleanup_cb   = cleanup,
        event_cb     = event,
        width        = 1280,
        height       = 720,
        window_title = "Toy Engine",
        icon         = { sokol_default = false },
        logger       = { func = slog.func },
        high_dpi     = true,
        html5_update_document_title = true,
    })
}

compute_camera_view_projection_matrix :: proc (position : [3]f32, rotation : [3]f32) -> Mat4 {
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0)
    
    // Create INVERSE rotation matrices for camera orientation
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    // R_inverse from Yaw, then Pitch, then Roll camera orientation: (Roll_inv * Pitch_inv * Yaw_inv)
    // This makes the camera rotate around its own position.
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    
    // flip Z axis so +Z is forward (Unity-style) leaving +Y up, requires front face winding swap
    flip_z := linalg.matrix4_scale_f32({1.0, 1.0, -1.0})
    return proj * flip_z * view
}

// (position, rotation (deg), scale)
compute_model_matrix :: proc(t: render.transform) -> Mat4 {
    position := t.position
    trans := linalg.matrix4_translate_f32({position[0], position[1], position[2]})

    // Rotation matrices (convert degrees to radians)
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    rot_pitch := linalg.matrix4_rotate_f32(t.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(t.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(t.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})

    // Scale matrix
    scale := linalg.matrix4_scale_f32({t.scale[0], t.scale[1], t.scale[2]})

    // Combine rotations: roll, then pitch, then yaw (matching camera rotation order)
    rot_combined := rot_yaw * rot_pitch * rot_roll

    // Final model matrix: T * R * S (Translation * Rotation * Scale)
    // This ensures objects rotate and scale around their own origin point
    return trans * rot_combined * scale
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