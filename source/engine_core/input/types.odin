package input
import sapp "../../lib/sokol/app"

Vec3 :: [3]f32

Input_State :: struct {
    mouse_delta: Vec3,
    keys_down: map[sapp.Keycode]bool,
    keys_just_pressed: map[sapp.Keycode]bool,  // Keys that were pressed this frame
    keys_just_released: map[sapp.Keycode]bool, // Keys that were released this frame
    mouse_buttons_down: map[sapp.Mousebutton]bool,
    mouse_buttons_just_pressed: map[sapp.Mousebutton]bool,  // Mouse buttons that were pressed this frame
    mouse_buttons_just_released: map[sapp.Mousebutton]bool, // Mouse buttons that were released this frame
    mouse_locked: bool,
} 