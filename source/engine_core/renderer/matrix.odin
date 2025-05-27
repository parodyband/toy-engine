package renderer

import "core:math/linalg"

import sapp "../../lib/sokol/app"

Mat4 :: matrix[4,4]f32

compute_view_projection :: proc(position : [3]f32, rotation : [3]f32) -> Mat4 {
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0, false)
    
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    return proj * view
}

compute_ortho_projection :: proc(position : [3]f32, rotation : [3]f32, bounds : Bounds) -> Mat4 {
    proj := linalg.matrix_ortho3d_f32 (
        -bounds.width,
        bounds.width,
        -bounds.height,
        bounds.height,
        0.1,
        bounds.half_depth * 2,
        false,
    )
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    return proj * view
}

// Creates an orthographic projection where the camera is centered in the view volume.
// This makes it easier to reason about shadow map coverage - the view extends
// half_depth units in front of and behind the camera position.
compute_centered_ortho_projection :: proc(position : [3]f32, rotation : [3]f32, bounds : Bounds) -> Mat4 {    
    proj := linalg.matrix_ortho3d_f32 (
        -bounds.width / 2,
        bounds.width / 2,
        -bounds.height / 2,
        bounds.height / 2,
        -bounds.half_depth,
        bounds.half_depth,
        false,  // Don't flip Z axis for shadow mapping
    )
    
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    return proj * view
}