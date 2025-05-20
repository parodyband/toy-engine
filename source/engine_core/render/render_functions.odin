package render

import "../../glTF2"

import "core:fmt"

load_mesh_from_data :: proc(glb_data : ^glTF2.Data) -> mesh {

	loaded_mesh_data : mesh

	primitive := glb_data.meshes[0].primitives[0]

	position_accessor_idx, pos_ok := primitive.attributes["POSITION"]

	if !pos_ok {
		fmt.println("Primitive has no Position attribute")
	} else {
		accessor     := glb_data.accessors[position_accessor_idx]
		buffer_index, _ := accessor.buffer_view.?

		buffer_view  := glb_data.buffer_views[buffer_index]
		buffer       := glb_data.buffers[buffer_view.buffer]

		raw_buffer_bytes  := buffer.uri.([]byte)
		data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
		element_size      := 3 * size_of(f32)
		data_end_offset   := data_start_offset + int(accessor.count) * element_size

		loaded_mesh_data.vertex_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset]
		loaded_mesh_data.vertex_count = int(accessor.count)
	}

	// Load Normals
	normal_accessor_idx, normal_ok := primitive.attributes["NORMAL"]
	if !normal_ok {
		fmt.println("Primitive has no NORMAL attribute")
	} else {
		accessor     := glb_data.accessors[normal_accessor_idx]
		buffer_index, ok_norm_bv := accessor.buffer_view.?
		if ok_norm_bv {
			buffer_view  := glb_data.buffer_views[buffer_index]
			buffer       := glb_data.buffers[buffer_view.buffer]
			raw_buffer_bytes, is_bytes := buffer.uri.([]byte)

			if is_bytes {
				data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
				element_size      := 3 * size_of(f32)
				data_end_offset   := data_start_offset + int(accessor.count) * element_size
				loaded_mesh_data.normal_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset]
			} else {
				fmt.println("Normal buffer URI is not []byte")
			}
		} else {
			fmt.println("Normal accessor has no buffer view")
		}
	}

	// Load UVs (TexCoords)
	uv_accessor_idx, uv_ok := primitive.attributes["TEXCOORD_0"]
	if !uv_ok {
		fmt.println("Primitive has no TEXCOORD_0 attribute")
	} else {
		accessor     := glb_data.accessors[uv_accessor_idx]
		buffer_index, ok_uv_bv := accessor.buffer_view.?
		if ok_uv_bv {
			buffer_view  := glb_data.buffer_views[buffer_index]
			buffer       := glb_data.buffers[buffer_view.buffer]
			raw_buffer_bytes, is_bytes := buffer.uri.([]byte)

			if is_bytes {
				data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
				// UVs are typically 2 floats (vec2)
				element_size      := 2 * size_of(f32) 
				data_end_offset   := data_start_offset + int(accessor.count) * element_size
				loaded_mesh_data.uv_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset]
			} else {
				fmt.println("UV buffer URI is not []byte")
			}
		} else {
			fmt.println("UV accessor has no buffer view")
		}
	}

	{
		if primitive.indices != nil {
			idx_accessor_idx, _ := primitive.indices.?
			accessor := glb_data.accessors[idx_accessor_idx]

			component_size := size_of(u16)

			buffer_index, _ := accessor.buffer_view.?
			buffer_view := glb_data.buffer_views[buffer_index]
			buffer := glb_data.buffers[buffer_view.buffer]

			raw_buffer_bytes  := buffer.uri.([]byte)
			data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
			data_end_offset   := data_start_offset + int(accessor.count) * component_size
			
			loaded_mesh_data.index_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset]
			loaded_mesh_data.index_count = int(accessor.count)
		} else {
			fmt.println("Primitive has no indices defined.")
		}
	}

	return loaded_mesh_data
}

//load_texture_from_data :: proc(path : string) -> texture {
//
//}

load_glb_from_file :: proc(path : string) -> ^glTF2.Data {
	glb_data, error := glTF2.load_from_file(path)

	switch err_val in error {
	case glTF2.GLTF_Error:
		fmt.printfln("GLTF Error: %s", err_val)
	case glTF2.JSON_Error:
		fmt.printfln("GLTF Json Error: %s", err_val)
	}

	for mesh in glb_data.meshes {
		fmt.printfln("Mesh found! Name: %s", mesh.name)
	}
	return glb_data
}