package gameplay

import "core:math/linalg"
import "core:math/rand"

import sapp  "../lib/sokol/app"
import ren "../engine_core/renderer"
import inp "../engine_core/input"

import "../common"

Mat4  :: matrix[4,4]f32
Vec3  :: [3]f32
Vec2  :: [2]f32
Float :: f32

on_load :: proc(memory: ^common.Game_Memory) {
	// Initialize flappy bird game settings
	memory.saw_speed = 15.0            // Units per second moving backward (Z-)
	memory.saw_spawn_distance = 50.0   // Spawn saws this far forward (Z+)
	memory.saw_destroy_distance = -50.0 // Destroy saws this far backward (Z-)
	memory.next_saw_height = 0.0       // Gap center height (will be randomized)
	memory.gap_size = 12.0             // Gap size between top and bottom obstacles
	memory.obstacle_spacing = 25.0     // Distance between obstacle pairs (tighter spacing)
	memory.next_spawn_z = memory.saw_spawn_distance // Start spawning at spawn distance
	memory.obstacle_count = 0
	
	// Initialize obstacle pairs
	for i in 0..<common.MAX_OBSTACLES {
		memory.obstacle_pairs[i].active = false
	}
	
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
	
	// Pre-load saw assets once (slow but only done once)
	preload_saw_assets(memory)
	
	// Spawn initial obstacles
	spawn_initial_obstacles(memory)
	
	// Set up parent-child relationships
	ren.set_entity_parent(&memory.rendering_resources, memory.modern_tinker_key, memory.modern_tinker)
}

preload_saw_assets :: proc(memory: ^common.Game_Memory) {
	// Load saw arm assets once and extract IDs
	temp_saw_arm := ren.create_entity_from_mesh_file("assets/saw_arm.glb", &memory.rendering_resources, {
		position = {0, 0, 0}, rotation = {0, 0, 0}, scale = {1, 1, 1}, parent = nil, child = nil,
	})
	
	// Load saw blade assets once and extract IDs  
	temp_saw_blade := ren.create_entity_from_mesh_file("assets/saw_blade.glb", &memory.rendering_resources, {
		position = {0, 0, 0}, rotation = {0, 0, 0}, scale = {1, 1, 1}, parent = nil, child = nil,
	})
	
	// Extract mesh/material IDs from temporary entities
	memory.saw_arm_mesh_id = memory.rendering_resources.entities.mesh_id[temp_saw_arm.index]
	memory.saw_arm_material_id = memory.rendering_resources.entities.material_id[temp_saw_arm.index]
	memory.saw_blade_mesh_id = memory.rendering_resources.entities.mesh_id[temp_saw_blade.index]
	memory.saw_blade_material_id = memory.rendering_resources.entities.material_id[temp_saw_blade.index]
	
	// Destroy temporary entities (but keep the loaded resources in pools)
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, temp_saw_arm)
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, temp_saw_blade)
}

spawn_initial_obstacles :: proc(memory: ^common.Game_Memory) {
	// Spawn 3 initial obstacles with proper spacing
	for i in 0..<3 {
		spawn_obstacle_at_z(memory, memory.saw_spawn_distance - f32(i) * memory.obstacle_spacing)
	}
	memory.next_spawn_z = memory.saw_spawn_distance + memory.obstacle_spacing
}

find_free_obstacle_slot :: proc(memory: ^common.Game_Memory) -> int {
	for i in 0..<common.MAX_OBSTACLES {
		if !memory.obstacle_pairs[i].active {
			return i
		}
	}
	return -1 // No free slots
}

