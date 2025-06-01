package renderer

import "core:math/linalg"

import sapp "../../lib/sokol/app"

Mat4 :: matrix[4,4]f32

compute_view_projection :: proc(position : [3]f32, rotation : [3]f32, fov : f32) -> Mat4 {
    proj := linalg.matrix4_perspective(fov * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 1000.0, false)
    
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
    // Treat bounds.width/height as full extents (edge-to-edge).
    // Convert to half-extents for the ortho call so that the frustum
    // is centred on the forward axis and starts just in front of the light.
    // We only care about what lies in front of the light (negative view-Z),
    // so we use a forward-only depth range: near = 0.1, far = bounds.half_depth.

    half_w := bounds.width * 0.5
    half_h := bounds.height * 0.5

    proj := matrix_ortho_vulkan (
        -half_w,
         half_w,
        -half_h,
         half_h,
         0.0,
         bounds.half_depth,
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
// half_depth units in front of and behind the camera position.
compute_centered_ortho_projection :: proc(position : [3]f32, rotation : [3]f32, bounds : Bounds) -> Mat4 {    
    proj := linalg.matrix_ortho3d_f32 (
        -bounds.width / 2,
        bounds.width / 2,
        -bounds.height / 2,
        bounds.height / 2,
        0.0,
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

matrix_ortho_opengl :: proc(left, right, bottom, top, near, far: f32, flip_z_axis: bool = false) -> Mat4 {
    m: Mat4
    m = Mat4{} // zero-initialise

    m[0,0] =  2.0 / (right - left)
    m[1,1] =  2.0 / (top   - bottom)
    m[2,2] =  -2.0 / (far - near) if flip_z_axis else 2.0 / (far - near)
    m[0,3] = -(right + left)   / (right - left)
    m[1,3] = -(top   + bottom) / (top   - bottom)
    m[2,3] = -(far + near)     / (far  - near)

    m[3,3] = 1.0
    return m
}

matrix_ortho_vulkan :: proc(left, right, bottom, top, near, far: f32, flip_z_axis: bool = false) -> Mat4 {
    m: Mat4
    m = Mat4{}

    m[0,0] =  2.0 / (right - left)
    m[1,1] =  2.0 / (top   - bottom)
    m[2,2] =   -1.0 / (far - near) if flip_z_axis else 1.0 / (far - near)

    m[0,3] = -(right + left)   / (right - left)
    m[1,3] = -(top   + bottom) / (top   - bottom)
    m[2,3] = -near             / (far   - near)   // note: only –near

    m[3,3] = 1.0
    return m
}