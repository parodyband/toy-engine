# Odin `glTF2` Package Documentation

This document provides an overview of the `gltf2` Odin package, designed for loading and parsing glTF 2.0 files (both `.gltf` and `.glb` formats).

## Table of Contents
1.  [Overview](#overview)
2.  [Usage Example: Accessing Mesh Data (Sokol Context)](#usage-example-accessing-mesh-data-sokol-context)
3.  [Main API Procedures](#main-api-procedures)
    *   [`load_from_file`](#load_from_file)
    *   [`parse`](#parse)
    *   [`unload`](#unload)
4.  [Core Data Structures](#core-data-structures)
    *   [`Data`](#data-struct)
    *   [`Asset`](#asset-struct)
    *   [`Scene`](#scene-struct)
    *   [`Node`](#node-struct)
    *   [`Mesh`](#mesh-struct)
    *   [`Mesh_Primitive`](#mesh_primitive-struct)
    *   [`Accessor`](#accessor-struct)
    *   [`Buffer_View`](#buffer_view-struct)
    *   [`Buffer`](#buffer-struct)
    *   [`Material`](#material-struct)
    *   [`Texture`](#texture-struct)
    *   [`Image`](#image-struct)
    *   [`Sampler`](#sampler-struct)
    *   [`Animation`](#animation-struct)
    *   [`Skin`](#skin-struct)
    *   [`Camera`](#camera-struct)
    *   [`Options`](#options-struct)
5.  [Error Handling](#error-handling)
    *   [`Error` (union)](#error-union)
    *   [`GLTF_Error`](#gltf_error-struct)
    *   [`JSON_Error`](#json_error-struct)
6.  [Constants](#constants)
7.  [Helper Procedures](#helper-procedures)
    *   [`uri_parse`](#uri_parse)
    *   [`uri_free`](#uri_free)

## Overview

The `gltf2` package provides functionality to read and parse glTF (GL Transmission Format) 2.0 files. It supports both standard glTF (`.gltf` JSON files with external resources) and binary glTF (`.glb` files with embedded resources).

The typical workflow involves:
1.  Loading a glTF file using `load_from_file`.
2.  Accessing the parsed data through the `Data` struct.
3.  Interpreting the various glTF structures (meshes, materials, animations, etc.).
4.  Freeing the loaded data using `unload` when it's no longer needed.

## Usage Example: Accessing Mesh Data (Sokol Context)

This example demonstrates how to load a glTF file, access vertex positions, normals, and index data for the first primitive of the first mesh, and conceptually prepare it for use with a graphics library like Sokol.

```odin
package main

import "core:fmt"
import "core:mem"
import "core:os"
import gltf "vendor:gltf2" // Assuming 'gltf2' is in a vendor directory or accessible path
// import sg "sokol/gfx" // For conceptual Sokol GFX usage

main :: proc() {
    // --- 1. Load the glTF file ---
    // Replace "path/to/your/model.glb" with the actual file path.
    gltf_data, err := gltf.load_from_file("path/to/your/model.glb")
    if err != nil {
        switch e_type in err {
        case gltf.GLTF_Error:
            e := err.(gltf.GLTF_Error)
            fmt.printfln("GLTF Error in %s: %v (param: %v, index: %d)", e.proc_name, e.type, e.param.name, e.param.index)
        case gltf.JSON_Error:
            e := err.(gltf.JSON_Error)
            fmt.printfln("JSON Error: %v at line %d, col %d", e.type, e.parser.line_number, e.parser.column_number)
        }
        return
    }
    defer gltf.unload(gltf_data)

    fmt.printfln("Successfully loaded glTF asset: %s, version: %v", gltf_data.asset.generator, gltf_data.asset.version)

    // --- 2. Navigate to the desired mesh and primitive ---
    // This example uses the first mesh and its first primitive.
    // A real application would likely iterate or select based on names/properties.
    if len(gltf_data.meshes) == 0 {
        fmt.println("No meshes found in the glTF file.")
        return
    }
    mesh := gltf_data.meshes[0] // First mesh

    if len(mesh.primitives) == 0 {
        fmt.printf("Mesh '%s' has no primitives.
", mesh.name)
        return
    }
    primitive := mesh.primitives[0] // First primitive

    var vertex_buffer_bytes: []byte
    var index_buffer_bytes:  []byte
    var vertex_count:        int
    var index_count:         int
    // var sokol_index_type:    sg.index_type // Conceptual

    // --- 3. Access Vertex Position Data ---
    position_accessor_idx, pos_ok := primitive.attributes["POSITION"]
    if !pos_ok {
        fmt.println("Primitive has no POSITION attribute.")
        // Decide how to handle this: skip, error, use default, etc.
    } else {
        if int(position_accessor_idx) < len(gltf_data.accessors) {
            accessor := gltf_data.accessors[position_accessor_idx]
            if accessor.type == .Vector3 && accessor.component_type == .Float {
                buffer_view := gltf_data.buffer_views[accessor.buffer_view]
                buffer := gltf_data.buffers[buffer_view.buffer]
                
                if raw_buffer_bytes, is_bytes := buffer.uri.([]byte); is_bytes {
                    data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
                    element_size := 3 * size_of(f32) // VEC3 of f32
                    data_end_offset := data_start_offset + int(accessor.count) * element_size
                    
                    if data_end_offset <= len(raw_buffer_bytes) {
                        vertex_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset] // This is just positions for now
                        vertex_count = int(accessor.count)
                        fmt.printf("Vertex position data: %d vertices, %d bytes. Stride (from BufferView): %d
", 
                                   vertex_count, len(vertex_buffer_bytes), buffer_view.byte_stride)
                        // Note: If data is interleaved (e.g., Pos, Norm, UV in one buffer_view),
                        // you'd use buffer_view.byte_stride and accessor.byte_offset within that stride.
                        // For this example, we assume positions are contiguous or we are only extracting them.
                    } else {
                        fmt.println("Position data range out of bounds in buffer.")
                    }
                } else {
                     fmt.println("Position buffer URI is not []byte (e.g. external file not yet loaded by this example).")
                }
            } else {
                fmt.println("POSITION accessor is not VEC3 of FLOAT.")
            }
        } else {
            fmt.println("Invalid POSITION accessor index.")
        }
    }

    // --- 4. Access Vertex Normal Data (similar logic to positions) ---
    normal_accessor_idx, norm_ok := primitive.attributes["NORMAL"]
    if !norm_ok {
        fmt.println("Primitive has no NORMAL attribute.")
    } else {
        if int(normal_accessor_idx) < len(gltf_data.accessors) {
            accessor := gltf_data.accessors[normal_accessor_idx]
            if accessor.type == .Vector3 && accessor.component_type == .Float {
                buffer_view := gltf_data.buffer_views[accessor.buffer_view]
                buffer := gltf_data.buffers[buffer_view.buffer]

                if raw_buffer_bytes, is_bytes := buffer.uri.([]byte); is_bytes {
                    data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
                    element_size := 3 * size_of(f32) // VEC3 of f32
                    data_end_offset := data_start_offset + int(accessor.count) * element_size

                    if data_end_offset <= len(raw_buffer_bytes) {
                        normal_data_bytes := raw_buffer_bytes[data_start_offset:data_end_offset]
                        fmt.printf("Vertex normal data: %d normals, %d bytes. Stride (from BufferView): %d
", 
                                   accessor.count, len(normal_data_bytes), buffer_view.byte_stride)
                        // For Sokol: If normals are in a separate buffer, create another sg_buffer.
                        // If interleaved, define vertex layout and stride accordingly in sg_pipeline_desc.
                    } else {
                        fmt.Println("Normal data range out of bounds in buffer.")
                    }
                } // ... error handling for !is_bytes
            } // ... error handling for wrong type/component_type
        } // ... error handling for invalid accessor index
    }

    // --- 5. Access Index Buffer Data ---
    // primitive.indices holds the *accessor index* for the index data.
    // A value < 0 or out of bounds might indicate no indices or an error.
    // The default value for primitive.indices if not in JSON is 0.
    // Ensure this accessor is truly for indices (SCALAR, integer type).
    if primitive.indices >= 0 && int(primitive.indices) < len(gltf_data.accessors) {
        accessor := gltf_data.accessors[primitive.indices]
        if accessor.type == .Scalar { // Indices must be scalars
            component_size: int = 0
            // sokol_index_type = sg.INDEXINVALID // Conceptual
            switch accessor.component_type {
            case .Unsigned_Byte:
                component_size = size_of(u8)
                // sokol_index_type = sg.INDEX_UINT8 // Not directly supported by Sokol, usually u16 or u32.
                                                 // Would require conversion or careful handling.
                fmt.println("Indices are u8. Sokol typically uses u16 or u32.")
            case .Unsigned_Short:
                component_size = size_of(u16)
                // sokol_index_type = sg.INDEX_UINT16 // Conceptual
            case .Unsigned_Int:
                component_size = size_of(u32)
                // sokol_index_type = sg.INDEX_UINT32 // Conceptual
            default:
                fmt.println("Unsupported index component type:", accessor.component_type)
            }

            if component_size > 0 {
                buffer_view := gltf_data.buffer_views[accessor.buffer_view]
                buffer := gltf_data.buffers[buffer_view.buffer]

                if raw_buffer_bytes, is_bytes := buffer.uri.([]byte); is_bytes {
                    data_start_offset := int(buffer_view.byte_offset + accessor.byte_offset)
                    data_end_offset := data_start_offset + int(accessor.count) * component_size
                    
                    if data_end_offset <= len(raw_buffer_bytes) {
                        index_buffer_bytes = raw_buffer_bytes[data_start_offset:data_end_offset]
                        index_count = int(accessor.count)
                        fmt.printf("Index data: %d indices, %d bytes, component type: %v
", 
                                   index_count, len(index_buffer_bytes), accessor.component_type)
                    } else {
                        fmt.Println("Index data range out of bounds in buffer.")
                    }
                } // ... error handling
            }
        } else {
            fmt.println("Accessor for indices is not SCALAR type.")
        }
    } else {
        fmt.println("No valid index accessor found for this primitive (or primitive.indices points to an invalid accessor).")
        // This primitive might be non-indexed (rendered with glDrawArrays).
    }

    // --- 6. Conceptual Sokol GFX Usage ---
    // Ensure you have valid data before creating Sokol resources.
    // if len(vertex_buffer_bytes) > 0 {
    //     vbuf_desc := sg.buffer_desc{
    //         size    = uintptr(len(vertex_buffer_bytes)),
    //         data    = sg.range{ptr = raw_data(vertex_buffer_bytes), size = uintptr(len(vertex_buffer_bytes))},
    //         label   = "gltf-vertex-buffer",
    //         // type = .VERTEXBUFFER, // In older Sokol. Newer versions infer from pipeline.
    //         // usage = .IMMUTABLE,
    //     }
    //     vertex_buffer: sg.buffer = sg.make_buffer(vbuf_desc)
    //     fmt.printfln("Conceptual Sokol vertex buffer created: %v", vertex_buffer.id != sg.INVALID_ID)
    //
    //     // If normals, texcoords etc. are interleaved in this vertex_buffer_bytes,
    //     // the sg_pipeline_desc's layout.attrs would define strides and offsets.
    //     // If they are in separate buffers, create and bind them separately.
    // }

    // if len(index_buffer_bytes) > 0 && sokol_index_type != sg.INDEXINVALID {
    //     ibuf_desc := sg.buffer_desc{
    //         size    = uintptr(len(index_buffer_bytes)),
    //         data    = sg.range{ptr = raw_data(index_buffer_bytes), size = uintptr(len(index_buffer_bytes))},
    //         type    = .INDEXBUFFER,
    //         label   = "gltf-index-buffer",
    //         // usage = .IMMUTABLE,
    //     }
    //     index_buffer: sg.buffer = sg.make_buffer(ibuf_desc)
    //     fmt.printfln("Conceptual Sokol index buffer created: %v", index_buffer.id != sg.INVALID_ID)
    //
    //     // Later, in sg_bindings:
    //     // bind.vertex_buffers[0] = vertex_buffer
    //     // bind.index_buffer = index_buffer
    //
    //     // In sg_pipeline_desc:
    //     // pip_desc.layout.attrs[0].format = .FLOAT3 // For positions
    //     // pip_desc.layout.attrs[1].format = .FLOAT3 // For normals (if present)
    //     // ... define offsets if interleaved using layout.attrs[n].offset
    //     // pip_desc.layout.buffers[0].stride = buffer_view.byte_stride (if using a single interleaved buffer)
    //     // pip_desc.index_type = sokol_index_type
    // }
    
    fmt.println("
Finished processing example.")
}

// Note: For a robust solution, you would typically create helper procedures to:
// 1. Get accessor data as a typed slice (e.g., []f32, []u16) considering component_type and type.
// 2. Handle interleaved vertex data by correctly interpreting buffer_view.byte_stride and accessor.byte_offset.
// 3. Manage memory for data copied out of the main glTF buffer if needed for long-term storage.
// 4. Iterate over all meshes and primitives, and all attributes, not just the first ones.

## Main API Procedures

### `load_from_file`
Loads and parses a glTF file from the given file path. It automatically detects whether the file is a `.gltf` or `.glb` based on its extension.

```odin
load_from_file :: proc(file_name: string, allocator := context.allocator) -> (data: ^Data, err: Error)
```

**Parameters:**
*   `file_name: string`: The path to the glTF file.
*   `allocator: mem.Allocator` (optional): The allocator to use for memory allocations. Defaults to `context.allocator`.

**Returns:**
*   `data: ^Data`: A pointer to the parsed glTF data structure.
*   `err: Error`: An error object if parsing fails, `nil` otherwise.

**Errors:**
*   `GLTF_Error{.No_File}`: If the specified file does not exist.
*   `GLTF_Error{.Cant_Read_File}`: If the file cannot be read.
*   `GLTF_Error{.Unknown_File_Type}`: If the file extension is not `.gltf` or `.glb`.
*   Other errors from `parse`.

### `parse`
Parses glTF data from a byte slice. This is useful if the file content is already loaded into memory.

```odin
parse :: proc(file_content: []byte, opt := Options{}, allocator := context.allocator) -> (data: ^Data, err: Error)
```

**Parameters:**
*   `file_content: []byte`: The byte slice containing the glTF file data.
*   `opt: Options` (optional): Parsing options. See [`Options`](#options-struct).
*   `allocator: mem.Allocator` (optional): The allocator to use. Defaults to `context.allocator`.

**Returns:**
*   `data: ^Data`: A pointer to the parsed glTF data structure.
*   `err: Error`: An error object if parsing fails, `nil` otherwise.

**Errors:**
*   `GLTF_Error{.Data_Too_Short}`: If the provided `file_content` is too short for a valid GLB header.
*   `GLTF_Error{.Bad_GLB_Magic}`: For GLB files, if the magic number is incorrect.
*   `GLTF_Error{.Unsupported_Version}`: If the glTF version is less than 2.
*   `GLTF_Error{.Wrong_Chunk_Type}`: For GLB files, if the first chunk is not a JSON chunk.
*   `JSON_Error`: If there's an error parsing the JSON content.
*   Various `GLTF_Error` types for missing required parameters or invalid types within the glTF structure.

### `unload`
Frees all memory allocated for the glTF data. It is safe to pass `nil` to this procedure.

```odin
unload :: proc(data: ^Data)
```

**Parameters:**
*   `data: ^Data`: A pointer to the `Data` struct to be unloaded. If `nil`, the procedure does nothing.

## Core Data Structures

These are the main structs that represent the parsed glTF data. Most of these correspond directly to objects in the glTF 2.0 specification. Many structs include `name: string`, `extensions: json.Value`, and `extras: json.Value` fields.

*(Note: For brevity, not all fields of every struct are listed. Refer to the glTF 2.0 specification and the source code for complete details. Fields marked as "Required" by comments in the source are critical for a valid glTF asset.)*

### `Data` Struct
The root structure holding all parsed glTF data.

```odin
Data :: struct {
    json_value:          json.Value, // The raw parsed JSON object
    asset:               Asset,
    accessors:           []Accessor,
    animations:          []Animation,
    buffers:             []Buffer,
    buffer_views:        []Buffer_View,
    cameras:             []Camera,
    images:              []Image,
    materials:           []Material,
    meshes:              []Mesh,
    nodes:               []Node,
    samplers:            []Sampler,
    scene:               Integer, // Index of the default scene
    scenes:              []Scene,
    skins:               []Skin,
    textures:            []Texture,
    extensions_used:     []string,
    extensions_required: []string,
    extensions:          json.Value,
    extras:              json.Value,
}
```

### `Asset` Struct
Metadata about the glTF asset.

```odin
Asset :: struct {
    copyright:   string,
    generator:   string,
    version:     Number,     // Required: glTF version (e.g., 2.0)
    min_version: Number,     // Minimum glTF version required
    extensions:  json.Value,
    extras:      json.Value,
}
```

### `Scene` Struct
A collection of root nodes that define a scene.

```odin
Scene :: struct {
    nodes:      []Integer, // Indices of root nodes
    name:       string,
    extensions: json.Value,
    extras:     json.Value,
}
```

### `Node` Struct
A node in the scene hierarchy. It can contain a transform, and refer to a mesh, camera, or skin.

```odin
Node :: struct {
    camera:      Integer,    // Index of a camera
    children:    []Integer,  // Indices of child nodes
    skin:        Integer,    // Index of a skin
    matrix:      Matrix4,    // 4x4 transformation matrix (column-major)
    mesh:        Integer,    // Index of a mesh
    rotation:    Quaternion, // Rotation as a quaternion [x, y, z, w]
    scale:       [3]Number,  // Scale vector
    translation: [3]Number,  // Translation vector
    weights:     []Number,   // Weights for morph targets
    name:        string,
    extensions:  json.Value,
    extras:      json.Value,
}
```
**Default Transform Values:**
*   `matrix`: Identity matrix
*   `rotation`: `[0, 0, 0, 1]` (identity quaternion)
*   `scale`: `[1, 1, 1]`
*   `translation`: `[0, 0, 0]`

### `Mesh` Struct
Geometric data. A mesh is composed of one or more primitives.

```odin
Mesh :: struct {
    primitives: []Mesh_Primitive, // Required: Array of primitives
    weights:    []Number,         // Weights for morph targets
    name:       string,
    extensions: json.Value,
    extras:     json.Value,
}
```

### `Mesh_Primitive` Struct
Defines the geometry of a part of a mesh.

```odin
Mesh_Primitive :: struct {
    attributes: map[string]Integer, // Required: Accessor indices for vertex attributes (e.g., "POSITION", "NORMAL")
    indices:    Integer,            // Accessor index for element indices
    material:   Integer,            // Index of a material
    mode:       Mesh_Primitive_Mode, // Drawing mode (e.g., .Triangles)
    targets:    []Mesh_Target,      // Morph targets
    extensions: json.Value,
    extras:     json.Value,
}
```
*   `Mesh_Primitive_Mode`: Enum like `.Points`, `.Lines`, `.Triangles`, etc. Default: `.Triangles`.
*   `Mesh_Target`: `map[string]Integer` (Currently `mesh_targets_parse` is unimplemented).

### `Accessor` Struct
Defines how to read data from a `Buffer_View`.

```odin
Accessor :: struct {
    buffer_view:    Integer,        // Index of a Buffer_View
    byte_offset:    Integer,        // Offset into the Buffer_View (default: 0)
    component_type: Component_Type, // Required: Data type of components (e.g., .Float, .Unsigned_Short)
    normalized:     bool,           // Whether integer data should be normalized (default: false)
    count:          Integer,        // Required: Number of elements
    type:           Accessor_Type,  // Required: Type of elements (e.g., .Scalar, .Vector3, .Matrix4)
    max:            [16]Number,     // Maximum component values
    min:            [16]Number,     // Minimum component values
    sparse:         ^Accessor_Sparse, // Sparse storage information
    name:           string,
    extensions:     json.Value,
    extras:         json.Value,
}
```
*   `Component_Type`: Enum like `.Byte`, `.Unsigned_Byte`, `.Short`, `.Unsigned_Short`, `.Unsigned_Int`, `.Float`.
*   `Accessor_Type`: Enum like `.Scalar`, `.Vector2`, `.Vector3`, `.Vector4`, `.Matrix2`, `.Matrix3`, `.Matrix4`.

### `Accessor_Sparse` Struct
Information for sparse accessors.

```odin
Accessor_Sparse :: struct {
    count:      Integer, // Number of sparse elements (Note: source comment says "Not used by this implementation" for this field)
    indices:    []Accessor_Sparse_Indices, // Required
    values:     []Accessor_Sparse_Values,  // Required
    extensions: json.Value,
    extras:     json.Value,
}

Accessor_Sparse_Indices :: struct {
    buffer_view:    Integer,        // Required
    byte_offset:    Integer,        // Default: 0
    component_type: Component_Type, // Required
    extensions:     json.Value,
    extras:         json.Value,
}

Accessor_Sparse_Values :: struct {
    buffer_view: Integer,        // Required
    byte_offset: Integer,        // Default: 0
    extensions:  json.Value,
    extras:      json.Value,
}
```

### `Buffer_View` Struct
A view into a `Buffer`, representing a slice of binary data.

```odin
Buffer_View :: struct {
    buffer:      Integer,          // Required: Index of a Buffer
    byte_offset: Integer,          // Offset into the Buffer (default: 0)
    byte_length: Integer,          // Required: Length of the Buffer_View in bytes
    byte_stride: Integer,          // Stride between elements in bytes (0 means tightly packed)
    target:      Buffer_Type_Hint, // Hint for GPU buffer type (e.g., .Array_Buffer, .Element_Array_Buffer)
    name:        string,
    extensions:  json.Value,
    extras:      json.Value,
}
```
*   `Buffer_Type_Hint`: Enum.

### `Buffer` Struct
Represents raw binary data.

```odin
Buffer :: struct {
    uri:         Uri,     // URI to the buffer data (can be data URI, external file path, or []byte for GLB)
    byte_length: Integer, // Required: Length of the buffer in bytes
    name:        string,
    extensions:  json.Value,
    extras:      json.Value,
}
```
*   `Uri`: `union {string, []byte}`. `uri_parse` attempts to load data if it's a file path or decode if it's a data URI. For GLB, this is typically populated with `[]byte` from the binary chunk.

### `Material` Struct
Defines the appearance of a `Mesh_Primitive`.

```odin
Material :: struct {
    name:                 string,
    extensions:           json.Value,
    extras:               json.Value,
    metallic_roughness:   Material_Metallic_Roughness, // PBR metallic-roughness properties
    normal_texture:       Material_Normal_Texture_Info,
    occlusion_texture:    Material_Occlusion_Texture_Info,
    emissive_texture:     Texture_Info,
    emissive_factor:      [3]Number, // Default: [0, 0, 0]
    alpha_mode:           Alpha_Mode, // Default: .Opaque
    alpha_cutoff:         Number,    // Default: 0.5
    double_sided:         bool,      // Default: false
}

Material_Metallic_Roughness :: struct {
    base_color_factor:        [4]Number,    // Default: [1, 1, 1, 1]
    base_color_texture:       Texture_Info,
    metallic_factor:          Number,       // Default: 1
    roughness_factor:         Number,       // Default: 1
    metallic_roughness_texture: Texture_Info,
    extensions:               json.Value,
    extras:                   json.Value,
}

Material_Normal_Texture_Info :: struct {
    index:      Integer, // Required: Texture index
    tex_coord:  Integer, // Tex coord set (default: 0)
    scale:      Number,  // Normal map scale (default: 1)
    extensions: json.Value,
    extras:     json.Value,
}

Material_Occlusion_Texture_Info :: struct {
    index:      Integer, // Required: Texture index
    tex_coord:  Integer, // Tex coord set (default: 0)
    strength:   Number,  // Occlusion strength (default: 1)
    extensions: json.Value,
    extras:     json.Value,
}

Texture_Info :: struct {
    index:      Integer, // Required: Texture index
    tex_coord:  Integer, // Tex coord set (default: 0)
    extensions: json.Value,
    extras:     json.Value,
}
```
*   `Alpha_Mode`: Enum (`.Opaque`, `.Mask`, `.Blend`).

### `Texture` Struct
Combines an `Image` with a `Sampler`.

```odin
Texture :: struct {
    sampler:    Integer, // Index of a Sampler
    source:     Integer, // Index of an Image
    name:       string,
    extensions: json.Value,
    extras:     json.Value,
}
```

### `Image` Struct
Image data, can be from a URI or a `Buffer_View`.

```odin
Image :: struct {
    uri:         Uri,          // URI of the image (data URI or file path)
    mime_type:   Image_Mime_Type, // Mime type (e.g., .JPEG, .PNG) if uri is used
    buffer_view: Integer,      // Index of a Buffer_View if data is in a buffer
    name:        string,
    extensions:  json.Value,
    extras:      json.Value,
}
```
*   `Image_Mime_Type`: Enum (`.JPEG`, `.PNG`).

### `Sampler` Struct
Defines texture sampling parameters (filtering, wrapping).

```odin
Sampler :: struct {
    mag_filter: Magnification_Filter, // Magnification filter (e.g., .Nearest, .Linear)
    min_filter: Minification_Filter,  // Minification filter (e.g., .Nearest_Mipmap_Linear)
    wrap_s:     Wrap_Mode,            // Wrap mode for S coordinate (default: .Repeat)
    wrap_t:     Wrap_Mode,            // Wrap mode for T coordinate (default: .Repeat)
    name:       string,
    extensions: json.Value,
    extras:     json.Value,
}
```
*   `Magnification_Filter`, `Minification_Filter`, `Wrap_Mode`: Enums defining WebGL sampler states.

### `Animation` Struct
Keyframe animation data.

```odin
Animation :: struct {
    channels:   []Animation_Channel, // Required
    samplers:   []Animation_Sampler, // Required
    name:       string,
    extensions: json.Value,
    extras:     json.Value,
}

Animation_Channel :: struct {
    sampler:    Integer,                  // Required: Index of an Animation_Sampler
    target:     Animation_Channel_Target, // Required: Node and property to animate
    extensions: json.Value,
    extras:     json.Value,
}

Animation_Channel_Target :: struct {
    node:       Integer,                    // Index of the target Node
    path:       Animation_Channel_Path,     // Required: Property to animate (e.g., .Translation, .Rotation)
    extensions: json.Value,
    extras:     json.Value,
}

Animation_Sampler :: struct {
    input:         Integer,              // Required: Accessor index for keyframe times
    interpolation: Interpolation_Mode,   // Interpolation mode (default: .Linear)
    output:        Integer,              // Required: Accessor index for keyframe values
    extensions:    json.Value,
    extras:        json.Value,
}
```
*   `Animation_Channel_Path`: Enum (`.Translation`, `.Rotation`, `.Scale`, `.Weights`).
*   `Interpolation_Mode`: Enum (`.Linear`, `.Step`, `.Cubic_Spline`).

### `Skin` Struct
Joints and matrices for skinned animation.

```odin
Skin :: struct {
    inverse_bind_matrices: Integer,   // Accessor index for inverse bind matrices
    skeleton:              Integer,   // Root node of the skeleton
    joints:                []Integer, // Required: Indices of joint nodes
    name:                  string,
    extensions:            json.Value,
    extras:                json.Value,
}
```

### `Camera` Struct
Defines a camera, either perspective or orthographic.

```odin
Camera :: struct {
    type:         Camera_Type, // Union: Orthographic_Camera or Perspective_Camera
    name:         string,
    extensions:   json.Value,
    extras:       json.Value,
}

Camera_Type :: union {
    Orthographic_Camera,
    Perspective_Camera,
}

Orthographic_Camera :: struct {
    xmag:       Number, // Required: Horizontal magnification
    ymag:       Number, // Required: Vertical magnification
    zfar:       Number, // Required: Far clipping plane
    znear:      Number, // Required: Near clipping plane
    extensions: json.Value,
    extras:     json.Value,
}

Perspective_Camera :: struct {
    aspect_ratio: Number, // Aspect ratio
    yfov:         Number, // Required: Vertical field of view in radians
    zfar:         Number, // Far clipping plane
    znear:        Number, // Required: Near clipping plane
    extensions:   json.Value,
    extras:       json.Value,
}
```

### `Options` Struct
Options for parsing glTF data with the `parse` procedure.

```odin
Options :: struct {
    delete_content: bool,   // If true, the input file_content slice will be deleted after parsing (default: false, but true in load_from_file)
    gltf_dir:       string, // Directory of the glTF file, used for resolving relative URIs
    is_glb:         bool,   // If true, parse as a GLB file (default: false, but set by load_from_file)
}
```

## Error Handling

Errors are returned as an `Error` union.

### `Error` (union)
The main error type returned by parsing procedures.

```odin
Error :: union {
    GLTF_Error,
    JSON_Error,
    nil, // No error
}
```
You can switch on this union to determine the type of error.

### `GLTF_Error` Struct
Represents errors specific to glTF parsing logic.

```odin
GLTF_Error_Type :: enum {
    No_File,
    Cant_Read_File,
    Unknown_File_Type,
    Data_Too_Short,
    Bad_GLB_Magic,
    Unsupported_Version,
    Wrong_Chunk_Type,
    JSON_Missing_Section,
    Invalid_Type,
    Missing_Required_Parameter,
}

GLTF_Error_Param :: struct {
    name:  string, // Name of the parameter or file
    index: int,    // Index if error relates to an array item
}

GLTF_Error :: struct {
    type:      GLTF_Error_Type,
    proc_name: string, // Name of the procedure where the error occurred
    param:     GLTF_Error_Param,
}
```
**Example:**
```odin
data, err := gltf2.load_from_file("my_model.glb")
if err != nil {
    switch e in err {
    case gltf2.GLTF_Error:
        fmt.printfln("GLTF Error in %s: %v (param: %v, index: %d)", e.proc_name, e.type, e.param.name, e.param.index)
    case gltf2.JSON_Error:
        fmt.printfln("JSON Error: %v at line %d, col %d", e.type, e.parser.line_number, e.parser.column_number)
    }
    return
}
// Use data
gltf2.unload(data)
```

### `JSON_Error` Struct
Represents errors from the underlying JSON parser.

```odin
JSON_Error :: struct {
    type:   json.Error_Type,
    parser: json.Parser, // The JSON parser instance for more details
}
```

## Constants

*   `GLB_MAGIC :: 0x46546c67`: The magic number for GLB files ("glTF").
*   `GLB_HEADER_SIZE :: size_of(GLB_Header)`
*   `GLB_CHUNK_HEADER_SIZE :: size_of(GLB_Chunk_Header)`
*   `GLTF_MIN_VERSION :: 2`: Minimum supported glTF version.
*   Various `SCENE_KEY`, `ASSET_KEY`, `EXTENSIONS_KEY`, etc. are used internally for JSON parsing (not typically directly used by the package consumer).

## Helper Procedures

### `uri_parse`
Parses a URI string. If it's a file path, it attempts to read the file. If it's a "data" URI with base64 encoding, it decodes the data.

```odin
uri_parse :: proc(uri: Uri, gltf_dir: string) -> Uri
```
*   `uri: Uri`: The URI to parse (can be `string` or `[]byte`). If already `[]byte`, it's returned directly.
*   `gltf_dir: string`: The base directory of the glTF file, for resolving relative file paths.
*   Returns: `Uri` (either `string` if not parsable/unchanged, or `[]byte` with loaded/decoded data).

### `uri_free`
Frees the memory if the URI contains `[]byte` data.

```odin
uri_free :: proc(uri: Uri)
```
*   `uri: Uri`: The URI to potentially free.

*(This documentation is based on the provided `gltf.odin` source code. Some internal parsing procedures and type definitions are not detailed here for brevity, as they are not part of the primary public API for consuming the package.)* 