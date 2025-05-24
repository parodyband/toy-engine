package debug

import ren "../renderer"
import sgl "../../lib/sokol/gl"
import slog "../../lib/sokol/log"
import linalg "core:math/linalg"


init :: proc(pipeline: ^[Depth_Test_Mode]sgl.Pipeline) {
    // Initialize sokol-gl for debug drawing
	sgl.setup({
		logger = { func = slog.func },
	})

	pipeline[.Front] = sgl.make_pipeline({
		depth = {
			write_enabled = true,
			compare = .LESS_EQUAL,
		},
		cull_mode = .NONE,
	})
	
	pipeline[.Off] = sgl.make_pipeline({
		depth = {
			write_enabled = false,
			compare = .ALWAYS,
		},
		cull_mode = .NONE,
	})
}

draw_wire_sphere :: proc(center: [3]f32, radius: f32, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    append(debug_data, Debug_Draw_Call{
        data = Wire_Sphere_Data{
            center = center,
            radius = radius,
            color = color,
            depth_test = depth_test,
        },
    })
}

draw_wire_cube :: proc(transform : ren.Transform, color: [4]f32, debug_data : ^[dynamic]Debug_Draw_Call, depth_test: Depth_Test_Mode = .Front) {
    append(debug_data, Debug_Draw_Call{
        data = Wire_Cube_Data{
            transform = transform,
            color = color,
            depth_test = depth_test,
        },
    })
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


draw_wire_sphere_immediate :: proc(center: [3]f32, radius: f32, color: [4]f32) {
	sgl.c4f(color[0], color[1], color[2], color[3])
	
	segments :: 16
	rings :: 12
	
	// Draw longitude lines
	for i in 0..<segments {
		angle := f32(i) * 2.0 * linalg.PI / f32(segments)
		
		sgl.begin_line_strip()
		for j in 0..=rings {
			phi := f32(j) * linalg.PI / f32(rings)
			x := center[0] + radius * linalg.sin(phi) * linalg.cos(angle)
			y := center[1] + radius * linalg.cos(phi)
			z := center[2] + radius * linalg.sin(phi) * linalg.sin(angle)
			sgl.v3f(x, y, z)
		}
		sgl.end()
	}
	
	// Draw latitude lines
	for j in 1..<rings {
		phi := f32(j) * linalg.PI / f32(rings)
		r := radius * linalg.sin(phi)
		y := center[1] + radius * linalg.cos(phi)
		
		sgl.begin_line_strip()
		for i in 0..=segments {
			angle := f32(i) * 2.0 * linalg.PI / f32(segments)
			x := center[0] + r * linalg.cos(angle)
			z := center[2] + r * linalg.sin(angle)
			sgl.v3f(x, y, z)
		}
		sgl.end()
	}
}

draw_wire_cube_immediate :: proc(transform: ren.Transform, color: [4]f32) {
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