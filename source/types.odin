package game
import sapp "lib/sokol/app"

Camera :: struct {
    fov : f32,
    position : [3]f32,
    rotation : [3]f32,
}

Input_State :: struct {
    mouse_delta: Vec3,
    keys_down: map[sapp.Keycode]bool,
    mouse_buttons_down: map[sapp.Mousebutton]bool,
    mouse_locked: bool,
}