package renderer
import        "../../shader"
import sg     "../../lib/sokol/gfx"
import        "core:fmt"
import        "core:c"
import ass    "../asset"
import gltf   "../../lib/glTF2"

create_entity_by_mesh_path :: proc(
		path : string,
		render_queue : ^[dynamic]Draw_Call,
		shadow_pass_resources : ^Shadow_Pass_Resources,
		position : [3]f32 = {0,0,0},
) -> ^Entity{

	glb_data      := ass.load_glb_data_from_file(path)
	glb_mesh_data := ass.load_mesh_from_glb_data(glb_data)
	glb_texture   := ass.load_texture_from_glb_data(glb_data)
	defer gltf.unload(glb_data)
	
	mesh_renderer := Mesh_Renderer{
		materials = []ass.Material{
			{ // Element 0
				tint_color     = {1.0,1.0,1.0,1.0},
				albedo_texture = glb_texture,
			},
		},
		mesh = glb_mesh_data,
	}

	entity := add_mesh_to_render_queue(mesh_renderer, render_queue, shadow_pass_resources)

	entity.transform = {
		position = position,
		scale    = {1,1,1},
	}

	return entity
}

add_mesh_to_render_queue :: proc(
	mesh_renderer      : Mesh_Renderer,
	render_queue       : ^[dynamic]Draw_Call,
	shadow_resources   : ^Shadow_Pass_Resources,
) -> ^Entity {

	draw_call : Draw_Call
	draw_call.entity = Entity{
		mesh_renderer = mesh_renderer,
	}

	bind_opaque_render_props(shadow_resources, &draw_call)
	bind_outline_render_props(&draw_call)
	bind_shadow_render_props(&draw_call)

	append(render_queue, draw_call)
	return &render_queue[len(render_queue)-1].entity
}

@(private="file")
bind_opaque_render_props :: proc( shadow_resources : ^Shadow_Pass_Resources, draw_call : ^Draw_Call, ){
	// Set the renderer field
	mesh_renderer := draw_call.entity.mesh_renderer
	
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

	assert(len(mesh_renderer.materials) > 0, "Error: Mesh renderer has no materials")
	albedo_texture := mesh_renderer.materials[0].albedo_texture

	assert(len(albedo_texture.mip_chain) > 0, "Error: Texture mip_chain is empty")
	assert(len(albedo_texture.mip_chain[0].final_pixels) > 0, "Error: Texture has no pixel data")

	// Calculate expected size for RGBA8 format
	expected_size := int(albedo_texture.dimensions.width) * int(albedo_texture.dimensions.height) * 4
	actual_size := len(albedo_texture.mip_chain[0].final_pixels)
	
	fmt.printfln("Creating GPU texture: %dx%d, expected %d bytes, actual %d bytes",
		albedo_texture.dimensions.width, albedo_texture.dimensions.height, 
		expected_size, actual_size)
	
	assert(actual_size == expected_size, "Error: Texture size mismatch for RGBA8 format")

	// ------------------------------------------------------------------
	// Upload the full mip chain to the GPU image
	// ------------------------------------------------------------------
	img_desc : sg.Image_Desc
	img_desc.width        = albedo_texture.dimensions.width
	img_desc.height       = albedo_texture.dimensions.height
	img_desc.pixel_format = .RGBA8
	img_desc.num_mipmaps  = c.int(len(albedo_texture.mip_chain))

	for mip_idx in 0..<int(len(albedo_texture.mip_chain)) {
		mip_pixels := albedo_texture.mip_chain[mip_idx].final_pixels
		img_desc.data.subimage[0][mip_idx].ptr  = raw_data(mip_pixels)
		img_desc.data.subimage[0][mip_idx].size = uint(len(mip_pixels))
	}

	draw_call.opaque.bindings.images[shader.IMG_tex] = sg.make_image(img_desc)

	draw_call.opaque.bindings.samplers[shader.SMP_smp] = sg.make_sampler({
		max_anisotropy = 8,
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		mipmap_filter  = .LINEAR,
	})

	// Bind Shadows
	draw_call.opaque.bindings.images[shader.IMG_shadow_tex]   = shadow_resources.shadow_map
	draw_call.opaque.bindings.samplers[shader.SMP_shadow_smp] = shadow_resources.shadow_sampler

	// Shader and pipeline object
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
}

@(private="file")
bind_outline_render_props :: proc(draw_call : ^Draw_Call,){
	mesh_renderer := draw_call.entity.mesh_renderer

	assert(mesh_renderer.mesh.vertex_count > 0, "Error: Vertex Buffer Count for Mesh is 0")
	draw_call.outline.bindings.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.vertex_buffer_bytes), size = uint(len(mesh_renderer.mesh.vertex_buffer_bytes)) },
	})

	// Calculate smoothed normals for outline pass
	smooth_normals := ass.calculate_smooth_normals(mesh_renderer.mesh)
	
	assert(len(smooth_normals) > 0, "Error: Smooth normal buffer is empty")
	draw_call.outline.bindings.vertex_buffers[1] = sg.make_buffer({
		data = { ptr = raw_data(smooth_normals), size = uint(len(smooth_normals)) },
	})

	assert(len(mesh_renderer.mesh.index_buffer_bytes) > 0, "Error: Index Buffer Count for Mesh is 0")
	draw_call.outline.bindings.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(mesh_renderer.mesh.index_buffer_bytes),  size = uint(len(mesh_renderer.mesh.index_buffer_bytes)) },
	})

	// Shader and pipeline object
	draw_call.outline.pipeline = sg.make_pipeline({
		shader = sg.make_shader(shader.outline_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				shader.ATTR_outline_pos    = { format = .FLOAT3 },
				shader.ATTR_outline_normal = { format = .FLOAT3, buffer_index = 1 },
			},
		},
		index_type = .UINT16,
		cull_mode = .FRONT,
		face_winding = .CW,
		depth = {
			compare = .LESS_EQUAL,
			write_enabled = false,
			
		},
	})
}

@(private="file")
bind_shadow_render_props :: proc(draw_call : ^Draw_Call,) {

	mesh_renderer := draw_call.entity.mesh_renderer
	// Set the index count
	draw_call.index_count = mesh_renderer.mesh.index_count

	assert(mesh_renderer.mesh.vertex_count > 0, "Error: Vertex Buffer Count for Mesh is 0")
	draw_call.shadow.bindings.vertex_buffers[0] = sg.make_buffer({
		data = { ptr = raw_data(mesh_renderer.mesh.vertex_buffer_bytes), size = uint(len(mesh_renderer.mesh.vertex_buffer_bytes)) },
	})

	assert(len(mesh_renderer.mesh.index_buffer_bytes) > 0, "Error: Index Buffer Count for Mesh is 0")
	draw_call.shadow.bindings.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = { ptr = raw_data(mesh_renderer.mesh.index_buffer_bytes),  size = uint(len(mesh_renderer.mesh.index_buffer_bytes)) },
	})

	// shader and pipeline object
	draw_call.shadow.pipeline = sg.make_pipeline({
		shader = sg.make_shader(shader.shadow_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				shader.ATTR_shadow_pos  = { format = .FLOAT3 },
			},
		},
		colors = {
			0 = {
				pixel_format = .NONE,
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CW,
		sample_count = 1,
		depth = {
			pixel_format = .DEPTH,
			write_enabled = true,
			compare = .LESS_EQUAL,
			bias = 0.001,
			bias_slope_scale = 1.0,
		},
		label = "shadow-pipeline",
	})
}