spawn_obstacle_at_z :: proc(memory: ^common.Game_Memory, z_position: f32) -> bool {
	slot := find_free_obstacle_slot(memory)
	if slot == -1 do return false
	
	// Randomize gap center height (between -10 and +5 for better range)
	gap_center := -10.0 + rand.float32() * 15.0
	half_gap := memory.gap_size * 0.5
	
	// Calculate positions for top and bottom obstacles
	top_position := gap_center + half_gap + 3.0    // +3 offset for obstacle size
	bottom_position := gap_center - half_gap - 3.0 // -3 offset for obstacle size
	
	pair := &memory.obstacle_pairs[slot]
	
	// Create TOP obstacle stack
	pair.top_arm = ren.create_entity_from_ids(&memory.rendering_resources,
		memory.saw_arm_mesh_id, memory.saw_arm_material_id, {
		position = {0, top_position, z_position},
		rotation = {0, 0, 0}, // Normal orientation
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	pair.top_blade = ren.create_entity_from_ids(&memory.rendering_resources,
		memory.saw_blade_mesh_id, memory.saw_blade_material_id, {
		position = {0, 0, 0}, // Local position (relative to arm)
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	// Create BOTTOM obstacle stack (rotated 180° on X)
	pair.bottom_arm = ren.create_entity_from_ids(&memory.rendering_resources,
		memory.saw_arm_mesh_id, memory.saw_arm_material_id, {
		position = {0, bottom_position, z_position},
		rotation = {180, 0, 0}, // Flipped upside down
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	pair.bottom_blade = ren.create_entity_from_ids(&memory.rendering_resources,
		memory.saw_blade_mesh_id, memory.saw_blade_material_id, {
		position = {0, 0, 0}, // Local position (relative to arm)
		rotation = {0, 0, 0}, 
		scale = {1, 1, 1},
		parent = nil,
		child = nil,
	})
	
	// Set up parent-child relationships (arm -> blade for each stack)
	ren.set_entity_parent(&memory.rendering_resources, pair.top_blade, pair.top_arm)
	ren.set_entity_parent(&memory.rendering_resources, pair.bottom_blade, pair.bottom_arm)
	
	pair.active = true
	memory.obstacle_count += 1
	return true
}

destroy_obstacle_pair :: proc(memory: ^common.Game_Memory, slot: int) {
	if slot < 0 || slot >= common.MAX_OBSTACLES do return
	
	pair := &memory.obstacle_pairs[slot]
	if !pair.active do return
	
	// Destroy all entities in this pair
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, pair.top_arm)
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, pair.top_blade)
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, pair.bottom_arm)
	ren.destroy_entity_ecs(&memory.rendering_resources.entities, pair.bottom_blade)
	
	pair.active = false
	memory.obstacle_count -= 1
}

spawn_new_saw :: proc(memory: ^common.Game_Memory) {
	// Legacy function - now spawns at next spawn position
	if spawn_obstacle_at_z(memory, memory.next_spawn_z) {
		memory.next_spawn_z += memory.obstacle_spacing
	}
}

destroy_current_saw :: proc(memory: ^common.Game_Memory) {
	// Legacy function - now just for compatibility
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

    // Animate tinker (flappy bird player)
    tinker_transform := ren.get_entity_transform(&memory.rendering_resources, memory.modern_tinker)
    if tinker_transform != nil {
        gravity: f32        = -60.0
        jump_force: f32     = +20.0
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
        
        if tinker_transform.position.y < -15.0 {
            tinker_transform.position.y = -15.0
            memory.tinker_velocity = 0 
        }
    }
    
    // Update saw obstacles (flappy bird mechanics with multiple obstacles)
    
    // Move all active obstacle pairs
    for i in 0..<common.MAX_OBSTACLES {
        pair := &memory.obstacle_pairs[i]
        if !pair.active do continue
        
        // Get transforms for this obstacle pair
        top_arm_transform := ren.get_entity_transform(&memory.rendering_resources, pair.top_arm)
        top_blade_transform := ren.get_entity_transform(&memory.rendering_resources, pair.top_blade)
        bottom_arm_transform := ren.get_entity_transform(&memory.rendering_resources, pair.bottom_arm)
        bottom_blade_transform := ren.get_entity_transform(&memory.rendering_resources, pair.bottom_blade)
        
        if top_arm_transform != nil && bottom_arm_transform != nil {
            // Move both obstacle stacks from forward to backward (Z axis)
            movement := memory.saw_speed * delta_time
            top_arm_transform.position.z -= movement
            bottom_arm_transform.position.z -= movement
            
            // Animate saw blade rotation (blades are children, so they inherit arm movement)
            if top_blade_transform != nil {
                top_blade_transform.rotation.x += delta_time * 200
            }
            if bottom_blade_transform != nil {
                bottom_blade_transform.rotation.x += delta_time * 200
            }
            
            // Check if this obstacle has moved off-screen (destroy it)
            if top_arm_transform.position.z < memory.saw_destroy_distance {
                destroy_obstacle_pair(memory, i)
            }
        }
    }
    
    // Check if we need to spawn a new obstacle
    // Find the rightmost (newest) obstacle and check its distance
    rightmost_z := memory.saw_destroy_distance - 100.0 // Default very far left
    for i in 0..<common.MAX_OBSTACLES {
        pair := &memory.obstacle_pairs[i]
        if !pair.active do continue
        
        top_arm_transform := ren.get_entity_transform(&memory.rendering_resources, pair.top_arm)
        if top_arm_transform != nil {
            if top_arm_transform.position.z > rightmost_z {
                rightmost_z = top_arm_transform.position.z
            }
        }
    }
    
    // Spawn new obstacle if the rightmost one has moved far enough
    spawn_threshold := memory.obstacle_spacing * 0.8 // Spawn when 80% of spacing is reached
    if rightmost_z < memory.saw_spawn_distance - spawn_threshold {
        spawn_obstacle_at_z(memory, memory.saw_spawn_distance)
    }
    
    // Animate tinker key
    tinker_key_transform := ren.get_entity_transform(&memory.rendering_resources, memory.modern_tinker_key)
    if tinker_key_transform != nil {
        tinker_key_transform.rotation.z += delta_time * 600
    }
}

