package renderer

import "core:math/linalg"

import sapp "../../lib/sokol/app"
import ren "../renderer"

Mat4 :: matrix[4,4]f32

compute_view_projection :: proc (position : [3]f32, rotation : [3]f32) -> Mat4 {
    proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0)
    
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    inv_rot_pitch := linalg.matrix4_rotate_f32(-rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    inv_rot_yaw   := linalg.matrix4_rotate_f32(-rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    inv_rot_roll  := linalg.matrix4_rotate_f32(-rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Create translation matrix for camera position (inverse of camera's world translation)
    trans := linalg.matrix4_translate_f32({-position[0], -position[1], -position[2]})
    
    // View matrix V = R_inverse * T_inverse
    view_rotation_inv := inv_rot_roll * inv_rot_pitch * inv_rot_yaw
    view := view_rotation_inv * trans
    flip_z := linalg.matrix4_scale_f32({1.0, 1.0, -1.0})
    return proj * flip_z * view
}

compute_model_matrix :: proc(t: ren.Transform) -> Mat4 {
    position := t.position
    trans := linalg.matrix4_translate_f32({position[0], position[1], position[2]})

    // Rotation matrices (convert degrees to radians)
    // rotation[0] is Pitch (around X), rotation[1] is Yaw (around Y), rotation[2] is Roll (around Z)
    rot_pitch := linalg.matrix4_rotate_f32(t.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(t.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(t.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})

    // Scale matrix
    scale := linalg.matrix4_scale_f32({t.scale[0], t.scale[1], t.scale[2]})

    // Combine rotations: roll, then pitch, then yaw (matching camera rotation order)
    rot_combined := rot_yaw * rot_pitch * rot_roll

    // Final model matrix: T * R * S (Translation * Rotation * Scale)
    // This ensures objects rotate and scale around their own origin point
    return trans * rot_combined * scale
}