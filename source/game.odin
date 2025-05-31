package game

import "core:math/linalg"
import "core:slice"

import sapp  "lib/sokol/app"
import sg    "lib/sokol/gfx"
import sglue "lib/sokol/glue"
import slog  "lib/sokol/log"
import sgl   "lib/sokol/gl"
import gltf  "lib/glTF2"

import ass   "engine_core/asset"
import ren   "engine_core/renderer"
import deb   "engine_core/debug"
import inp   "engine_core/input"
import trans "engine_core/transform"

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
	
	inp.init_input_state(&g.game_input)

	g.toggle_debug = false

	game_hot_reloaded(g)

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	// Initialize shadow resources once
	g.shadow_resources.shadow_map = sg.make_image({
		render_target = true,
		width         = 2048,
		height        = 2048,
		pixel_format  = .DEPTH,
		sample_count  = 1,
		label         = "shadow-map",
	})

	g.shadow_resources.shadow_sampler = sg.make_sampler({
		wrap_u         = .CLAMP_TO_EDGE,
		wrap_v         = .CLAMP_TO_EDGE,
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		compare        = .LESS,
		label          = "shadow-sampler",
	})

	g.shadow_resources.shadow_attachments = sg.make_attachments({
		depth_stencil = { image = g.shadow_resources.shadow_map },
		label = "shadow-attachments",
	})

	append(&g.lights, ren.Point_Light{
		color = {0,1,1,1},
		intensity = 3,
		transform = {
			position = {-5,5,-5},
			scale    = {10,10,10},
		},
	})

	append(&g.lights, ren.Directional_Light{
		color = {1,1,1,1},
		intensity = .8,
		transform = {
			position = {-5 ,20, -5},
			rotation = {70, 45, 0},
			scale    = { 1, 1, 1},
		},
		bounds = {
			height = 60,
			width  = 60,
			half_depth = 75,
		},
	})

	deb.init(&g.debug_pipelines)

	add_mesh_by_name("assets/monkey.glb", {-10,10,-10})
	add_mesh_by_name("assets/car.glb")
	add_mesh_by_name("assets/1x1 cube.glb")
	add_mesh_by_name("assets/floor.glb")
}

add_mesh_by_name :: proc(path : string, position : [3]f32 = {0,0,0}) {
	glb_data      := ass.load_glb_data_from_file(path)
	glb_mesh_data := ass.load_mesh_from_glb_data(glb_data)
	glb_texture   := ass.load_texture_from_glb_data(glb_data)
	defer gltf.unload(glb_data)
	
	mesh_renderer := ren.Mesh_Renderer{
		materials = []ass.Material{
			{ // Element 0
				tint_color     = {1.0,1.0,1.0,1.0},
				albedo_texture = glb_texture,
			},
		},
		mesh = glb_mesh_data,
		transform = {
			position = { position.x, position.y, position.z },
			rotation = {0,0,0},
			scale    = {1,1,1},
		},
	}

	ren.add_mesh_to_render_queue(mesh_renderer, &g.render_queue, &g.shadow_resources)
}


