package asset

import "base:runtime"

import "core:log"
import "core:image/png"
import "core:image"
import "core:slice"
import "core:fmt"

import "../../lib/glTF2"

import file "../../lib/sokol_utils"

load_mesh_from_glb_data :: proc(glb_data : ^glTF2.Data) -> mesh {

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

load_texture_from_glb_data :: proc(glb_data : ^glTF2.Data) -> texture {  
    mat   := glb_data.materials[0]
    pbr   :  glTF2.Material_Metallic_Roughness = mat.metallic_roughness.?
    tex_i := int(pbr.base_color_texture.?.index)
    bytes := get_glb_image_bytes(glb_data, tex_i)

    img, err := png.load_from_bytes(data = bytes, allocator = context.temp_allocator)
    assert(err == nil, "texture decode failed")

    pixels := img.pixels.buf[:]
    byte_len := slice.size(pixels)
    bytes_per_pixel := byte_len / (img.width * img.height)

    final_pixels_ptr := raw_data(pixels)
    final_pixels_size := uint(byte_len)

    if bytes_per_pixel == 3 {
        converted_pixels_slice := rgb_to_rgba(pixels, img.width, img.height, context.temp_allocator)
        final_pixels_ptr = raw_data(converted_pixels_slice)
        final_pixels_size = uint(len(converted_pixels_slice))
    } else if bytes_per_pixel != 4 {
        log.errorf("Unsupported PNG pixel format: %v bytes per pixel (expected 3 or 4)", bytes_per_pixel)
        return texture{} // Return empty texture on error
    }

    return texture{
        width = i32(img.width),
        height = i32(img.height),
        data = final_pixels_ptr[:final_pixels_size],
        final_pixels_ptr = final_pixels_ptr,
        final_pixels_size = final_pixels_size,
    }
}

load_texture_from_png_file :: proc(file_path : string) -> texture {
	
	bytes, ok := file.read_entire_file(file_path)
	assert(ok)

	img, err := png.load_from_bytes(bytes)

	if err != nil {
		fmt.printfln("Error loading PNG file %v: %v", file_path, err)
	}

	defer image.destroy(img)

	return texture {
		width = i32(img.width),
		height = i32(img.height),
		data = bytes,
		final_pixels_ptr = raw_data(img.pixels.buf),
		final_pixels_size = uint(slice.size(img.pixels.buf[:])),
	}
}

load_glb_data_from_file :: proc(path : string) -> ^glTF2.Data {
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

get_glb_image_bytes :: proc (d: ^glTF2.Data, tex_idx: int) -> []byte {
    tex := d.textures[tex_idx]
    img := d.images[tex.source.?]

    if img.buffer_view != nil {
        view  := d.buffer_views[img.buffer_view.?]
        buf   := d.buffers[view.buffer].uri.([]byte)
        start := int(view.byte_offset)
        return buf[start : start + int(view.byte_length)]
    }

    return img.uri.([]byte)
}

rgb_to_rgba :: proc(input_pixels: []u8, width: int, height: int, allocator: runtime.Allocator) -> []u8 {
    pixel_count := width * height
    local_output_pixels := make([]u8, pixel_count * 4, allocator)
    for i in 0..<pixel_count {
        src_idx := i * 3
        dst_idx := i * 4
        local_output_pixels[dst_idx+0] = input_pixels[src_idx+0]
        local_output_pixels[dst_idx+1] = input_pixels[src_idx+1]
        local_output_pixels[dst_idx+2] = input_pixels[src_idx+2]
        local_output_pixels[dst_idx+3] = 255 // Opaque alpha
    }
    return local_output_pixels
}