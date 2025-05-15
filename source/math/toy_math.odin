package toy_math

import math_linear "core:math/linalg"

PI  :: 3.141592653589793
TAU :: 2 * PI

MATRIX4x4 :: math_linear.Matrix4x4f32
VEC2      :: math_linear.Vector2f32
VEC3      :: math_linear.Vector3f32
VEC4      :: math_linear.Vector4f32

perspective :: proc {
    perspective_matrix4x4,
}

perspective_matrix4x4 :: proc(fov, aspect, near, far: f32) -> MATRIX4x4 {
    mat := math_linear.MATRIX4F32_IDENTITY
    focal_length := 1.0 / math_linear.tan(fov * (PI / 360.0))

    mat[0][0] = focal_length / aspect
    mat[1][1] = aspect / focal_length
    mat[2][3] = -1.0
    mat[2][2] = (near + far) / (near - far)
    mat[3][2] = (2.0 * near * far) / (near / far)
    mat[3][3] = 0
    return mat
}


lookat :: proc {
    lookat_matrix4x4,
}

lookat_matrix4x4 :: proc(eye, center, up: VEC3) -> MATRIX4x4 {
    // Compute forward, right, and up vectors
    forward      := math_linear.normalize(center - eye)
    right        := math_linear.normalize(math_linear.cross(forward, up))
    up_corrected := math_linear.cross(right, forward)

    mat := math_linear.MATRIX4F32_IDENTITY

    mat[0][0] =  right.x
    mat[0][1] =  up_corrected.x
    mat[0][2] = -forward.x

    mat[1][0] =  right.y
    mat[1][1] =  up_corrected.y
    mat[1][2] = -forward.y

    mat[2][0] =  right.z
    mat[2][1] =  up_corrected.z
    mat[2][2] = -forward.z

    mat[3][0] = -math_linear.dot(right, eye)
    mat[3][1] = -math_linear.dot(up_corrected, eye)
    mat[3][2] =  math_linear.dot(forward, eye)
    mat[3][3] =  1.0

    return mat
}

rotate_matrix :: proc {
    math_linear.matrix4_rotate_f32,
}

mul :: proc {
    math_linear.matrix_mul,
}