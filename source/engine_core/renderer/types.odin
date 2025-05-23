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
    renderer    : ^Mesh_Renderer,
}

Mesh_Renderer :: struct {
    render_mesh      :   asset.Mesh,
    render_materials : []asset.Material,
    render_transform : Transform,
}

Transform :: struct {
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
}