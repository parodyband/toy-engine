package game

import "core:math/linalg"
// import "core:image/png"
// import "core:log"
// import "core:slice"

import sapp  "lib/sokol/app"
import sg    "lib/sokol/gfx"
import sglue "lib/sokol/glue"
import slog  "lib/sokol/log"

// import util "lib/sokol_utils"
import gltf "lib/glTF2"

import "shader"

import ass "engine_core/asset"
import ren "engine_core/renderer"

Game_Memory :: struct {
	main_camera: Camera,
	game_input: Input_State,
	draw_calls: [dynamic]ren.Draw_Call,
}

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32
g: ^Game_Memory

Vertex :: struct {
	x, y, z: f32,
	color: u32,
	u, v: u16,
}

@export
game_app_default_desc :: proc() -> sapp.Desc {
	return {
		width = 1280,
		height = 720,
		sample_count = 4,
		window_title = "Toy Game",
		icon = { sokol_default = false },
		logger = { func = slog.func },
		html5_update_document_title = true,
	}
}

@export
game_init :: proc() {
	g = new(Game_Memory)

	// Initialize camera
	g.main_camera = Camera {
		fov = 60,
		position = {0, 20, -40},
		rotation = {0, 0, 0},
	}
	
	// Initialize input state
	g.game_input = Input_State {
		mouse_delta = {0, 0, 0},
		keys_down = make(map[sapp.Keycode]bool),
		mouse_buttons_down = make(map[sapp.Mousebutton]bool),
		mouse_locked = false,
	}

	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	add_mesh_by_name("assets/monkey.glb")
	add_mesh_by_name("assets/car.glb")
	add_mesh_by_name("assets/floor.glb")
}

add_mesh_by_name :: proc(path : string) {
	glb_data      := ass.load_glb_data_from_file(path)
	glb_mesh_data := ass.load_mesh_from_glb_data(glb_data)
	glb_texture   := ass.load_texture_from_glb_data(glb_data)

	mesh_renderer := ren.Mesh_Renderer{
		materials = []ass.Material{
			{ // Element 0
				tint_color     = {1.0,1.0,1.0,1.0},
				albedo_texture = glb_texture,
			},
		},
		mesh = glb_mesh_data,
		transform = {
			position = {0,0,0},
			rotation = {0,0,0},
			scale    = {1,1,1},
		},
	}

	add_draw_call(mesh_renderer)

	defer gltf.unload(glb_data)
}

add_draw_call :: proc(mesh_renderer : ren.Mesh_Renderer) {
	// bind draw calls
	draw_call : ren.Draw_Call
	
	// Set the renderer field
	draw_call.renderer = mesh_renderer
	
	// Set the index count
	draw_call.index_count = mesh_renderer.mesh.index_count

	assert(mesh_renderer.mesh.vertex_count > 0, "Error: Vertex Buffer Count for Mesh is 0")
	draw_call.bind.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.vertex_buffer_bytes), size = uint(len(mesh_renderer.mesh.vertex_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.normal_buffer_bytes) > 0, "Error: Normal Buffer Count for Mesh is 0")
	draw_call.bind.vertex_buffers[1] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.normal_buffer_bytes), size = uint(len(mesh_renderer.mesh.normal_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.uv_buffer_bytes) > 0, "Error: Uv Buffer Count for Mesh is 0")
	draw_call.bind.vertex_buffers[2] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.uv_buffer_bytes),     size = uint(len(mesh_renderer.mesh.uv_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.index_buffer_bytes) > 0, "Error: Index Buffer Count for Mesh is 0")
	draw_call.bind.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(mesh_renderer.mesh.index_buffer_bytes),  size = uint(len(mesh_renderer.mesh.index_buffer_bytes)) },
	})

	albedo_texture := mesh_renderer.materials[0].albedo_texture

	draw_call.bind.images[shader.IMG_tex] = sg.make_image({
		width  = albedo_texture.dimensions.width,
		height = albedo_texture.dimensions.height,
		data = {
			subimage = {
				0 = {
					0 = {
						ptr  = albedo_texture.final_pixels_ptr,
						size = albedo_texture.final_pixels_size,
					},
				},
			},
		},
	})

	draw_call.bind.samplers[shader.SMP_smp] = sg.make_sampler({
		max_anisotropy = 8,
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		mipmap_filter  = .LINEAR,
	})

	// shader and pipeline object
	draw_call.pipeline = sg.make_pipeline({
		shader = sg.make_shader(shader.texcube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				shader.ATTR_texcube_pos       = { format = .FLOAT3 },
				shader.ATTR_texcube_normal    = { format = .FLOAT3, buffer_index = 1 },
				shader.ATTR_texcube_texcoord0 = { format = .FLOAT2, buffer_index = 2 },
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CW,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})

	append(&g.draw_calls, draw_call)
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())

	move_camera(dt)

	// Opaque Pass

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })

	for i in 0..<len(g.draw_calls) {
		// vertex shader uniform with model-view-projection matrix
		vs_params := shader.Vs_Params {
			vp    = compute_mvp(g.main_camera.position, g.main_camera.rotation),
			model = compute_model_matrix(g.draw_calls[i].renderer.transform),
		}
		sg.apply_pipeline(g.draw_calls[i].pipeline)
		sg.apply_bindings(g.draw_calls[i].bind)
		sg.apply_uniforms(shader.UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.draw(0, i32(g.draw_calls[i].index_count), 1)
	}

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

compute_mvp :: proc (position : [3]f32, rotation : [3]f32) -> Mat4 {
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0)
    
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    flip_z := linalg.matrix4_scale_f32({1.0, 1.0, -1.0})
    return proj * flip_z * view
}

