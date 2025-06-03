package renderer

import ass   "../asset"
import sg    "../../lib/sokol/gfx"
import trans "../transform"
import       "../../shader"

import "core:hash"

MAX_PIPELINES :: 10000
MAX_MATERIALS :: 5000
MAX_MESHES    :: 2500
MAX_TEXTURES  :: 5000
MAX_ENTITIES  :: 5000

Pipeline_Registry :: struct {
    pipelines : [MAX_PIPELINES]sg.Pipeline,
    count     : int,
}

Material_Registry :: struct {
    materials : [MAX_MATERIALS]ass.Material,
    count     : int,
}

Mesh_Registry :: struct {
    meshes   : [MAX_MESHES]ass.Mesh,
    bindings : [MAX_MESHES]sg.Bindings,        // Opaque/shadow bindings
    outline_bindings : [MAX_MESHES]sg.Bindings, // Outline bindings (with smooth normals)
    count    : int,
}

Texture_Registry :: struct {
    textures : map[u64]ass.Texture,
    images   : map[u64]sg.Image,    // GPU texture objects
    samplers : map[u64]sg.Sampler, // GPU sampler objects
}

Shadow_Pass_Registry :: struct {
    shadow_attachments : sg.Attachments,
	shadow_map         : sg.Image,
	shadow_sampler     : sg.Sampler,
}

Entities_Registry :: struct { 
    alive      : [MAX_ENTITIES]bool,
    generation : [MAX_ENTITIES]u8,
    free_list  : [MAX_ENTITIES]u16,
    free_count : int,

    // Components
    transforms   : [MAX_ENTITIES]trans.Transform,
    mesh_id      : [MAX_ENTITIES]u16,
    material_id  : [MAX_ENTITIES]u16,
    pipeline_id  : [MAX_ENTITIES]u16,
}

// Complete rendering resources
Rendering_Resources :: struct {
    textures  : Texture_Registry,
    meshes    : Mesh_Registry,
    materials : Material_Registry,
    pipelines : Pipeline_Registry,
    entities  : Entities_Registry,
    shadows   : Shadow_Pass_Registry,
}

// Initialize the entire resource system
init_rendering_resources :: proc(resources: ^Rendering_Resources) {
    resources.textures.textures = make(map[u64]ass.Texture)
    resources.textures.images = make(map[u64]sg.Image)
    resources.textures.samplers = make(map[u64]sg.Sampler)
    
    resources.entities.free_count = 0
    for i in 0..<MAX_ENTITIES {
        resources.entities.alive[i] = false
        resources.entities.generation[i] = 0
    }
    
    // Initialize pipelines once
    init_pipelines(&resources.pipelines)
}

// Create and cache pipelines in the registry
init_pipelines :: proc(pipelines: ^Pipeline_Registry) {
    // Shadow pipeline (ID 0)
    pipelines.pipelines[0] = sg.make_pipeline({
        shader = sg.make_shader(shader.shadow_shader_desc(sg.query_backend())),
        layout = {
            attrs = {
                shader.ATTR_shadow_pos = { format = .FLOAT3 },
            },
        },
        colors = {
            0 = {
                pixel_format = .NONE,
            },
        },
        index_type = .UINT16,
        cull_mode = .BACK,
        face_winding = .CW,
        sample_count = 1,
        depth = {
            pixel_format = .DEPTH,
            write_enabled = true,
            compare = .LESS_EQUAL,
            bias = 0.001,
            bias_slope_scale = 1.0,
        },
        label = "shadow-pipeline",
    })
    
    // Opaque pipeline (ID 1)
    pipelines.pipelines[1] = sg.make_pipeline({
        shader = sg.make_shader(shader.texcube_shader_desc(sg.query_backend())),
        layout = {
            attrs = {
                shader.ATTR_texcube_pos       = { format = .FLOAT3 },
                shader.ATTR_texcube_normal    = { format = .FLOAT3, buffer_index = 1 },
                shader.ATTR_texcube_texcoord0 = { format = .FLOAT2, buffer_index = 2 },
            },
        },
        index_type = .UINT16,
        cull_mode = .BACK,
        face_winding = .CW,
        depth = {
            compare = .LESS_EQUAL,
            write_enabled = true,
        },
        label = "opaque-pipeline",
    })
    
    // Outline pipeline (ID 2)
    pipelines.pipelines[2] = sg.make_pipeline({
        shader = sg.make_shader(shader.outline_shader_desc(sg.query_backend())),
        layout = {
            attrs = {
                shader.ATTR_outline_pos    = { format = .FLOAT3 },
                shader.ATTR_outline_normal = { format = .FLOAT3, buffer_index = 1 },
            },
        },
        index_type = .UINT16,
        cull_mode = .FRONT,
        face_winding = .CW,
        depth = {
            compare = .LESS_EQUAL,
            write_enabled = false,
        },
        label = "outline-pipeline",
    })
    
    pipelines.count = 3
}

// Entity management
create_entity :: proc(entities: ^Entities_Registry) -> Entity_Id {
    // Find a free slot
    if entities.free_count > 0 {
        entities.free_count -= 1
        index := entities.free_list[entities.free_count]
        
        entities.alive[index] = true
        entities.generation[index] += 1
        
        return Entity_Id{
            index = u16(index),
            generation = entities.generation[index],
        }
    }
    
    // Find first dead entity
    for i in 0..<MAX_ENTITIES {
        if !entities.alive[i] {
            entities.alive[i] = true
            entities.generation[i] += 1
            
            return Entity_Id{
                index = u16(i),
                generation = entities.generation[i],
            }
        }
    }
    
    panic("Out of entities!")
}

