package asset

import "base:runtime"

import "core:log"
import "core:image/png"
import "core:fmt"
import "core:math"

import "../../lib/glTF2"


load_mesh_from_glb_data :: proc(glb_data : ^glTF2.Data) -> Mesh {

	loaded_mesh_data : Mesh

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

		// Copy the vertex data instead of just slicing
		vertex_data_slice := raw_buffer_bytes[data_start_offset:data_end_offset]
		loaded_mesh_data.vertex_buffer_bytes = make([]byte, len(vertex_data_slice))
		copy(loaded_mesh_data.vertex_buffer_bytes, vertex_data_slice)
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
				
				// Copy the normal data
				normal_data_slice := raw_buffer_bytes[data_start_offset:data_end_offset]
				loaded_mesh_data.normal_buffer_bytes = make([]byte, len(normal_data_slice))
				copy(loaded_mesh_data.normal_buffer_bytes, normal_data_slice)
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
				
				// Copy the UV data
				uv_data_slice := raw_buffer_bytes[data_start_offset:data_end_offset]
				loaded_mesh_data.uv_buffer_bytes = make([]byte, len(uv_data_slice))
				copy(loaded_mesh_data.uv_buffer_bytes, uv_data_slice)
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
			
			// Copy the index data
			index_data_slice := raw_buffer_bytes[data_start_offset:data_end_offset]
			loaded_mesh_data.index_buffer_bytes = make([]byte, len(index_data_slice))
			copy(loaded_mesh_data.index_buffer_bytes, index_data_slice)
			loaded_mesh_data.index_count = int(accessor.count)
		} else {
			fmt.println("Primitive has no indices defined.")
		}
	}

	return loaded_mesh_data
}

