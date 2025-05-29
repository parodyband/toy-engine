package input
import sapp "../../lib/sokol/app"
import fmt "core:fmt"

// Global input state - will be set by the game
input_state: ^Input_State

// Initialize input system with a reference to the input state
init :: proc(state: ^Input_State) {
    input_state = state
}

// Initialize the input state maps
init_input_state :: proc(state: ^Input_State) {
    state.mouse_delta = {0, 0, 0}
    state.keys_down = make(map[sapp.Keycode]bool)
    state.keys_just_pressed = make(map[sapp.Keycode]bool)
    state.keys_just_released = make(map[sapp.Keycode]bool)
    state.mouse_buttons_down = make(map[sapp.Mousebutton]bool)
    state.mouse_locked = false
    init(state)
}

// GetKeyDown returns true only on the frame when the key is first pressed
// Example: if GetKeyDown(.SPACE) { jump() }
get_key_down :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_just_pressed[key] or_else false
}

// GetKeyUp returns true only on the frame when the key is released
// Example: if GetKeyUp(.LEFT_SHIFT) { stop_running() }
get_key_up :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_just_released[key] or_else false
}

// GetKey returns true every frame while the key is held down
// Example: if GetKey(.W) { move_forward() }
GetKey :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_down[key] or_else false
}

// Process key down event
process_key_down :: proc(key_code: sapp.Keycode) {
    if input_state == nil do return
    if !input_state.keys_down[key_code] {
        input_state.keys_just_pressed[key_code] = true
    }
    input_state.keys_down[key_code] = true
}

// Process key up event
process_key_up :: proc(key_code: sapp.Keycode) {
    if input_state == nil do return
    if input_state.keys_down[key_code] {
        input_state.keys_just_released[key_code] = true
    }
    input_state.keys_down[key_code] = false
}

// Process mouse move event
process_mouse_move :: proc(dx, dy: f32) {
    if input_state == nil do return
    input_state.mouse_delta.x += dx
    input_state.mouse_delta.y += dy
}

// Process mouse button down event
process_mouse_button_down :: proc(button: sapp.Mousebutton) {
    if input_state == nil do return
    input_state.mouse_buttons_down[button] = true
}

// Process mouse button up event
process_mouse_button_up :: proc(button: sapp.Mousebutton) {
    if input_state == nil do return
    input_state.mouse_buttons_down[button] = false
}

// Toggle mouse lock state
toggle_mouse_lock :: proc() {
    if input_state == nil do return
    sapp.lock_mouse(!input_state.mouse_locked)
    input_state.mouse_locked = !input_state.mouse_locked
}

// Get mouse delta for this frame (do not reset here; will be cleared at end of frame)
get_mouse_delta :: proc() -> Vec3 {
    if input_state == nil do return {0, 0, 0}
    return input_state.mouse_delta
}

// Get mouse locked state
is_mouse_locked :: proc() -> bool {
    if input_state == nil do return false
    return input_state.mouse_locked
}

// Clear frame-based input states (call at end of frame)
clear_frame_states :: proc() {
    if input_state == nil {
        fmt.println("Input not found")
        return
    }
    clear(&input_state.keys_just_pressed)
    clear(&input_state.keys_just_released)
    input_state.mouse_delta = {0, 0, 0}
} 