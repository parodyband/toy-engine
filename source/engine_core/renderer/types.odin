package renderer


Camera :: struct {
    fov : f32,
    position : [3]f32,
    rotation : [3]f32,
    target_rotation : [3]f32,
}

Bounds :: struct {
    width, height, half_depth : f32,
}