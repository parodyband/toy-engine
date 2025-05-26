package renderer
import        "../../shader"
import sg     "../../lib/sokol/gfx"

add_mesh_to_render_queue :: proc(
	mesh_renderer : Mesh_Renderer,
	opaque_render_queue : ^[dynamic]Draw_Call,
	shadow_render_queue : ^[dynamic]Draw_Call,
) {
	// bind draw calls
	opaque_draw_call := create_opaque_drawcall(mesh_renderer)
	shadow_draw_call := create_shadow_drawcall(mesh_renderer)

	append(opaque_render_queue, opaque_draw_call)
	append(shadow_render_queue, shadow_draw_call)
}

@(private="file")
create_opaque_drawcall :: proc(mesh_renderer : Mesh_Renderer) -> Draw_Call {
	draw_call : Draw_Call
	// Set the renderer field
	draw_call.renderer = mesh_renderer
	
	// Set the index count
	draw_call.index_count = mesh_renderer.mesh.index_count

	assert(mesh_renderer.mesh.vertex_count > 0, "Error: Vertex Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.vertex_buffer_bytes), size = uint(len(mesh_renderer.mesh.vertex_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.normal_buffer_bytes) > 0, "Error: Normal Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.vertex_buffers[1] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.normal_buffer_bytes), size = uint(len(mesh_renderer.mesh.normal_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.uv_buffer_bytes) > 0, "Error: Uv Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.vertex_buffers[2] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.uv_buffer_bytes),     size = uint(len(mesh_renderer.mesh.uv_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.index_buffer_bytes) > 0, "Error: Index Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(mesh_renderer.mesh.index_buffer_bytes),  size = uint(len(mesh_renderer.mesh.index_buffer_bytes)) },
	})

	albedo_texture := mesh_renderer.materials[0].albedo_texture

	draw_call.opaque.bindings.images[shader.IMG_tex] = sg.make_image({
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

	draw_call.opaque.bindings.samplers[shader.SMP_smp] = sg.make_sampler({
		max_anisotropy = 8,
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		mipmap_filter  = .LINEAR,
	})

	// shader and pipeline object
	draw_call.opaque.pipeline = sg.make_pipeline({
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

	return draw_call
}

@(private="file")
create_shadow_drawcall :: proc(mesh_renderer : Mesh_Renderer) -> Draw_Call {
	draw_call : Draw_Call
	// Set the renderer field
	draw_call.renderer = mesh_renderer
	
	// Set the index count
	draw_call.index_count = mesh_renderer.mesh.index_count

	assert(mesh_renderer.mesh.vertex_count > 0, "Error: Vertex Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.vertex_buffer_bytes), size = uint(len(mesh_renderer.mesh.vertex_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.index_buffer_bytes) > 0, "Error: Index Buffer Count for Mesh is 0")
	draw_call.opaque.bindings.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(mesh_renderer.mesh.index_buffer_bytes),  size = uint(len(mesh_renderer.mesh.index_buffer_bytes)) },
	})

	albedo_texture := mesh_renderer.materials[0].albedo_texture

	draw_call.opaque.bindings.images[shader.IMG_tex] = sg.make_image({
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

	draw_call.opaque.bindings.samplers[shader.SMP_smp] = sg.make_sampler({
		max_anisotropy = 8,
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		mipmap_filter  = .LINEAR,
	})

	// shader and pipeline object
	draw_call.opaque.pipeline = sg.make_pipeline({
		shader = sg.make_shader(shader.texcube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				shader.ATTR_texcube_pos       = { format = .FLOAT3 },
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

	return draw_call
}