draw_debug :: proc() {
	if len(g.debug_render_queue) == 0 {
		return
	}

	// Sort debug calls by depth test mode to minimize pipeline switches
	slice.sort_by(g.debug_render_queue[:], proc(a, b: deb.Debug_Draw_Call) -> bool {
		a_depth: deb.Depth_Test_Mode
		b_depth: deb.Depth_Test_Mode
		
		switch data in a.data {
			case deb.Line_Segment_Data: a_depth = data.depth_test
			case deb.Wire_Sphere_Data:  a_depth = data.depth_test
			case deb.Wire_Cube_Data:    a_depth = data.depth_test
		}
		
		switch data in b.data {
			case deb.Line_Segment_Data: b_depth = data.depth_test
			case deb.Wire_Sphere_Data:  b_depth = data.depth_test
			case deb.Wire_Cube_Data:    b_depth = data.depth_test
		}
		
		return int(a_depth) < int(b_depth)
	})

	// Setup sokol-gl for debug drawing with proper depth testing
	sgl.defaults()
	
	// Start with the first depth mode
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
	for i in 0..<len(g.debug_render_queue) {
		// Get the depth test mode for this draw call
		depth_mode: deb.Depth_Test_Mode
		switch data in g.debug_render_queue[i].data {
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
		switch draw_data in g.debug_render_queue[i].data {
			case deb.Line_Segment_Data:
				sgl.c4f(draw_data.color[0], draw_data.color[1], draw_data.color[2], draw_data.color[3])
				sgl.begin_lines()
				sgl.v3f(draw_data.start[0], draw_data.start[1], draw_data.start[2])
				sgl.v3f(draw_data.end[0], draw_data.end[1], draw_data.end[2])
				sgl.end()
				
			case deb.Wire_Sphere_Data:
				if draw_data.simple_mode {
					deb.draw_wire_sphere_simple_immediate(draw_data.transform, draw_data.radius, draw_data.color)
				} else {
					deb.draw_wire_sphere_immediate(draw_data.transform, draw_data.radius, draw_data.color)
				}
				
			case deb.Wire_Cube_Data:
				deb.draw_wire_cube_immediate(draw_data.transform, draw_data.color)
		}
	}

	//clear debug draw calls
	clear(&g.debug_render_queue)

	sgl.draw()
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())
	t  := f32(sapp.frame_count())

	gameplay.on_update(dt, t, g)

	if inp.get_key_down(.F1) {
		g.toggle_debug = !g.toggle_debug
	}

	shadow_pass_action := sg.Pass_Action {
		depth = {
			load_action  = .CLEAR,
			store_action = .STORE,
			clear_value  = 1,
		},
	}

	opaque_pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = {.2,.2,.2,1} },
		},
	}

	debug_pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .DONTCARE },
		},
	}

	directional_light : ren.Directional_Light
	direct_light_found := false
	// Get Directional Light
	for i in 0..<len(g.lights) {
		#partial switch value in g.lights[i] {
			case ren.Directional_Light:
				directional_light = value
				direct_light_found = true
		}
	}

	deb.draw_grid({0,0,0}, {0,0,0},50,50,{.4,.4,.4,.8}, &g.debug_render_queue)

	// Directional Shadow Pass
	{
		if !direct_light_found do return
		sg.begin_pass({ action = shadow_pass_action, attachments = g.shadow_resources.shadow_attachments })

		view_projection := ren.get_light_view_proj(directional_light)

		g.light_view_projection = view_projection

		for i in 0..<len(g.render_queue) {

			model := trans.compute_model_matrix(g.render_queue[i].renderer.transform)

			vs_shadow_params := shader.Vs_Shadow_Params {
				view_projection = view_projection,
				model           = model,
			}
			
			sg.apply_pipeline(g.render_queue[i].shadow.pipeline)
			sg.apply_bindings(g.render_queue[i].shadow.bindings)
			sg.apply_uniforms(shader.UB_vs_shadow_params, { ptr = &vs_shadow_params, size = size_of(vs_shadow_params) })
			sg.draw(0, i32(g.render_queue[i].index_count), 1)
		}

		deb.draw_ortho_frustum(
				directional_light.transform.position,
				directional_light.transform.rotation,
				directional_light.bounds,
				{1, 1, 0, 1},  // Yellow color
				&g.debug_render_queue,
				.Off,  // No depth test so we can always see it
			)

		sg.end_pass()
	}
	
	point_light_params       : shader.Fs_Point_Light
	directional_light_params : shader.Fs_Directional_Light

	for i in 0..<len(g.lights) {
		if i > len(point_light_params.color) do continue
		
		switch value in g.lights[i] {
			case ren.Point_Light:
				point_light := value
				point_range := point_light.transform.scale
				
				point_light_params.position[i].xyz = point_light.transform.position
				point_light_params.color[i]        = point_light.color
				point_light_params.intensity[i].x  = point_light.intensity
				point_light_params.range[i].x      = linalg.max_triple(point_range.x, point_range.y, point_range.z)

				deb.draw_wire_sphere_alpha(point_light.transform, 1, point_light.color.rgb, .8, &g.debug_render_queue, .Front, true)
			case ren.Directional_Light:
				forward := trans.get_forward_direction(directional_light.transform) 

				directional_light_params.position.xyz  = directional_light.transform.position
				directional_light_params.direction.xyz = forward
				directional_light_params.color         = directional_light.color
				directional_light_params.intensity     = directional_light.intensity

				deb.draw_wire_sphere(directional_light.transform, .25, directional_light.color, &g.debug_render_queue, .Front, true)
				deb.draw_transform_axes(directional_light.transform, 1, &g.debug_render_queue)
		}
	}

	//Opaque Pass
	{
		sg.begin_pass({ action = opaque_pass_action, swapchain = sglue.swapchain() })
		for i in 0..<len(g.render_queue) {
			model := trans.compute_model_matrix(g.render_queue[i].renderer.transform)
			vs_params := shader.Vs_Params {
				view_projection  = ren.compute_view_projection(g.main_camera.position, g.main_camera.rotation),
				model            = model,
				view_pos         = g.main_camera.position,
				direct_light_mvp = ren.get_light_view_proj(directional_light) * model,
			}
			sg.apply_pipeline(g.render_queue[i].opaque.pipeline)
			sg.apply_bindings(g.render_queue[i].opaque.bindings)
			sg.apply_uniforms(shader.UB_vs_params,            { ptr = &vs_params,                size = size_of(vs_params) })
			sg.apply_uniforms(shader.UB_fs_point_light,       { ptr = &point_light_params,       size = size_of(point_light_params) })
			sg.apply_uniforms(shader.UB_fs_directional_light, { ptr = &directional_light_params, size = size_of(directional_light_params) })
			sg.draw(0, i32(g.render_queue[i].index_count), 1)
		}

		sg.end_pass()
	}

	if g.toggle_debug {
		sg.begin_pass( { action = debug_pass_action, swapchain = sglue.swapchain() })
		draw_debug()
		sg.end_pass()
	}

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