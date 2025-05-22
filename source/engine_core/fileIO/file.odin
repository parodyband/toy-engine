package file

import "../../lib/web"
import "core:os"

_ :: os

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

@(require_results)
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
    when IS_WEB {
        return web.read_entire_file(name, allocator, loc)
    } else {
        return os.read_entire_file(name, allocator, loc)
    }
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
    when IS_WEB {
        return web.write_entire_file(name, data, truncate)
    } else {
        return os.write_entire_file(name, data, truncate)
    }
}