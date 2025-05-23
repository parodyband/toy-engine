package asset

// import slog  "../../sokol/log"
// import sapp  "../../sokol/app"
// import sg    "../../sokol/gfx"
// import sglue "../../sokol/glue"

// high level

Mesh :: struct {
    index_buffer_bytes : []byte,
    vertex_buffer_bytes: []byte,
    normal_buffer_bytes: []byte,
    uv_buffer_bytes    : []byte,
    vertex_count       : int,
    index_count        : int,
    // all of the above are required,
    // if the mesh is filled and it's missing something
    // then something went wrong
}

Material :: struct {
    tint_color     : [4]f32,
    albedo_texture : Texture,
}

Texture :: struct {
    dimensions : Texture_Dimensions,
    data   : []byte,
    final_pixels_ptr  : [^]byte,
    final_pixels_size : uint,
}

Texture_Dimensions :: struct {
    width  : i32,
    height : i32,
}