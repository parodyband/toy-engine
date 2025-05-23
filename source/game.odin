package game

import "core:math/linalg"
import "core:image/png"
import "core:log"
import "core:slice"

import sapp  "lib/sokol/app"
import sg    "lib/sokol/gfx"
import sglue "lib/sokol/glue"
import slog  "lib/sokol/log"

import util "lib/sokol_utils"

import "shader"

Game_Memory :: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
	main_camera: Camera,
	game_input: Input_State,
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
		window_title = "Toy ",
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

	// The remainder of this proc just sets up a sample cube and loads the
	// texture to put on the cube's sides.
	//
	// The cube is from https://github.com/floooh/sokol-odin/blob/main/examples/cube/main.odin

	/*
		Cube vertex buffer with packed vertex formats for color and texture coords.
		Note that a vertex format which must be portable across all
		backends must only use the normalized integer formats
		(BYTE4N, UBYTE4N, SHORT2N, SHORT4N), which can be converted
		to floating point formats in the vertex shader inputs.
	*/

	vertices := [?]Vertex {
		// pos               color       uvs
		{ -1.0, -1.0, -1.0,  0xFF0000FF,     0,     0 },
		{  1.0, -1.0, -1.0,  0xFF0000FF, 32767,     0 },
		{  1.0,  1.0, -1.0,  0xFF0000FF, 32767, 32767 },
		{ -1.0,  1.0, -1.0,  0xFF0000FF,     0, 32767 },

		{ -1.0, -1.0,  1.0,  0xFF00FF00,     0,     0 },
		{  1.0, -1.0,  1.0,  0xFF00FF00, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFF00FF00, 32767, 32767 },
		{ -1.0,  1.0,  1.0,  0xFF00FF00,     0, 32767 },

		{ -1.0, -1.0, -1.0,  0xFFFF0000,     0,     0 },
		{ -1.0,  1.0, -1.0,  0xFFFF0000, 32767,     0 },
		{ -1.0,  1.0,  1.0,  0xFFFF0000, 32767, 32767 },
		{ -1.0, -1.0,  1.0,  0xFFFF0000,     0, 32767 },

		{  1.0, -1.0, -1.0,  0xFFFF007F,     0,     0 },
		{  1.0,  1.0, -1.0,  0xFFFF007F, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFFFF007F, 32767, 32767 },
		{  1.0, -1.0,  1.0,  0xFFFF007F,     0, 32767 },

		{ -1.0, -1.0, -1.0,  0xFFFF7F00,     0,     0 },
		{ -1.0, -1.0,  1.0,  0xFFFF7F00, 32767,     0 },
		{  1.0, -1.0,  1.0,  0xFFFF7F00, 32767, 32767 },
		{  1.0, -1.0, -1.0,  0xFFFF7F00,     0, 32767 },

		{ -1.0,  1.0, -1.0,  0xFF007FFF,     0,     0 },
		{ -1.0,  1.0,  1.0,  0xFF007FFF, 32767,     0 },
		{  1.0,  1.0,  1.0,  0xFF007FFF, 32767, 32767 },
		{  1.0,  1.0, -1.0,  0xFF007FFF,     0, 32767 },
	}
	g.bind.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = &vertices, size = size_of(vertices) },
	})

	// create an index buffer for the cube
	indices := [?]u16 {
		0, 1, 2,  0, 2, 3,
		6, 5, 4,  7, 6, 4,
		8, 9, 10,  8, 10, 11,
		14, 13, 12,  15, 14, 12,
		16, 17, 18,  16, 18, 19,
		22, 21, 20,  23, 22, 20,
	}
	g.bind.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = &indices, size = size_of(indices) },
	})

	if img_data, img_data_ok := util.read_entire_file("assets/test.png", context.temp_allocator); img_data_ok {
		if img, img_err := png.load_from_bytes(img_data, allocator = context.temp_allocator); img_err == nil {
			g.bind.images[shader.IMG_tex] = sg.make_image({
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
		} else {
			log.error(img_err)
		}
	} else {
		log.error("Failed loading texture")
	}

	// a sampler with default options to sample the above image as texture
	g.bind.samplers[shader.SMP_smp] = sg.make_sampler({})

	// shader and pipeline object
	g.pip = sg.make_pipeline({
		shader = sg.make_shader(shader.texcube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				shader.ATTR_texcube_pos = { format = .FLOAT3 },
				shader.ATTR_texcube_color0 = { format = .UBYTE4N },
				shader.ATTR_texcube_texcoord0 = { format = .SHORT2N },
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CCW,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = true,
		},
	})
}

@export
game_frame :: proc() {
	dt := f32(sapp.frame_duration())

	move_camera(dt)

	// vertex shader uniform with model-view-projection matrix
	vs_params := shader.Vs_Params {
		mvp = compute_mvp(g.main_camera.position, g.main_camera.rotation),
	}

	pass_action := sg.Pass_Action {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.41, 0.68, 0.83, 1 } },
		},
	}

	sg.begin_pass({ action = pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(g.pip)
	sg.apply_bindings(g.bind)
	sg.apply_uniforms(shader.UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })

	// 36 is the number of indices
	sg.draw(0, 36, 1)

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