compute_model_matrix :: proc(t: ren.Transform) -> Mat4 {
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

force_reset: bool

@export
game_event :: proc(event: ^sapp.Event) {
	#partial switch event.type {
	 case .MOUSE_MOVE:
        g.game_input.mouse_delta = {event.mouse_dx, event.mouse_dy, 0}
            
	case .KEY_DOWN:
		g.game_input.keys_down[event.key_code] = true
		
	case .KEY_UP:
		g.game_input.keys_down[event.key_code] = false
		
	case .MOUSE_DOWN:
		g.game_input.mouse_buttons_down[event.mouse_button] = true
		
		if event.mouse_button == .RIGHT {
			sapp.lock_mouse(!g.game_input.mouse_locked)
			g.game_input.mouse_locked = !g.game_input.mouse_locked
		}
		
	case .MOUSE_UP:
		g.game_input.mouse_buttons_down[event.mouse_button] = false
	}
}

move_camera :: proc(deltaTime: f32) {
	// Camera movement speed
	move_speed: f32 = 50.0
    rot_speed:  f32 = 0.25

    // Mouse look
    mouse_dx := g.game_input.mouse_delta.x
    mouse_dy := g.game_input.mouse_delta.y
    if g.game_input.mouse_locked {
        g.main_camera.rotation.y += mouse_dx * rot_speed
        g.main_camera.rotation.x += mouse_dy * rot_speed
        g.main_camera.rotation.x = linalg.clamp(g.main_camera.rotation.x, -89.0, 89.0)
    }

    g.game_input.mouse_delta = {0, 0, 0}

    // for WASD
    pitch_rad := linalg.to_radians(g.main_camera.rotation.x)
    yaw_rad   := linalg.to_radians(g.main_camera.rotation.y)

    // forward vector (camera forward) based on yaw (Y) and pitch (X)
    forward: Vec3 = {
         linalg.sin(yaw_rad) * linalg.cos(pitch_rad),
        -linalg.sin(pitch_rad),
         linalg.cos(yaw_rad) * linalg.cos(pitch_rad),
    }

    // right vector (camera right) perpendicular to forward and world up
    right: Vec3 = {
        linalg.cos(yaw_rad),
        0,
        -linalg.sin(yaw_rad),
    }

    up: Vec3 = {0, 1, 0}
    move: Vec3 = {0, 0, 0}

    if g.game_input.keys_down[.W] {
        move += forward
    }
    if g.game_input.keys_down[.S] {
        move -= forward
    }
    if g.game_input.keys_down[.A] {
        move -= right
    }
    if g.game_input.keys_down[.D] {
        move += right
    }
    if g.game_input.keys_down[.Q] {
        move += up
    }
    if g.game_input.keys_down[.E] {
        move -= up
    }

	if g.game_input.keys_down[.ESCAPE] {
		sapp.quit()
	}

	// Normalize the movement vector and apply speed
	// Only move if the length of the vector is greater than a small threshold

	if linalg.length(move) > 0.001 {
        move = linalg.normalize(move)
        g.main_camera.position += move * move_speed * deltaTime
    }
}

@export
game_cleanup :: proc() {
	sg.shutdown()
	free(g)
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g`. Then that state carries over between hot reloads.
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}
