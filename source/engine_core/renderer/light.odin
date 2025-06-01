package renderer
import trans "../transform"

Light :: union {
    Point_Light,
    Directional_Light,
}

Point_Light :: struct {
    transform : trans.Transform,
    color     : [4]f32,
    intensity : f32,
}

Directional_Light :: struct {
    transform : trans.Transform,
    color     : [4]f32,
    intensity : f32,
    bounds    : Bounds,
}

get_light_view_proj :: proc(light : Light) -> Mat4 {
    vp : Mat4
    #partial switch light_value in light {
        case Directional_Light: vp = compute_ortho_projection(
            light_value.transform.position,
			light_value.transform.rotation,
			light_value.bounds,
        )
    }
    return vp
}