package transform
import ass "../asset"

Transform :: struct {
    position : [3]f32,
    rotation : [3]f32,
    scale    : [3]f32,
}

GameObject :: struct {
    transform : Transform,
    parent    : Maybe(Transform),
    child     : Maybe(Transform),
    mesh      : ass.Mesh,
}