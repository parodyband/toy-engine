package input
import sapp "../../lib/sokol/app"
import fmt "core:fmt"

// Global input state - will be set by the game
input_state: ^Input_State

init :: proc(state: ^Input_State) {
    input_state = state
}

init_input_state :: proc(state: ^Input_State) {
    state.mouse_delta = {0, 0, 0}
    state.keys_down = make(map[sapp.Keycode]bool)
    state.keys_just_pressed = make(map[sapp.Keycode]bool)
    state.keys_just_released = make(map[sapp.Keycode]bool)
    state.mouse_buttons_down = make(map[sapp.Mousebutton]bool)
    state.mouse_buttons_just_pressed = make(map[sapp.Mousebutton]bool)
    state.mouse_buttons_just_released = make(map[sapp.Mousebutton]bool)
    state.mouse_locked = false
    init(state)
}

get_key_down :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_just_pressed[key] or_else false
}

get_key_up :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_just_released[key] or_else false
}

GetKey :: proc(key: sapp.Keycode) -> bool {
    if input_state == nil do return false
    return input_state.keys_down[key] or_else false
}

get_mouse_down :: proc(button: sapp.Mousebutton) -> bool {
    if input_state == nil do return false
    return input_state.mouse_buttons_just_pressed[button] or_else false
}

get_mouse_up :: proc(button: sapp.Mousebutton) -> bool {
    if input_state == nil do return false
    return input_state.mouse_buttons_just_released[button] or_else false
}

GetMouse :: proc(button: sapp.Mousebutton) -> int {
    if input_state == nil do return 0
    return input_state.mouse_buttons_down[button] ? 1 : 0
}

process_key_down :: proc(key_code: sapp.Keycode) {
    if input_state == nil do return
    if !input_state.keys_down[key_code] {
        input_state.keys_just_pressed[key_code] = true
    }
    input_state.keys_down[key_code] = true
}

process_key_up :: proc(key_code: sapp.Keycode) {
    if input_state == nil do return
    if input_state.keys_down[key_code] {
        input_state.keys_just_released[key_code] = true
    }
    input_state.keys_down[key_code] = false
}

process_mouse_move :: proc(dx, dy: f32) {
    if input_state == nil do return
    input_state.mouse_delta.x += dx
    input_state.mouse_delta.y += dy
}

process_mouse_button_down :: proc(button: sapp.Mousebutton) {
    if input_state == nil do return
    if !input_state.mouse_buttons_down[button] {
        input_state.mouse_buttons_just_pressed[button] = true
    }
    input_state.mouse_buttons_down[button] = true
}

process_mouse_button_up :: proc(button: sapp.Mousebutton) {
    if input_state == nil do return
    if input_state.mouse_buttons_down[button] {
        input_state.mouse_buttons_just_released[button] = true
    }
    input_state.mouse_buttons_down[button] = false
}

toggle_mouse_lock :: proc() {
    if input_state == nil do return
    sapp.lock_mouse(!input_state.mouse_locked)
    input_state.mouse_locked = !input_state.mouse_locked
}

get_mouse_delta :: proc() -> Vec3 {
    if input_state == nil do return {0, 0, 0}
    return input_state.mouse_delta
}

is_mouse_locked :: proc() -> bool {
    if input_state == nil do return false
    return input_state.mouse_locked
}

clear_frame_states :: proc() {
    if input_state == nil {
        fmt.println("Input not found")
        return
    }
    clear(&input_state.keys_just_pressed)
    clear(&input_state.keys_just_released)
    clear(&input_state.mouse_buttons_just_pressed)
    clear(&input_state.mouse_buttons_just_released)
    input_state.mouse_delta = {0, 0, 0}
} 