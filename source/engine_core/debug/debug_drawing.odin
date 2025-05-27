package debug

import sgl "../../lib/sokol/gl"
import sg "../../lib/sokol/gfx"
import slog "../../lib/sokol/log"
import linalg "core:math/linalg"
import trans "../transform"
import ren "../renderer"


init :: proc(pipeline: ^[Depth_Test_Mode]sgl.Pipeline) {
    // Initialize sokol-gl for debug drawing
	sgl.setup({
		logger = { func = slog.func },
	})

	// Create pipeline with alpha blending enabled for depth testing
	pipeline[.Front] = sgl.make_pipeline({
		depth = {
			write_enabled = true,
			compare = .LESS_EQUAL,
		},
		cull_mode = .NONE,
		colors = {
			0 = {
				blend = {
					enabled = true,
					src_factor_rgb = sg.Blend_Factor.SRC_ALPHA,
					dst_factor_rgb = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					op_rgb = sg.Blend_Op.ADD,
					src_factor_alpha = sg.Blend_Factor.ONE,
					dst_factor_alpha = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					op_alpha = sg.Blend_Op.ADD,
				},
				write_mask = sg.Color_Mask.RGBA,
			},
		},
	})
	
	// Create pipeline with alpha blending enabled for no depth testing
	pipeline[.Off] = sgl.make_pipeline({
		depth = {
			write_enabled = false,
			compare = .ALWAYS,
		},
		cull_mode = .NONE,
		colors = {
			0 = {
				blend = {
					enabled = true,
					src_factor_rgb = sg.Blend_Factor.SRC_ALPHA,
					dst_factor_rgb = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					op_rgb = sg.Blend_Op.ADD,
					src_factor_alpha = sg.Blend_Factor.ONE,
					dst_factor_alpha = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
					op_alpha = sg.Blend_Op.ADD,
				},
				write_mask = sg.Color_Mask.RGBA,
			},
		},
	})
}

draw_wire_sphere :: proc(transform: trans.Transform, radius: f32, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front, simple_mode: bool = false) {
    append(debug_data, Debug_Draw_Call{
        data = Wire_Sphere_Data{
            transform = transform,
            radius = radius,
            color = color,
            depth_test = depth_test,
            simple_mode = simple_mode,
        },
    })
}

// Convenience function for drawing a wire sphere with opacity
draw_wire_sphere_alpha :: proc(transform: trans.Transform, radius: f32, color: [3]f32, alpha: f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front, simple_mode: bool = false) {
    full_color := [4]f32{color[0], color[1], color[2], alpha}
    draw_wire_sphere(transform, radius, full_color, debug_data, depth_test, simple_mode)
}

// Low-detail sphere for less visual noise
draw_wire_sphere_simple :: proc(transform: trans.Transform, radius: f32, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    // Draw just 3 orthogonal circles instead of full wireframe
    
    // XY plane circle (around Z axis)
    segments :: 16
    for i in 0..<segments {
        angle1 := f32(i) * 2.0 * linalg.PI / f32(segments)
        angle2 := f32((i + 1) % segments) * 2.0 * linalg.PI / f32(segments)
        
        p1 := transform.position + [3]f32{
            radius * linalg.cos(angle1),
            radius * linalg.sin(angle1),
            0,
        }
        p2 := transform.position + [3]f32{
            radius * linalg.cos(angle2),
            radius * linalg.sin(angle2),
            0,
        }
        draw_line_segment(p1, p2, color, debug_data, depth_test)
    }
    
    // XZ plane circle (around Y axis)
    for i in 0..<segments {
        angle1 := f32(i) * 2.0 * linalg.PI / f32(segments)
        angle2 := f32((i + 1) % segments) * 2.0 * linalg.PI / f32(segments)
        
        p1 := transform.position + [3]f32{
            radius * linalg.cos(angle1),
            0,
            radius * linalg.sin(angle1),
        }
        p2 := transform.position + [3]f32{
            radius * linalg.cos(angle2),
            0,
            radius * linalg.sin(angle2),
        }
        draw_line_segment(p1, p2, color, debug_data, depth_test)
    }
    
    // YZ plane circle (around X axis)
    for i in 0..<segments {
        angle1 := f32(i) * 2.0 * linalg.PI / f32(segments)
        angle2 := f32((i + 1) % segments) * 2.0 * linalg.PI / f32(segments)
        
        p1 := transform.position + [3]f32{
            0,
            radius * linalg.cos(angle1),
            radius * linalg.sin(angle1),
        }
        p2 := transform.position + [3]f32{
            0,
            radius * linalg.cos(angle2),
            radius * linalg.sin(angle2),
        }
        draw_line_segment(p1, p2, color, debug_data, depth_test)
    }
}

