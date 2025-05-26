package common

import ren "../engine_core/renderer"
import deb "../engine_core/debug"
import inp "../engine_core/input"
import sgl "../lib/sokol/gl"

Game_Memory :: struct {
	main_camera         : ren.Camera,
	game_input          : inp.Input_State,
	opaque_render_queue : [dynamic]ren.Draw_Call,
	shadow_render_queue : [dynamic]ren.Draw_Call,
	lights              : [dynamic]ren.Light,
	debug_render_queue  : [dynamic]deb.Debug_Draw_Call,
	debug_pipelines     : [deb.Depth_Test_Mode]sgl.Pipeline,
	toggle_debug        : bool,
}