package common

import ren "../engine_core/renderer"
import deb "../engine_core/debug"
import inp "../engine_core/input"
import sgl "../lib/sokol/gl"

// import sg  "../lib/sokol/gfx"

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
	modern_saw_arm      : ren.Entity_Id,
	modern_saw_blade    : ren.Entity_Id,
	time_counter        : f32,
	tinker_velocity     : f32,
}