draw_wire_cube :: proc(transform : trans.Transform, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    append(debug_data, Debug_Draw_Call{
        data = Wire_Cube_Data{
            transform = transform,
            color = color,
            depth_test = depth_test,
        },
    })
}

// Convenience function for drawing a wire cube with opacity
draw_wire_cube_alpha :: proc(transform: trans.Transform, color: [3]f32, alpha: f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    full_color := [4]f32{color[0], color[1], color[2], alpha}
    draw_wire_cube(transform, full_color, debug_data, depth_test)
}

draw_line_segment :: proc(start: [3]f32, end: [3]f32, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    append(debug_data, Debug_Draw_Call{
        data = Line_Segment_Data{
            start = start,
            end = end,
            color = color,
            depth_test = depth_test,
        },
    })
}

// Convenience function for drawing a line segment with opacity
draw_line_segment_alpha :: proc(start: [3]f32, end: [3]f32, color: [3]f32, alpha: f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    full_color := [4]f32{color[0], color[1], color[2], alpha}
    draw_line_segment(start, end, full_color, debug_data, depth_test)
}

draw_wire_cone :: proc(tip: [3]f32, base_center: [3]f32, radius: f32, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front, segments: int = 8) {
    // Calculate the cone's local coordinate system
    cone_axis := linalg.normalize(base_center - tip)
    
    // Find two perpendicular vectors to the cone axis
    up := [3]f32{0, 1, 0}
    if abs(linalg.dot(cone_axis, up)) > 0.9 {
        up = {1, 0, 0} // Use right vector if cone is pointing up/down
    }
    
    right := linalg.normalize(linalg.cross(cone_axis, up))
    forward := linalg.cross(right, cone_axis)
    
    // Generate points around the base circle
    base_points: [dynamic][3]f32
    defer delete(base_points)
    
    for i in 0..<segments {
        angle := f32(i) * 2.0 * linalg.PI / f32(segments)
        cos_a := linalg.cos(angle)
        sin_a := linalg.sin(angle)
        
        point := base_center + right * (radius * cos_a) + forward * (radius * sin_a)
        append(&base_points, point)
    }
    
    // Draw base circle
    for i in 0..<segments {
        next_i := (i + 1) % segments
        draw_line_segment(base_points[i], base_points[next_i], color, debug_data, depth_test)
    }
    
    // Draw lines from tip to base circle
    for point in base_points {
        draw_line_segment(tip, point, color, debug_data, depth_test)
    }
}

draw_transform_axes :: proc(transform: trans.Transform, axis_length: f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    // Get the rotation matrix to extract the transformed axes
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    // Extract the transformed axes from the rotation matrix
    x_axis := [3]f32{rot_combined[0][0], rot_combined[0][1], rot_combined[0][2]} * axis_length
    y_axis := [3]f32{rot_combined[1][0], rot_combined[1][1], rot_combined[1][2]} * axis_length
    z_axis := [3]f32{rot_combined[2][0], rot_combined[2][1], rot_combined[2][2]} * axis_length
    
    origin := transform.position
    // cone_length := axis_length * 0.2
    cone_radius := axis_length * 0.05
    
    // Draw X axis (Red)
    x_line_end := origin + x_axis * 0.8  // Shorten line to make room for cone
    x_cone_tip := origin + x_axis
    draw_line_segment(origin, x_line_end, {1, 0, 0, 1}, debug_data, depth_test)
    draw_wire_cone(x_cone_tip, x_line_end, cone_radius, {1, 0, 0, 1}, debug_data, depth_test)
    
    // Draw Y axis (Green)
    y_line_end := origin + y_axis * 0.8
    y_cone_tip := origin + y_axis
    draw_line_segment(origin, y_line_end, {0, 1, 0, 1}, debug_data, depth_test)
    draw_wire_cone(y_cone_tip, y_line_end, cone_radius, {0, 1, 0, 1}, debug_data, depth_test)
    
    // Draw Z axis (Blue)
    z_line_end := origin + z_axis * 0.8
    z_cone_tip := origin + z_axis
    draw_line_segment(origin, z_line_end, {0, 0, 1, 1}, debug_data, depth_test)
    draw_wire_cone(z_cone_tip, z_line_end, cone_radius, {0, 0, 1, 1}, debug_data, depth_test)
}

