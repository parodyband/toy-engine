package gltf2

import "core:os"

_read_entire_file :: proc(file_name: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    return os.read_entire_file(file_name, allocator)
} 