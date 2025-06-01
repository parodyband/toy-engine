package transform

Transform :: struct {
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
    parent   : ^Transform,
    child    : ^Transform,
}