package common

import ren "../engine_core/renderer"
import deb "../engine_core/debug"
import inp "../engine_core/input"
import sgl "../lib/sokol/gl"

// import sg  "../lib/sokol/gfx"

MAX_OBSTACLES :: 5

Obstacle_Pair :: struct {
	active        : bool,
	top_arm       : ren.Entity_Id,
	top_blade     : ren.Entity_Id,
	bottom_arm    : ren.Entity_Id,
	bottom_blade  : ren.Entity_Id,
}

Game_Memory :: struct {
	main_camera         : ren.Camera,
	game_input          : inp.Input_State,
	rendering_resources : ren.Rendering_Resources,
	lights              : [dynamic]ren.Light,
	debug_render_queue  : [dynamic]deb.Debug_Draw_Call,
	debug_pipelines     : [deb.Depth_Test_Mode]sgl.Pipeline,
	toggle_debug        : bool,
	light_view_projection : matrix[4,4]f32,
	game_time           : f32,
	force_reset         : bool,
	
	// Gameplay state (survives hot reload)
	modern_tinker       : ren.Entity_Id,
	modern_tinker_key   : ren.Entity_Id,
	time_counter        : f32,
	tinker_velocity     : f32,
	
	// Flappy bird game state
	saw_speed           : f32,        // Speed saws move backwards (Z axis)
	saw_spawn_distance  : f32,        // How far forward (Z+) to spawn new saws  
	saw_destroy_distance: f32,        // How far backward (Z-) before destroying
	next_saw_height     : f32,        // Y position for next saw
	gap_size            : f32,        // Gap size between top and bottom obstacles
	obstacle_spacing    : f32,        // Distance between obstacle pairs
	next_spawn_z        : f32,        // Z position where we should spawn next obstacle
	
	// Multiple obstacle pairs (like real Flappy Bird)
	obstacle_count      : int,
	obstacle_pairs      : [MAX_OBSTACLES]Obstacle_Pair,
	
	// Pre-loaded asset IDs (for fast spawning without disk I/O)
	saw_arm_mesh_id     : u16,
	saw_arm_material_id : u16,
	saw_blade_mesh_id   : u16,
	saw_blade_material_id : u16,
}