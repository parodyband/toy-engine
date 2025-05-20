package render

import slog  "../../sokol/log"
import sapp  "../../sokol/app"
import sg    "../../sokol/gfx"
import sglue "../../sokol/glue"

// high level

mesh_renderer :: struct {
    render_mesh      : mesh,
    render_materials : []material,
    render_transfrom : transform
}

mesh :: struct {
    index_buffer_bytes : []byte,
    vertex_buffer_bytes: []byte,
    normal_buffer_bytes: []byte,
    uv_buffer_bytes    : []byte,
    vertex_count       : int,
    index_count        : int,
    // all of the above are required,
    // if when the mesh is filled, its missing something
    // then something went wrong
}

material :: struct {
    tint_color     : [4]f32,
    albedo_texture : texture,
}

texture :: struct {
    width  : i32,
    height : i32,
    data   : []byte,
}

transform :: struct {
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
}