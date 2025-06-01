package renderer

import ass "../asset"
import "core:hash"

store_texture_in_pool :: proc(texture : ass.Texture, resources : ^Rendering_Resources) -> u64 {
    texture_bytes := texture.mip_chain[0].final_pixels
    bytes := texture_bytes[:]
    hash_value := hash.murmur64a(bytes)

    if _, ok := resources.texture_pool[hash_value]; ok {
        return hash_value
    } else {
        resources.texture_pool[hash_value] = texture
        return hash_value
    }
}

get_texture_from_pool :: proc(hash : u64, resources : ^Rendering_Resources) -> ^ass.Texture {
    if value, ok := &resources.texture_pool[hash]; ok {
        assert(ok, "Just tried to get a texture that doesn't exist (yet?)")
        return value
    } else do return nil
}