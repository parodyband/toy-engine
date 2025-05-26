package renderer
import trans "../transform"
import sg "../../lib/sokol/gfx"

Light :: union {
    Point_Light,
    Directional_Light,
}

Point_Light :: struct {
    transform : trans.Transform,
    color     : [4]f32,
    intensity : f32,
    shadow    : Shadow_Properties,
}

Directional_Light :: struct {
    transform : trans.Transform,
    color     : [4]f32,
    intensity : f32,
    bounds    : Bounds,
    shadow    : Shadow_Properties,
}

Shadow_Properties :: struct {
    light_view_proj : Mat4,
}