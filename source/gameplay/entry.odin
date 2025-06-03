package gameplay

import "core:math/linalg"

import sapp  "../lib/sokol/app"
import ren "../engine_core/renderer"
import inp "../engine_core/input"

import "../common"

Mat4  :: matrix[4,4]f32
Vec3  :: [3]f32
Vec2  :: [2]f32
Float :: f32

on_load :: proc(memory: ^common.Game_Memory) {
	// Create entities using the new data-oriented system
	memory.modern_tinker = ren.create_entity_from_mesh_file("assets/Tinker.glb", &memory.rendering_resources, {
		position = {0, 0, 0},
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	memory.modern_tinker_key = ren.create_entity_from_mesh_file("assets/Tinker_Key.glb", &memory.rendering_resources, {
		position = {0, 0, 0},
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	memory.modern_saw_arm = ren.create_entity_from_mesh_file("assets/saw_arm.glb", &memory.rendering_resources, {
		position = {0, 0, 10},
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	memory.modern_saw_blade = ren.create_entity_from_mesh_file("assets/saw_blade.glb", &memory.rendering_resources, {
		position = {0, 0, 10},
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	// Set up parent-child relationships
	ren.set_entity_parent(&memory.rendering_resources, memory.modern_tinker_key, memory.modern_tinker)
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
	if linalg.length(move) > 0.001 {
        move = linalg.normalize(move)
        camera.position += move * move_speed * delta_time
    }
}

on_awake  :: proc(memory : ^common.Game_Memory) {
	memory.main_camera = ren.Camera {
		fov = 45,
		position = {40, 0, 20},
		rotation = {0, 250, 0},
	}
}

on_update :: proc(delta_time : f32, time : f32, memory : ^common.Game_Memory) {
    // update_flycam(delta_time, &memory.main_camera)
    if inp.GetKey(.ESCAPE) do sapp.quit()

    // Animate entities using the new ECS system
    tinker_transform := ren.get_entity_transform(&memory.rendering_resources, memory.modern_tinker)
    if tinker_transform != nil {
        gravity: f32        = -60.0
        jump_force: f32     = +25.0
        max_fall_speed: f32 = -60.0
        max_jump_speed: f32 = +25.0
        
        memory.tinker_velocity += gravity * delta_time
        
        if inp.get_mouse_down(.LEFT) {        
            memory.tinker_velocity = jump_force
        }
        
        memory.tinker_velocity = linalg.clamp(memory.tinker_velocity, max_fall_speed, max_jump_speed)
        
        tinker_transform.position.y += memory.tinker_velocity * delta_time
        target_rotation_x := linalg.clamp(memory.tinker_velocity * 3.0, -30.0, 30.0)
        
        rotation_smooth_speed: f32 = 12.0
        tinker_transform.rotation.x = linalg.lerp(tinker_transform.rotation.x, target_rotation_x, delta_time * rotation_smooth_speed)
        
        if tinker_transform.position.y < -5.0 {
            tinker_transform.position.y = -5.0
            memory.tinker_velocity = 0 
        }
    }
    
    // Animate other entities
    saw_blade_transform := ren.get_entity_transform(&memory.rendering_resources, memory.modern_saw_blade)
    if saw_blade_transform != nil {
        saw_blade_transform.rotation.x += delta_time * 200
    }
    
    tinker_key_transform := ren.get_entity_transform(&memory.rendering_resources, memory.modern_tinker_key)
    if tinker_key_transform != nil {
        tinker_key_transform.rotation.z += delta_time * 600
    }
}

