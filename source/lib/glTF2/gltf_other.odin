#+build darwin, linux, windows
package gltf2

import "core:os"

_read_entire_file :: proc(file_name: string, allocator := context.allocator) -> ([]byte, bool) {
    return os.read_entire_file(file_name, allocator)
} 