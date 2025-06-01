package gameplay

import "core:math/linalg"

import sapp  "../lib/sokol/app"
import ren "../engine_core/renderer"
import inp "../engine_core/input"

import "../common"

import trans "../engine_core/transform"

Mat4  :: matrix[4,4]f32
Vec3  :: [3]f32
Vec2  :: [2]f32
Float :: f32

Tinker     : ^ren.Entity
Tinker_Key : ^ren.Entity

on_load :: proc(memory : ^common.Game_Memory) {
    Tinker     = ren.create_entity_by_mesh_path("assets/Tinker.glb",     &memory.render_queue, &memory.shadow_resources, {0,5,0})
	Tinker_Key = ren.create_entity_by_mesh_path("assets/Tinker_Key.glb", &memory.render_queue, &memory.shadow_resources)
    Tinker_Key.transform.parent = &Tinker.transform

	ren.create_entity_by_mesh_path("assets/floor.glb", &memory.render_queue, &memory.shadow_resources)
}

update_flycam :: proc(delta_time: f32, camera : ^ren.Camera) {
	// Camera movement speed
	move_speed:    Float = 50.0
    rot_speed:     Float = 0.35
    smooth_factor: Float = 40.0

    // Mouse look
    mouse_delta := inp.get_mouse_delta()
    mouse_dx := mouse_delta.x
    mouse_dy := mouse_delta.y

    if inp.is_mouse_locked() {
        camera.target_rotation.y += mouse_dx * rot_speed
        camera.target_rotation.x += mouse_dy * rot_speed
        camera.target_rotation.x = linalg.clamp(camera.target_rotation.x, -89.0, 89.0)
    }

    camera.rotation = linalg.lerp(camera.rotation, camera.target_rotation, delta_time * smooth_factor)

    // for WASD
    pitch_rad := linalg.to_radians(camera.target_rotation.x)
    yaw_rad   := linalg.to_radians(camera.target_rotation.y)

    // forward vector (camera forward) based on yaw (Y) and pitch (X)
    forward: Vec3 = {
         linalg.sin(yaw_rad) * linalg.cos(pitch_rad),
        -linalg.sin(pitch_rad),
         linalg.cos(yaw_rad) * linalg.cos(pitch_rad),
    }

    // right vector (camera right) perpendicular to forward and world up
    right: Vec3 = {
        linalg.cos(yaw_rad),
        0,
        -linalg.sin(yaw_rad),
    }

    up: Vec3 = {0, 1, 0}
    move: Vec3 = {0, 0, 0}

    if inp.GetKey(.W) {
        move += forward
    }
    if inp.GetKey(.S) {
        move -= forward
    }
    if inp.GetKey(.A) {
        move -= right
    }
    if inp.GetKey(.D) {
        move += right
    }
    if inp.GetKey(.Q) {
        move += up
    }
    if inp.GetKey(.E) {
        move -= up
    }

	if inp.GetKey(.ESCAPE) {
		sapp.quit()
	}

	// Normalize the movement vector and apply speed
	// Only move if the length of the vector is greater than a small threshold

	if linalg.length(move) > 0.001 {
        move = linalg.normalize(move)
        camera.position += move * move_speed * delta_time
    }
}

on_awake  :: proc(memory : ^common.Game_Memory) {
	memory.main_camera = ren.Camera {
		fov = 45,
		position = {0, 20, -40},
		rotation = {0, 0, 0},
	}
}

time_counter :f32 = 0

on_update :: proc(delta_time : f32, time : f32, memory : ^common.Game_Memory) {
    update_flycam(delta_time, &memory.main_camera)

    tinker_base_position :[3]f32= {0,5,0}

    if inp.GetKey(.RIGHT){
        time_counter += delta_time
        move_value := linalg.sin(time_counter)
        
        Tinker.transform.rotation.y     += delta_time * 60
        Tinker_Key.transform.rotation.z += delta_time * 300
        forward := trans.get_forward_direction(Tinker.transform)
        Tinker.transform.position = tinker_base_position + forward * (move_value * 5)
    }
}