draw_wire_sphere_immediate :: proc(transform: trans.Transform, radius: f32, color: [4]f32) {
	sgl.c4f(color[0], color[1], color[2], color[3])
	
	// Apply transformation matrix
	sgl.push_matrix()
	sgl.translate(transform.position[0], transform.position[1], transform.position[2])
	// Match compute_model_matrix rotation order: yaw (Y), pitch (X), roll (Z)
	sgl.rotate(sgl.rad(transform.rotation[1]), 0, 1, 0) // Yaw
	sgl.rotate(sgl.rad(transform.rotation[0]), 1, 0, 0) // Pitch
	sgl.rotate(sgl.rad(transform.rotation[2]), 0, 0, 1) // Roll
	// Apply non-uniform scale to create ellipsoid
	sgl.scale(transform.scale[0], transform.scale[1], transform.scale[2])
	
	segments :: 12  // Reduced from 16
	rings :: 8      // Reduced from 12
	
	// Draw longitude lines (reduced frequency)
	for i in 0..<segments {
		// Only draw every other longitude line to reduce visual noise
		if i % 2 != 0 do continue
		
		angle := f32(i) * 2.0 * linalg.PI / f32(segments)
		
		sgl.begin_line_strip()
		for j in 0..=rings {
			phi := f32(j) * linalg.PI / f32(rings)
			x := radius * linalg.sin(phi) * linalg.cos(angle)
			y := radius * linalg.cos(phi)
			z := radius * linalg.sin(phi) * linalg.sin(angle)
			sgl.v3f(x, y, z)
		}
		sgl.end()
	}
	
	// Draw latitude lines (reduced frequency)
	for j in 1..<rings {
		// Only draw every other latitude line to reduce visual noise
		if j % 2 != 0 do continue
		
		phi := f32(j) * linalg.PI / f32(rings)
		r := radius * linalg.sin(phi)
		y := radius * linalg.cos(phi)
		
		sgl.begin_line_strip()
		for i in 0..=segments {
			angle := f32(i) * 2.0 * linalg.PI / f32(segments)
			x := r * linalg.cos(angle)
			z := r * linalg.sin(angle)
			sgl.v3f(x, y, z)
		}
		sgl.end()
	}
	
	sgl.pop_matrix()
}

// Simple immediate mode sphere with just 3 orthogonal circles
draw_wire_sphere_simple_immediate :: proc(transform: trans.Transform, radius: f32, color: [4]f32) {
	sgl.c4f(color[0], color[1], color[2], color[3])
	
	// Apply transformation matrix
	sgl.push_matrix()
	sgl.translate(transform.position[0], transform.position[1], transform.position[2])
	sgl.rotate(sgl.rad(transform.rotation[1]), 0, 1, 0) // Yaw
	sgl.rotate(sgl.rad(transform.rotation[0]), 1, 0, 0) // Pitch
	sgl.rotate(sgl.rad(transform.rotation[2]), 0, 0, 1) // Roll
	sgl.scale(transform.scale[0], transform.scale[1], transform.scale[2])
	
	segments :: 24
	
	// XY plane circle (around Z axis)
	sgl.begin_line_strip()
	for i in 0..=segments {
		angle := f32(i) * 2.0 * linalg.PI / f32(segments)
		x := radius * linalg.cos(angle)
		y := radius * linalg.sin(angle)
		sgl.v3f(x, y, 0)
	}
	sgl.end()
	
	// XZ plane circle (around Y axis)
	sgl.begin_line_strip()
	for i in 0..=segments {
		angle := f32(i) * 2.0 * linalg.PI / f32(segments)
		x := radius * linalg.cos(angle)
		z := radius * linalg.sin(angle)
		sgl.v3f(x, 0, z)
	}
	sgl.end()
	
	// YZ plane circle (around X axis)
	sgl.begin_line_strip()
	for i in 0..=segments {
		angle := f32(i) * 2.0 * linalg.PI / f32(segments)
		y := radius * linalg.cos(angle)
		z := radius * linalg.sin(angle)
		sgl.v3f(0, y, z)
	}
	sgl.end()
	
	sgl.pop_matrix()
}

