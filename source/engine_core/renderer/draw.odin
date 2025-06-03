package renderer


Render_Key :: bit_field u64 {
    pass_type   : u8  | 3 ,   // 0 = shadow, 1 == opaque, 2 = transparent, 3 = outline
    pipeline_id : u16 | 12,   // batch by shader
    material_id : u16 | 16,   // batch by textures
    mesh_id     : u16 | 16,   // batch by vertex/index buffers
    depth_bits  : u16 | 12,   // front-to-back (opaque) or back-to-front (alpha)
    flags       : u8  | 5 ,   // not used yet
}

Draw_Call :: struct {
    key         : Render_Key,
    entity_id   : Entity_Id,
    mesh_id     : u16,
    material_id : u16,
    pipeline_id : u16,
    submesh_id  : u8,
    index_count : int,
}