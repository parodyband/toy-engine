#+build wasm32, wasm64p32
package gltf2

import web "../sokol_utils"

_read_entire_file :: proc(file_name: string, allocator := context.allocator) -> ([]byte, bool) {
    return web.read_entire_file(file_name, allocator)
} 