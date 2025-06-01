package transform

import "core:math/linalg"

Vec3 :: [3]f32
Mat4 :: matrix[4,4]f32

// Internal helper: works on a possibly-nil transform pointer and performs recursion.
compute_model_matrix_internal :: proc(t: ^Transform) -> Mat4 {
    if t == nil {
        return Mat4(1)
    }

    pos := t^.position
    trans := linalg.matrix4_translate_f32({pos[0], pos[1], pos[2]})

    rot_pitch := linalg.matrix4_rotate_f32(t^.rotation[0] * linalg.RAD_PER_DEG, {1,0,0})
    rot_yaw   := linalg.matrix4_rotate_f32(t^.rotation[1] * linalg.RAD_PER_DEG, {0,1,0})
    rot_roll  := linalg.matrix4_rotate_f32(t^.rotation[2] * linalg.RAD_PER_DEG, {0,0,1})
    rot_combined := rot_yaw * rot_pitch * rot_roll

    scale_m := linalg.matrix4_scale_f32({t^.scale[0], t^.scale[1], t^.scale[2]})

    local_model := trans * rot_combined * scale_m

    parent_model := compute_model_matrix_internal(t^.parent)
    return parent_model * local_model
}

// Public convenience wrapper that keeps existing call-sites unchanged.
compute_model_matrix :: proc(transform: Transform) -> Mat4 {
    t_copy := transform
    return compute_model_matrix_internal(&t_copy)
}

get_forward_direction :: proc(transform: Transform) -> Vec3 {
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    forward: Vec3 = {
        rot_combined[2][0],
        rot_combined[2][1],
        rot_combined[2][2],
    }
    
    return forward
}

get_right_direction :: proc(transform: Transform) -> Vec3 {
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    right: Vec3 = {
        rot_combined[0][0],
        rot_combined[0][1],
        rot_combined[0][2],
    }
    
    return right
}

get_up_direction :: proc(transform: Transform) -> Vec3 {
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    up: Vec3 = {
        rot_combined[1][0],
        rot_combined[1][1],
        rot_combined[1][2],
    }
    
    return up
}

// Get all three local axes at once (more efficient than calling individual functions)
get_local_axes :: proc(transform: Transform) -> (right: Vec3, up: Vec3, forward: Vec3) {
    rot_pitch := linalg.matrix4_rotate_f32(transform.rotation[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(transform.rotation[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(transform.rotation[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    rot_combined := rot_yaw * rot_pitch * rot_roll
    
    right = {
        rot_combined[0][0],
        rot_combined[0][1],
        rot_combined[0][2],
    }
    
    up = {
        rot_combined[1][0],
        rot_combined[1][1],
        rot_combined[1][2],
    }
    
    forward = {
        rot_combined[2][0],
        rot_combined[2][1],
        rot_combined[2][2],
    }
    
    return
}

// Utility: Build a rotation matrix (Yaw * Pitch * Roll) from Euler angles in degrees
build_rotation_matrix :: proc(rot: Vec3) -> Mat4 {
    rot_pitch := linalg.matrix4_rotate_f32(rot[0] * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
    rot_yaw   := linalg.matrix4_rotate_f32(rot[1] * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})
    rot_roll  := linalg.matrix4_rotate_f32(rot[2] * linalg.RAD_PER_DEG, {0.0, 0.0, 1.0})
    // Same rotation order as compute_model_matrix (Yaw * Pitch * Roll)
    return rot_yaw * rot_pitch * rot_roll
}

// Recursively compute the absolute/world-space components for a transform
compute_world_components :: proc(t: ^Transform) -> (pos: Vec3, rot: Vec3, scl: Vec3) {
    pos = t.position
    rot = t.rotation
    scl = t.scale

    if t.parent != nil {
        p_pos, p_rot, p_scl := compute_world_components(t.parent)

        // World scale = parent_scale * local_scale (component-wise)
        scl = { p_scl[0] * scl[0], p_scl[1] * scl[1], p_scl[2] * scl[2] }

        // World rotation = parent_rotation + local_rotation (same Euler convention)
        rot = p_rot + rot

        // Scale local position by parent scale first
        scaled_local := Vec3{ pos[0] * p_scl[0], pos[1] * p_scl[1], pos[2] * p_scl[2] }

        // Rotate into parent space
        rot_m := build_rotation_matrix(p_rot)
        local_4 := [4]f32{ scaled_local[0], scaled_local[1], scaled_local[2], 1.0 }
        rotated := rot_m * local_4

        // World position = parent_pos + rotated_local
        pos = p_pos + Vec3{ rotated.x, rotated.y, rotated.z }
    }

    return
}

// Re-implement set_world_transform to assign absolute/world-space values while keeping parent relationship
set_world_transform :: proc(transform_reference: ^Transform, position: Vec3 = {0,0,0}, rotation: Vec3 = {0,0,0}, scale: Vec3 = {1,1,1}) {
    if transform_reference.parent == nil {
        transform_reference.position = position
        transform_reference.rotation = rotation
        transform_reference.scale    = scale
        return
    }

    p_pos, p_rot, p_scl := compute_world_components(transform_reference.parent)

    local_scale := Vec3{
        scale[0] / (p_scl[0] if p_scl[0] != 0 else 1),
        scale[1] / (p_scl[1] if p_scl[1] != 0 else 1),
        scale[2] / (p_scl[2] if p_scl[2] != 0 else 1),
    }

    local_rotation := rotation - p_rot

    diff_world := position - p_pos

    inv_parent_rot := Vec3{ -p_rot[0], -p_rot[1], -p_rot[2] }
    inv_rot_m := build_rotation_matrix(inv_parent_rot)
    diff4 := [4]f32{ diff_world[0], diff_world[1], diff_world[2], 1.0 }
    local_pos_rot := inv_rot_m * diff4

    local_position := Vec3{
        local_pos_rot.x / (p_scl[0] if p_scl[0] != 0 else 1),
        local_pos_rot.y / (p_scl[1] if p_scl[1] != 0 else 1),
        local_pos_rot.z / (p_scl[2] if p_scl[2] != 0 else 1),
    }

    transform_reference.position = local_position
    transform_reference.rotation = local_rotation
    transform_reference.scale    = local_scale
}


