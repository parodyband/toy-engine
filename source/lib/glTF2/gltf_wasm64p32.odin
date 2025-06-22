package gltf2

import web "../sokol_utils"

_read_entire_file :: proc(file_name: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    return web.read_entire_file(file_name, allocator)
} 