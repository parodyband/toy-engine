package renderer

import sg "../../lib/sokol/gfx"
import "../asset/"

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
    transform : Transform,
}

Transform :: struct {
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
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