package renderer
import tra "../transform"

Light :: union {
    Point_Light,
    Directional_Light,
}

Point_Light :: struct {
    transform : tra.Transform,
    color     : [4]f32,
    intensity : f32,
    shadow    : Shadow_Properties,
}

Directional_Light :: struct {
    transform : tra.Transform,
    color     : [4]f32,
    intensity : f32,
    shadow    : Shadow_Properties,
}

Shadow_Properties :: struct {

}