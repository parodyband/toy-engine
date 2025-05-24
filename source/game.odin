package game

import "core:math/linalg"

import sapp  "lib/sokol/app"
import sg    "lib/sokol/gfx"
import sglue "lib/sokol/glue"
import slog  "lib/sokol/log"
import sgl   "lib/sokol/gl"

import gltf "lib/glTF2"

import "shader"

import ass "engine_core/asset"
import ren "engine_core/renderer"
import deb "engine_core/debug"
import inp "engine_core/input"

Game_Memory :: struct {
	main_camera       : ren.Camera,
	game_input        : inp.Input_State,
	draw_calls        : [dynamic]ren.Draw_Call,
	debug_draw_calls  : [dynamic]deb.Debug_Draw_Call,
	debug_pipelines   : [deb.Depth_Test_Mode]sgl.Pipeline,
	toggle_debug      : bool,
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
	g.main_camera = ren.Camera {
		fov = 60,
		position = {0, 20, -40},
		rotation = {0, 0, 0},
	}
	
	// Initialize input state
	inp.init_input_state(&g.game_input)
	inp.init(&g.game_input)

	g.toggle_debug = false

	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	deb.init(&g.debug_pipelines)

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

draw_debug :: proc() {
	if len(g.debug_draw_calls) == 0 {
		return
	}

	// Setup sokol-gl for debug drawing with proper depth testing
	sgl.defaults()
	
	// Sort debug calls by depth test mode to minimize pipeline switches
	current_depth_mode := deb.Depth_Test_Mode.Front
	sgl.load_pipeline(g.debug_pipelines[current_depth_mode])
	
	// Compute projection matrix (same as renderer)
	proj := linalg.matrix4_perspective(g.main_camera.fov * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0)
	flip_z := linalg.matrix4_scale_f32({1.0, 1.0, -1.0})
	proj_flip := proj * flip_z
	
	// Compute view matrix (inverse camera transform)
	inv_rot_pitch := linalg.matrix4_rotate_f32(-g.main_camera.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	inv_rot_yaw   := linalg.matrix4_rotate_f32(-g.main_camera.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
	inv_rot_roll  := linalg.matrix4_rotate_f32(-g.main_camera.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
	trans := linalg.matrix4_translate_f32({-g.main_camera.position[0], -g.main_camera.position[1], -g.main_camera.position[2]})
	view_rot_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
	view := view_rot_inv * trans
	
	// Load matrices into sokol-gl
	sgl.matrix_mode_projection()
	sgl.load_matrix(&proj_flip[0][0])
	
	sgl.matrix_mode_modelview()
	sgl.load_matrix(&view[0][0])

	// Draw all debug primitives
	for i in 0..<len(g.debug_draw_calls) {
		// Get the depth test mode for this draw call
		depth_mode: deb.Depth_Test_Mode
		switch data in g.debug_draw_calls[i].data {
			case deb.Line_Segment_Data:
				depth_mode = data.depth_test
			case deb.Wire_Sphere_Data:
				depth_mode = data.depth_test
			case deb.Wire_Cube_Data:
				depth_mode = data.depth_test
		}
		
		// Switch pipeline if needed
		if depth_mode != current_depth_mode {
			current_depth_mode = depth_mode
			sgl.load_pipeline(g.debug_pipelines[current_depth_mode])
		}
		
		// Draw the primitive
		switch draw_data in g.debug_draw_calls[i].data {
			case deb.Line_Segment_Data:
				sgl.c4f(draw_data.color[0], draw_data.color[1], draw_data.color[2], draw_data.color[3])
				sgl.begin_lines()
				sgl.v3f(draw_data.start[0], draw_data.start[1], draw_data.start[2])
				sgl.v3f(draw_data.end[0], draw_data.end[1], draw_data.end[2])
				sgl.end()
				
			case deb.Wire_Sphere_Data:
				deb.draw_wire_sphere_immediate(draw_data.center, draw_data.radius, draw_data.color)
				
			case deb.Wire_Cube_Data:
				deb.draw_wire_cube_immediate(draw_data.transform, draw_data.color)
		}
	}

	//clear debug draw calls
	clear(&g.debug_draw_calls)

	sgl.draw()
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())

	move_camera(dt)

	g.draw_calls[0].renderer.transform.position = {0,10,0}

	if inp.GetKeyDown(.F1) {
		g.toggle_debug = !g.toggle_debug
	}

	// Opaque Pass
	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })

	for i in 0..<len(g.draw_calls) {
		vs_params := shader.Vs_Params {
			view_projection = ren.compute_view_projection(g.main_camera.position, g.main_camera.rotation),
			model = ren.compute_model_matrix(g.draw_calls[i].renderer.transform),
		}
		sg.apply_pipeline(g.draw_calls[i].pipeline)
		sg.apply_bindings(g.draw_calls[i].bind)
		sg.apply_uniforms(shader.UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
		sg.draw(0, i32(g.draw_calls[i].index_count), 1)
	}

	if g.toggle_debug {
		deb.draw_wire_sphere({0, 0, 0}, 2.0, {0, 1, 0, 1}, &g.debug_draw_calls, .Off)
		draw_debug()
	}

	sg.end_pass()
	sg.commit()

	// Clear input state changes for next frame
	inp.clear_frame_states()

	free_all(context.temp_allocator)
}

force_reset: bool

@export
game_event :: proc(event: ^sapp.Event) {
	#partial switch event.type {
	 case .MOUSE_MOVE:
        inp.process_mouse_move(event.mouse_dx, event.mouse_dy)
            
	case .KEY_DOWN:
		inp.process_key_down(event.key_code)
		
	case .KEY_UP:
		inp.process_key_up(event.key_code)
		
	case .MOUSE_DOWN:
		inp.process_mouse_button_down(event.mouse_button)
		
		if event.mouse_button == .RIGHT {
			inp.toggle_mouse_lock()
		}
		
	case .MOUSE_UP:
		inp.process_mouse_button_up(event.mouse_button)
	}
}

move_camera :: proc(deltaTime: f32) {
	// Camera movement speed
	move_speed: f32 = 50.0
    rot_speed:  f32 = 0.25

    // Mouse look
    mouse_delta := inp.get_mouse_delta()
    mouse_dx := mouse_delta.x
    mouse_dy := mouse_delta.y
    if inp.is_mouse_locked() {
        g.main_camera.rotation.y += mouse_dx * rot_speed
        g.main_camera.rotation.x += mouse_dy * rot_speed
        g.main_camera.rotation.x = linalg.clamp(g.main_camera.rotation.x, -89.0, 89.0)
    }

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

    if inp.GetKey(.W) {
        move += forward
    }
    if inp.GetKey(.S) {
        move -= forward
    }
    if inp.GetKey(.A) {
        move -= right
    }
    if inp.GetKey(.D) {
        move += right
    }
    if inp.GetKey(.Q) {
        move += up
    }
    if inp.GetKey(.E) {
        move -= up
    }

	if inp.GetKey(.ESCAPE) {
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
	// Destroy all debug pipelines
	for mode in deb.Depth_Test_Mode {
		sgl.destroy_pipeline(g.debug_pipelines[mode])
	}
	sgl.shutdown()
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
