package renderer

import sg "../../lib/sokol/gfx"
import "../asset/"
import tra "../transform"

Draw_Call :: struct {
    index       : int,
    pipeline    : sg.Pipeline,
    bind        : sg.Bindings,
    index_count : int,
    skip_render : bool,
    visible     : bool,
    renderer    : Mesh_Renderer,
}

Mesh_Renderer :: struct {
    mesh      :   asset.Mesh,
    materials  : []asset.Material,
    transform : tra.Transform,
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