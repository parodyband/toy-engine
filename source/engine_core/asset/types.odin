package asset

Mesh :: struct {
    index_buffer_bytes : []byte,
    vertex_buffer_bytes: []byte,
    normal_buffer_bytes: []byte,
    uv_buffer_bytes    : []byte,
    vertex_count       : int,
    index_count        : int,
}

Material :: struct {
    tint_color     : [4]f32,
    albedo_texture_hash : u64,
}

Texture :: struct {
    dimensions : Texture_Dimensions,
    mip_chain  : Mip_Chain,
}

Mip_Map :: struct {
    final_pixels : [dynamic]byte,
}

Mip_Chain :: []Mip_Map

Texture_Dimensions :: struct {
    width  : i32,
    height : i32,
}