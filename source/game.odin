package game

import "core:math/linalg"

import sapp  "lib/sokol/app"
import sg    "lib/sokol/gfx"
import sglue "lib/sokol/glue"
import slog  "lib/sokol/log"
import sgl   "lib/sokol/gl"
import gltf  "lib/glTF2"

import ass "engine_core/asset"
import ren "engine_core/renderer"
import deb "engine_core/debug"
import inp "engine_core/input"

import "gameplay"
import "shader"
import "common"

Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32
g: ^common.Game_Memory

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
	g = new(common.Game_Memory)

	gameplay.on_awake(g)
	
	// Initialize input state
	inp.init_input_state(&g.game_input)
	inp.init(&g.game_input)

	g.toggle_debug = false

	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	append(&g.lights, ren.Point_Light{
		color = {1,1,1,1},
		intensity = .5,
		transform = {
			position = {0,15,0},
		},
	})
	append(&g.lights, ren.Point_Light{
		color = {0,1,1,1},
		intensity = .5,
		transform = {
			position = {-15,10,-15},
		},
	})
	append(&g.lights, ren.Point_Light{
		color = {1,1,0,1},
		intensity = .5,
		transform = {
			position = {15,10,15},
		},
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
	t  := f32(sapp.frame_count())

	gameplay.on_update(dt, t, g)

	if inp.GetKeyDown(.F1) {
		g.toggle_debug = !g.toggle_debug
	}

	g.draw_calls[0].renderer.transform.position = {0,10,0}

	// Opaque Pass
	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.2, 0.2, 0.2, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })

	light_params : shader.Fs_Spot_Light
	for i in 0..<len(g.lights) {
		if i < len(light_params.color) {
			light_params.position[i].xyz = g.lights[i].transform.position
			light_params.color[i]        = g.lights[i].color
			light_params.intensity[i].x  = g.lights[i].intensity

			deb.draw_wire_sphere(g.lights[i].transform.position, .5, g.lights[i].color, &g.debug_draw_calls)
		}
	}

	for i in 0..<len(g.draw_calls) {
		vs_params := shader.Vs_Params {
			view_projection = ren.compute_view_projection(g.main_camera.position, g.main_camera.rotation),
			model = ren.compute_model_matrix(g.draw_calls[i].renderer.transform),
			view_pos = g.main_camera.position,
		}
		sg.apply_pipeline(g.draw_calls[i].pipeline)
		sg.apply_bindings(g.draw_calls[i].bind)
		sg.apply_uniforms(shader.UB_vs_params,     { ptr = &vs_params, size = size_of(vs_params) })
		sg.apply_uniforms(shader.UB_fs_spot_light, { ptr = &light_params, size = size_of(light_params) })
		sg.draw(0, i32(g.draw_calls[i].index_count), 1)
	}

	if g.toggle_debug {
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
	return size_of(common.Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^common.Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g`. Then that state carries over between hot reloads.
}

@(export)
game_force_restart :: proc() -> bool {
	return force_reset
}