draw_wire_cube_immediate :: proc(transform: trans.Transform, color: [4]f32) {
	sgl.c4f(color[0], color[1], color[2], color[3])
	
	// Apply transformation
	sgl.push_matrix()
	sgl.translate(transform.position[0], transform.position[1], transform.position[2])
	sgl.rotate(sgl.rad(transform.rotation[0]), 1, 0, 0)
	sgl.rotate(sgl.rad(transform.rotation[1]), 0, 1, 0)
	sgl.rotate(sgl.rad(transform.rotation[2]), 0, 0, 1)
	sgl.scale(transform.scale[0], transform.scale[1], transform.scale[2])
	
	size :: 0.5
	vertices := [8]Vec3{
		{-size, -size, -size},
		{ size, -size, -size},
		{ size,  size, -size},
		{-size,  size, -size},
		{-size, -size,  size},
		{ size, -size,  size},
		{ size,  size,  size},
		{-size,  size,  size},
	}
	
	edges := [12][2]int{
		{0, 1}, {1, 2}, {2, 3}, {3, 0}, // Front face
		{4, 5}, {5, 6}, {6, 7}, {7, 4}, // Back face
		{0, 4}, {1, 5}, {2, 6}, {3, 7}, // Connecting edges
	}
	
	sgl.begin_lines()
	for edge in edges {
		v0 := vertices[edge[0]]
		v1 := vertices[edge[1]]
		sgl.v3f(v0[0], v0[1], v0[2])
		sgl.v3f(v1[0], v1[1], v1[2])
	}
	sgl.end()
	
	sgl.pop_matrix()
}