destroy_entity_ecs :: proc(entities: ^Entities_Registry, entity_id: Entity_Id) {
    if is_entity_valid(entities, entity_id) {
        idx := entity_id.index
        entities.alive[idx] = false
        
        // Add to free list
        if entities.free_count < MAX_ENTITIES {
            entities.free_list[entities.free_count] = idx
            entities.free_count += 1
        }
    }
}

is_entity_valid :: proc(entities: ^Entities_Registry, entity_id: Entity_Id) -> bool {
    return entity_id.index < MAX_ENTITIES && 
           entities.alive[entity_id.index] && 
           entities.generation[entity_id.index] == entity_id.generation
}

// Resource pool functions
get_or_create_mesh :: proc(mesh_registry: ^Mesh_Registry, mesh: ass.Mesh) -> u16 {
    // TODO: Could hash mesh data to check for duplicates
    if mesh_registry.count >= MAX_MESHES {
        panic("Out of mesh slots!")
    }
    
    idx := mesh_registry.count
    mesh_registry.meshes[idx] = mesh
    
    // Create GPU resources for opaque/shadow passes
    mesh_registry.bindings[idx].vertex_buffers[0] = sg.make_buffer({
        data = { ptr = raw_data(mesh.vertex_buffer_bytes), 
                size = uint(len(mesh.vertex_buffer_bytes)) },
    })
    
    mesh_registry.bindings[idx].vertex_buffers[1] = sg.make_buffer({
        data = { ptr = raw_data(mesh.normal_buffer_bytes), 
                size = uint(len(mesh.normal_buffer_bytes)) },
    })
    
    mesh_registry.bindings[idx].vertex_buffers[2] = sg.make_buffer({
        data = { ptr = raw_data(mesh.uv_buffer_bytes), 
                size = uint(len(mesh.uv_buffer_bytes)) },
    })
    
    mesh_registry.bindings[idx].index_buffer = sg.make_buffer({
        usage = { index_buffer = true },
        data = { ptr = raw_data(mesh.index_buffer_bytes), 
                size = uint(len(mesh.index_buffer_bytes)) },
    })
    
    // Create outline bindings with smooth normals
    mesh_registry.outline_bindings[idx].vertex_buffers[0] = sg.make_buffer({
        data = { ptr = raw_data(mesh.vertex_buffer_bytes), 
                size = uint(len(mesh.vertex_buffer_bytes)) },
    })
    
    // Calculate and store smooth normals for outline
    smooth_normals := ass.calculate_smooth_normals(mesh)
    mesh_registry.outline_bindings[idx].vertex_buffers[1] = sg.make_buffer({
        data = { ptr = raw_data(smooth_normals), 
                size = uint(len(smooth_normals)) },
    })
    
    mesh_registry.outline_bindings[idx].index_buffer = sg.make_buffer({
        usage = { index_buffer = true },
        data = { ptr = raw_data(mesh.index_buffer_bytes), 
                size = uint(len(mesh.index_buffer_bytes)) },
    })
    
    mesh_registry.count += 1
    return u16(idx)
}

get_or_create_material :: proc(mat_registry: ^Material_Registry, material: ass.Material) -> u16 {
    if mat_registry.count >= MAX_MATERIALS {
        panic("Out of material slots!")
    }
    
    idx := mat_registry.count
    mat_registry.materials[idx] = material
    mat_registry.count += 1
    return u16(idx)
}

store_texture_in_pool :: proc(texture : ass.Texture, resources : ^Texture_Registry) -> u64 {
    texture_bytes := texture.mip_chain[0].final_pixels
    bytes := texture_bytes[:]
    hash_value := hash.murmur64a(bytes)

    if _, ok := resources.textures[hash_value]; ok {
        return hash_value
    } else {
        resources.textures[hash_value] = texture
        return hash_value
    }
}

get_texture_from_pool :: proc(hash : u64, resources : ^Texture_Registry) -> ^ass.Texture {
    if value, ok := &resources.textures[hash]; ok {
        return value
    } else do return nil
}

// Create GPU texture from asset texture
get_or_create_gpu_texture :: proc(texture_hash: u64, resources: ^Texture_Registry) -> sg.Image {
    // Check if GPU texture already exists
    if image, ok := resources.images[texture_hash]; ok {
        return image
    }
    
    // Get the asset texture
    texture := get_texture_from_pool(texture_hash, resources)
    if texture == nil do panic("Texture not found in pool!")
    
    // Create GPU image
    img_desc : sg.Image_Desc
    img_desc.width        = texture.dimensions.width
    img_desc.height       = texture.dimensions.height
    img_desc.pixel_format = .RGBA8
    img_desc.num_mipmaps  = i32(len(texture.mip_chain))

    for mip_idx in 0..<len(texture.mip_chain) {
        mip_pixels := texture.mip_chain[mip_idx].final_pixels
        img_desc.data.subimage[0][mip_idx].ptr  = raw_data(mip_pixels)
        img_desc.data.subimage[0][mip_idx].size = uint(len(mip_pixels))
    }

    image := sg.make_image(img_desc)
    resources.images[texture_hash] = image
    
    return image
}

get_or_create_gpu_sampler :: proc(texture_hash: u64, resources: ^Texture_Registry) -> sg.Sampler {
    // Check if sampler already exists
    if sampler, ok := resources.samplers[texture_hash]; ok {
        return sampler
    }
    
    // Create new sampler (could be configurable per texture later)
    sampler := sg.make_sampler({
        max_anisotropy = 8,
        min_filter     = .LINEAR,
        mag_filter     = .LINEAR,
        mipmap_filter  = .LINEAR,
    })
    
    resources.samplers[texture_hash] = sampler
    return sampler
}