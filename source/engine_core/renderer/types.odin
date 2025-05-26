package renderer

import sg "../../lib/sokol/gfx"
import ass "../asset/"
import trans "../transform"

Draw_Call :: struct {
    index       : int,
    opaque      : Render_Pass_Props,
    shadow      : Render_Pass_Props,
    index_count : int,
    skip_render : bool,
    visible     : bool,
    renderer    : Mesh_Renderer,
}

Mesh_Renderer :: struct {
    mesh      :   ass.Mesh,
    materials : []ass.Material,
    transform : trans.Transform,
}

Camera :: struct {
    fov : f32,
    position : [3]f32,
    rotation : [3]f32,
    target_rotation : [3]f32,
}

Bounds :: struct {
    left, right, bottom, top, near, far : f32,
}

Render_Pass_Props :: struct {
    pipeline : sg.Pipeline,
    bindings : sg.Bindings,
}