// Draw orthographic frustum bounds for shadow mapping
draw_ortho_frustum :: proc(position: [3]f32, rotation: [3]f32, bounds: ren.Bounds, color: [4]f32, debug_data: ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Off, show_full_volume: bool = false) {
	// Calculate the 8 corners of the orthographic frustum in view space
	// This matches compute_centered_ortho_projection which uses:
	// left = -bounds.width / 2, right = bounds.width / 2
	// bottom = -bounds.height / 2, top = bounds.height / 2
	// near = -bounds.half_depth, far = bounds.half_depth
	half_w := bounds.width / 2
	half_h := bounds.height / 2
	
	// For orthographic projection, the camera is at the center (z=0 in view space)
	// Typically we only care about the forward portion (negative Z in view space)
	near := show_full_volume ? -bounds.half_depth : 0.0  // Start from camera position
	far  := bounds.half_depth                            // Extend forward to half_depth

	corners_view := [8][3]f32{
		{-half_w, -half_h, near},  // Near bottom left
		{ half_w, -half_h, near},  // Near bottom right
		{ half_w,  half_h, near},  // Near top right
		{-half_w,  half_h, near},  // Near top left
		{-half_w, -half_h, far},   // Far bottom left
		{ half_w, -half_h, far},   // Far bottom right
		{ half_w,  half_h, far},   // Far top right
		{-half_w,  half_h, far},   // Far top left
	}
	
	// Build the inverse view matrix to transform from view space to world space
	// compute_centered_ortho_projection uses: view = view_rotation_inv * trans
	// where view_rotation_inv = inv_rot_roll * inv_rot_pitch * inv_rot_yaw
	// So the inverse is: trans_inv * rot_yaw * rot_pitch * rot_roll
	
	rot_pitch := linalg.matrix4_rotate_f32(rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	rot_yaw   := linalg.matrix4_rotate_f32(rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
	rot_roll  := linalg.matrix4_rotate_f32(rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
	trans_inv := linalg.matrix4_translate_f32(position)
	
	// Combine in reverse order
	view_inv := trans_inv * rot_yaw * rot_pitch * rot_roll
	
	// Transform corners to world space
	corners_world: [8][3]f32
	for i in 0..<8 {
		corner := corners_view[i]
		corner_4d := [4]f32{corner.x, corner.y, corner.z, 1.0}
		
		// Apply view inverse
		world_4d := view_inv * corner_4d
		corners_world[i] = [3]f32{world_4d.x, world_4d.y, world_4d.z}
	}
	
	// Draw the 12 edges of the frustum
	edges := [12][2]int{
		// Near plane
		{0, 1}, {1, 2}, {2, 3}, {3, 0},
		// Far plane
		{4, 5}, {5, 6}, {6, 7}, {7, 4},
		// Connecting edges
		{0, 4}, {1, 5}, {2, 6}, {3, 7},
	}
	
	for edge in edges {
		draw_line_segment(corners_world[edge[0]], corners_world[edge[1]], color, debug_data, depth_test)
	}
	
	// Draw a cross on the near plane to indicate orientation
	near_center := (corners_world[0] + corners_world[1] + corners_world[2] + corners_world[3]) * 0.25
	near_horizontal := (corners_world[1] - corners_world[0]) * 0.3
	near_vertical := (corners_world[3] - corners_world[0]) * 0.3
	
	draw_line_segment(near_center - near_horizontal, near_center + near_horizontal, color, debug_data, depth_test)
	draw_line_segment(near_center - near_vertical, near_center + near_vertical, color, debug_data, depth_test)
	
	// If we're showing only the forward portion, draw a small indicator at the camera position
	if !show_full_volume {
		// Draw a small cross at the camera position (which is at the near plane when near=0)
		camera_size := min(bounds.width, bounds.height) * 0.1
		camera_color := [4]f32{color[0], color[1], color[2], color[3] * 0.5} // Slightly dimmer
		
		// Get camera right and up vectors in world space
		right := [3]f32{view_inv[0][0], view_inv[0][1], view_inv[0][2]} * camera_size
		up := [3]f32{view_inv[1][0], view_inv[1][1], view_inv[1][2]} * camera_size
		
		// Draw camera position indicator
		draw_line_segment(position - right, position + right, camera_color, debug_data, depth_test)
		draw_line_segment(position - up, position + up, camera_color, debug_data, depth_test)
	}
}

// Draw a grid with specified size in meters, with 1-meter spacing between lines
draw_grid :: proc(position: [3]f32, rotation: [3]f32, amount_x: int, amount_z: int, color: [4]f32, debug_data: ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
	// Build transformation matrix
	rot_pitch := linalg.matrix4_rotate_f32(rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	rot_yaw   := linalg.matrix4_rotate_f32(rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
	rot_roll  := linalg.matrix4_rotate_f32(rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
	trans     := linalg.matrix4_translate_f32(position)
	
	// Combine transformations: translate first, then rotate
	transform := trans * rot_yaw * rot_pitch * rot_roll
	
	// Grid size is determined by amount_x and amount_z (in meters)
	grid_width := f32(amount_x)
	grid_depth := f32(amount_z)
	half_width := grid_width * 0.5
	half_depth := grid_depth * 0.5
	
	// Draw lines parallel to X axis (varying Z)
	// Lines are spaced 1 meter apart
	for i in 0..=amount_z {
		z_pos := -half_depth + f32(i)  // From -half_depth to +half_depth in 1-meter increments
		
		// Start and end points in local space
		start_local := [4]f32{-half_width, 0, z_pos, 1}
		end_local   := [4]f32{ half_width, 0, z_pos, 1}
		
		// Transform to world space
		start_world := transform * start_local
		end_world   := transform * end_local
		
		draw_line_segment(
			[3]f32{start_world.x, start_world.y, start_world.z},
			[3]f32{end_world.x, end_world.y, end_world.z},
			color, debug_data, depth_test
		)
	}
	
	// Draw lines parallel to Z axis (varying X)
	// Lines are spaced 1 meter apart
	for i in 0..=amount_x {
		x_pos := -half_width + f32(i)  // From -half_width to +half_width in 1-meter increments
		
		// Start and end points in local space
		start_local := [4]f32{x_pos, 0, -half_depth, 1}
		end_local   := [4]f32{x_pos, 0,  half_depth, 1}
		
		// Transform to world space
		start_world := transform * start_local
		end_world   := transform * end_local
		
		draw_line_segment(
			[3]f32{start_world.x, start_world.y, start_world.z},
			[3]f32{end_world.x, end_world.y, end_world.z},
			color, debug_data, depth_test
		)
	}
}

// Convenience function for drawing a grid with opacity
draw_grid_alpha :: proc(position: [3]f32, rotation: [3]f32, amount_x: int, amount_z: int, color: [3]f32, alpha: f32, debug_data: ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
	full_color := [4]f32{color[0], color[1], color[2], alpha}
	draw_grid(position, rotation, amount_x, amount_z, full_color, debug_data, depth_test)
}