load_texture_from_glb_data :: proc(glb_data : ^glTF2.Data) -> Texture {  
    mat   := glb_data.materials[0]
    pbr   :  glTF2.Material_Metallic_Roughness = mat.metallic_roughness.?
    tex_i := int(pbr.base_color_texture.?.index)
    bytes := get_glb_image_bytes(glb_data, tex_i)

    // Validate we have image data
    if len(bytes) == 0 {
        fmt.println("ERROR: No image bytes extracted from GLB!")
        return Texture{}
    }
    
    // Check PNG signature (first 8 bytes should be: 137 80 78 71 13 10 26 10)
    if len(bytes) >= 8 {
        png_signature := []u8{137, 80, 78, 71, 13, 10, 26, 10}
        is_png := true
        for i in 0..<8 {
            if bytes[i] != png_signature[i] {
                is_png = false
                break
            }
        }
        if is_png {
            fmt.println("Valid PNG signature detected")
        } else {
            fmt.printfln("WARNING: Data doesn't look like PNG. First 8 bytes: %v", bytes[:8])
        }
    }

    img, err := png.load_from_bytes(data = bytes, allocator = context.allocator)
	if err != nil {
		fmt.printfln("PNG load error: %v", err)
		assert(false, "texture decode failed")
	}

	// Get the actual pixel data size
	pixels := img.pixels.buf[:]
	byte_len := len(pixels)  // For []u8, len() gives us the byte count
	
	// Validate we have pixel data
	if byte_len == 0 {
		fmt.println("ERROR: PNG pixel buffer is empty!")
		return Texture{}
	}
	
	// PNG loader should tell us the format
	fmt.printfln("PNG loaded: %dx%d, channels: %d, depth: %d bits", 
		img.width, img.height, img.channels, img.depth)
	
	// Calculate expected size based on channels
	expected_size := img.width * img.height * img.channels * (img.depth / 8)
	fmt.printfln("Pixel data size: %d bytes, expected: %d bytes", byte_len, expected_size)
	
	final_pixels := pixels
	final_pixels_size := uint(byte_len)

	// Only convert if we have RGB data (3 channels)
	if img.channels == 3 && img.depth == 8 {
		fmt.println("Converting RGB to RGBA...")
		converted_pixels_slice := rgb_to_rgba(pixels, img.width, img.height, context.allocator)
		final_pixels = converted_pixels_slice
		final_pixels_size = uint(len(converted_pixels_slice))
	} else if img.channels == 4 && img.depth == 8 {
		fmt.println("Image already in RGBA format")
	} else {
		log.errorf("Unsupported PNG format: %v channels, %v bits per channel", img.channels, img.depth)
		return Texture{} // Return empty texture on error
	}

	dimensions := Texture_Dimensions{
		width  = i32(img.width),
		height = i32(img.height),
	}

	// Convert slice to dynamic array
	dynamic_pixels := make([dynamic]u8, len(final_pixels))
	copy(dynamic_pixels[:], final_pixels)

	fmt.printfln("Final texture: %dx%d, %d bytes", 
		img.width, img.height, len(dynamic_pixels))

	return fill_mip_chain(dynamic_pixels, dimensions, 5)
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

    fmt.printfln("Extracting image %d from GLB...", tex_idx)

    if img.buffer_view != nil {
        view  := d.buffer_views[img.buffer_view.?]
        buf   := d.buffers[view.buffer].uri.([]byte)
        start := int(view.byte_offset)
        length := int(view.byte_length)
        fmt.printfln("Image in buffer view: offset=%d, length=%d bytes", start, length)
        return buf[start : start + length]
    }

    // Image stored as URI
    bytes := img.uri.([]byte)
    fmt.printfln("Image as URI: %d bytes", len(bytes))
    return bytes
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

calculate_smooth_normals :: proc(mesh_data: Mesh) -> []byte {
	// Create a map to store positions and their associated normals
	Position_Key :: struct {
		x, y, z: f32,
	}
	
	position_normals := make(map[Position_Key][dynamic][3]f32)
	defer delete(position_normals)
	
	// Parse vertex positions and normals
	vertex_count := mesh_data.vertex_count
	
	// Process each vertex
	for i in 0..<vertex_count {
		// Read position (3 floats)
		pos_offset := i * 3 * size_of(f32)
		pos_x := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset])^
		pos_y := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset + size_of(f32)])^
		pos_z := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset + 2*size_of(f32)])^
		
		// Read normal (3 floats)
		norm_offset := i * 3 * size_of(f32)
		norm_x := (cast(^f32)&mesh_data.normal_buffer_bytes[norm_offset])^
		norm_y := (cast(^f32)&mesh_data.normal_buffer_bytes[norm_offset + size_of(f32)])^
		norm_z := (cast(^f32)&mesh_data.normal_buffer_bytes[norm_offset + 2*size_of(f32)])^
		
		// Create position key (with some epsilon for floating point comparison)
		epsilon : f32 = 0.0001
		key := Position_Key{
			x = f32(int(pos_x / epsilon)) * epsilon,
			y = f32(int(pos_y / epsilon)) * epsilon,
			z = f32(int(pos_z / epsilon)) * epsilon,
		}
		
		// Add normal to the list for this position
		if !(key in position_normals) {
			position_normals[key] = make([dynamic][3]f32)
		}
		append(&position_normals[key], [3]f32{norm_x, norm_y, norm_z})
	}
	
	// Create new normal buffer with averaged normals
	smooth_normals := make([]byte, len(mesh_data.normal_buffer_bytes))
	
	// Process each vertex again and write smoothed normal
	for i in 0..<vertex_count {
		// Read position again
		pos_offset := i * 3 * size_of(f32)
		pos_x := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset])^
		pos_y := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset + size_of(f32)])^
		pos_z := (cast(^f32)&mesh_data.vertex_buffer_bytes[pos_offset + 2*size_of(f32)])^
		
		// Create position key
		epsilon : f32 = 0.0001
		key := Position_Key{
			x = f32(int(pos_x / epsilon)) * epsilon,
			y = f32(int(pos_y / epsilon)) * epsilon,
			z = f32(int(pos_z / epsilon)) * epsilon,
		}
		
		// Average all normals at this position
		normals_list := position_normals[key]
		avg_normal := [3]f32{0, 0, 0}
		
		for normal in normals_list {
			avg_normal.x += normal.x
			avg_normal.y += normal.y
			avg_normal.z += normal.z
		}
		
		normal_count := f32(len(normals_list))
		avg_normal.x /= normal_count
		avg_normal.y /= normal_count
		avg_normal.z /= normal_count
		
		// Normalize the averaged normal
		length := math.sqrt(avg_normal.x * avg_normal.x + avg_normal.y * avg_normal.y + avg_normal.z * avg_normal.z)
		if length > 0 {
			avg_normal.x /= length
			avg_normal.y /= length
			avg_normal.z /= length
		}
		
		// Write to smooth normal buffer
		norm_offset := i * 3 * size_of(f32)
		(cast(^f32)&smooth_normals[norm_offset])^ = avg_normal.x
		(cast(^f32)&smooth_normals[norm_offset + size_of(f32)])^ = avg_normal.y
		(cast(^f32)&smooth_normals[norm_offset + 2*size_of(f32)])^ = avg_normal.z
	}
	
	// Clean up dynamic arrays
	for _, &normals in position_normals {
		delete(normals)
	}
	
	return smooth_normals
}