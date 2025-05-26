package transform

import "core:math/linalg"
// import sapp "../../lib/sokol/app"

Vec3 :: [3]f32
Mat4 :: matrix[4,4]f32

compute_model_matrix :: proc(t: Transform) -> Mat4 {
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

get_forward_direction :: proc(transform: Transform) -> Vec3 {
    // Build the rotation matrix the same way as in compute_model_matrix
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    // Combine rotations in the same order: yaw * pitch * roll
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    // Extract forward direction from the rotation matrix
    // The third column of the rotation matrix represents the Z-axis after rotation
    // In this coordinate system, positive Z is forward
    forward: Vec3 = {
        rot_combined[2][0],   // Z-axis X component
        rot_combined[2][1],   // Z-axis Y component
        rot_combined[2][2],   // Z-axis Z component
    }
    
    return forward
}