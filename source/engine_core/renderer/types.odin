package renderer

import sg "../../lib/sokol/gfx"
import ass "../asset/"
import trans "../transform"

Render_Key :: bit_field u64 {
    pass_type   : u8  | 3 ,   // 0 = shadow, 1 == opaque, 2 = transparent, 3 = outline
    pipeline_id : u16 | 12,   // batch by shader
    material_id : u16 | 16,   // batch by textures
    mesh_id     : u16 | 16,   // batch by vertex/index buffers
    depth_bits  : u16 | 12,   // front-to-back (opaque) or back-to-front (alpha)
    flags       : u8  | 5 ,   // not used yet
}

Draw_Call_ID :: i16


















// OLD

Draw_Call :: struct {
    index       : int,
    opaque      : Render_Pass_Props,
    shadow      : Render_Pass_Props,
    outline     : Render_Pass_Props,
    index_count : int,
    skip_render : bool,
    visible     : bool,
    entity      : Entity,
}

Mesh_Renderer :: struct {
    mesh      :   ass.Mesh,
    materials : []ass.Material,
}

Camera :: struct {
    fov : f32,
    position : [3]f32,
    rotation : [3]f32,
    target_rotation : [3]f32,
}

Bounds :: struct {
    width, height, half_depth : f32,
}

Rendering_Resources :: struct {
    shadow_resources : Shadow_Pass_Resources,
    texture_pool     : ass.Texture_Pool,
}

Entity :: struct {
    transform     : trans.Transform,
    mesh_renderer : Mesh_Renderer,
}

Render_Pass_Props :: struct {
    pipeline    : sg.Pipeline,
    bindings    : sg.Bindings,
}

Shadow_Pass_Resources :: struct {
    shadow_attachments : sg.Attachments,
	shadow_map         : sg.Image,
	shadow_sampler     : sg.Sampler,
}