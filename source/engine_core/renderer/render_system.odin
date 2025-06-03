package renderer

import "../../shader"
import sg     "../../lib/sokol/gfx"
import sglue  "../../lib/sokol/glue"
import        "core:slice"
import ass    "../asset"
import gltf   "../../lib/glTF2"
import trans  "../transform"

// Create entity from mesh file (new data-oriented approach)
create_entity_from_mesh_file :: proc(
    path: string,
    resources: ^Rendering_Resources,
    transform: trans.Transform = {
        position = {0,0,0}, 
        rotation = {0,0,0}, 
        scale = {1,1,1},
        parent = nil,
        child = nil,
    },
) -> Entity_Id {
    // Load asset data
    glb_data := ass.load_glb_data_from_file(path)
    glb_mesh_data := ass.load_mesh_from_glb_data(glb_data)
    glb_texture := ass.load_texture_from_glb_data(glb_data)
    defer gltf.unload(glb_data)
    
    // Create material with texture
    material := ass.Material{
        tint_color = {1.0, 1.0, 1.0, 1.0},
        albedo_texture_hash = store_texture_in_pool(glb_texture, &resources.textures),
    }
    
    return create_entity_from_mesh_and_material(resources, glb_mesh_data, material, transform)
}

// Create entity from mesh and material data
create_entity_from_mesh_and_material :: proc(
    resources: ^Rendering_Resources,
    mesh: ass.Mesh,
    material: ass.Material,
    transform: trans.Transform,
) -> Entity_Id {
    // Get or create resources in pools
    mesh_id := get_or_create_mesh(&resources.meshes, mesh)
    material_id := get_or_create_material(&resources.materials, material)
    pipeline_id := get_default_pipeline_id() // Will implement this
    
    // Create entity
    entity_id := create_entity(&resources.entities)
    idx := entity_id.index
    
    // Set components
    resources.entities.transforms[idx] = transform
    resources.entities.mesh_id[idx] = mesh_id
    resources.entities.material_id[idx] = material_id
    resources.entities.pipeline_id[idx] = pipeline_id
    
    return entity_id
}

// Fast entity creation using pre-loaded mesh/material IDs (no file I/O)
create_entity_from_ids :: proc(
    resources: ^Rendering_Resources,
    mesh_id: u16,
    material_id: u16,
    transform: trans.Transform,
) -> Entity_Id {
    // Create entity directly using existing resource IDs
    entity_id := create_entity(&resources.entities)
    idx := entity_id.index
    
    // Set components (no asset loading, just ID assignment)
    resources.entities.transforms[idx] = transform
    resources.entities.mesh_id[idx] = mesh_id
    resources.entities.material_id[idx] = material_id
    resources.entities.pipeline_id[idx] = get_default_pipeline_id()
    
    return entity_id
}

// Get transform of entity
get_entity_transform :: proc(resources: ^Rendering_Resources, entity_id: Entity_Id) -> ^trans.Transform {
    if !is_entity_valid(&resources.entities, entity_id) do return nil
    return &resources.entities.transforms[entity_id.index]
}

// Set parent-child relationship between entities
set_entity_parent :: proc(resources: ^Rendering_Resources, child_id: Entity_Id, parent_id: Entity_Id) {
    child_transform := get_entity_transform(resources, child_id)
    parent_transform := get_entity_transform(resources, parent_id)
    
    if child_transform != nil && parent_transform != nil {
        child_transform.parent = parent_transform
        parent_transform.child = child_transform // Set bidirectional link
    }
}

// Remove parent relationship (make entity root)
remove_entity_parent :: proc(resources: ^Rendering_Resources, child_id: Entity_Id) {
    child_transform := get_entity_transform(resources, child_id)
    if child_transform != nil {
        if child_transform.parent != nil {
            child_transform.parent.child = nil // Remove parent's child reference
        }
        child_transform.parent = nil
    }
}

// Submit all entities to render queue
submit_entities_for_rendering :: proc(
    resources: ^Rendering_Resources,
    render_queue: ^[dynamic]Draw_Call,
    camera: Camera,
) {
    clear(render_queue)
    
    for i in 0..<MAX_ENTITIES {
        if !resources.entities.alive[i] do continue
        
        entity_id := Entity_Id{index = u16(i), generation = resources.entities.generation[i]}
        
        // Calculate depth for sorting (simple distance from camera)
        transform := resources.entities.transforms[i]
        dx := transform.position.x - camera.position.x
        dy := transform.position.y - camera.position.y
        dz := transform.position.z - camera.position.z
        distance_to_camera := dx*dx + dy*dy + dz*dz // squared distance is fine for sorting
        depth_bits := u16(distance_to_camera * 100) // Convert to fixed point for sorting
        
        // Create opaque draw call
        opaque_key: Render_Key
        opaque_key.pass_type = 1 // opaque pass
        opaque_key.pipeline_id = resources.entities.pipeline_id[i]
        opaque_key.material_id = resources.entities.material_id[i]
        opaque_key.mesh_id = resources.entities.mesh_id[i]
        opaque_key.depth_bits = depth_bits
        
        opaque_draw_call := Draw_Call{
            key = opaque_key,
            entity_id = entity_id,
            mesh_id = resources.entities.mesh_id[i],
            material_id = resources.entities.material_id[i],
            pipeline_id = resources.entities.pipeline_id[i],
            submesh_id = 0,
            index_count = resources.meshes.meshes[opaque_key.mesh_id].index_count,
        }
        
        append(render_queue, opaque_draw_call)
        
        // Create outline draw call
        outline_key: Render_Key
        outline_key.pass_type = 3 // outline pass
        outline_key.pipeline_id = 2 // outline pipeline ID
        outline_key.material_id = resources.entities.material_id[i]
        outline_key.mesh_id = resources.entities.mesh_id[i]
        outline_key.depth_bits = depth_bits
        
        outline_draw_call := Draw_Call{
            key = outline_key,
            entity_id = entity_id,
            mesh_id = resources.entities.mesh_id[i],
            material_id = resources.entities.material_id[i],
            pipeline_id = 2, // outline pipeline
            submesh_id = 0,
            index_count = resources.meshes.meshes[outline_key.mesh_id].index_count,
        }
        
        append(render_queue, outline_draw_call)
    }
    
    // Sort by render key for optimal batching
    // Render key bit layout (most significant to least significant):
    // pass_type -> pipeline_id -> material_id -> mesh_id -> depth_bits
    // This ensures minimal GPU state changes:
    // 1. Groups by render pass (shadow=0, opaque=1, transparent=2, outline=3)
    // 2. Within each pass, groups by pipeline (most expensive state change)
    // 3. Within each pipeline, groups by material (texture binding)
    // 4. Within each material, groups by mesh (vertex buffer binding)
    // 5. Within each mesh, sorts by depth (front-to-back for opaque, back-to-front for alpha)
    slice.sort_by(render_queue[:], proc(a, b: Draw_Call) -> bool {
        return a.key < b.key
    })
}

// Render shadow pass with new system
render_shadow_pass_modern :: proc(
    resources: ^Rendering_Resources,
    draw_calls: []Draw_Call,
    light_view_projection: matrix[4,4]f32,
) {
    sg.begin_pass({
        action = {
            depth = {
                load_action = .CLEAR,
                store_action = .STORE,
                clear_value = 1,
            },
        },
        attachments = resources.shadows.shadow_attachments,
    })
    
    current_pipeline: u16 = 0xFFFF
    current_mesh: u16 = 0xFFFF
    
    for draw_call in draw_calls {
        // Skip non-shadow passes (we could filter this earlier)
        if draw_call.key.pass_type != 0 && draw_call.key.pass_type != 1 do continue
        
        // Batch by pipeline
        if current_pipeline != draw_call.pipeline_id {
            pipeline := get_shadow_pipeline(&resources.pipelines) 
            sg.apply_pipeline(pipeline)
            current_pipeline = draw_call.pipeline_id
            current_mesh = 0xFFFF // Force mesh rebind after pipeline change
        }
        
        // Batch by mesh (shadow pass doesn't use materials/textures)
        if current_mesh != draw_call.mesh_id {
            sg.apply_bindings(resources.meshes.bindings[draw_call.mesh_id])
            current_mesh = draw_call.mesh_id
        }
        
        // Set transform uniforms (always changes per draw call)
        transform := resources.entities.transforms[draw_call.entity_id.index]
        model := trans.compute_model_matrix(transform)
        
        vs_shadow_params := shader.Vs_Shadow_Params{
            view_projection = light_view_projection,
            model = model,
        }
        
        sg.apply_uniforms(shader.UB_vs_shadow_params, {
            ptr = &vs_shadow_params,
            size = size_of(vs_shadow_params),
        })
        
        sg.draw(0, i32(draw_call.index_count), 1)
    }
    
    sg.end_pass()
}

// Render opaque pass with new system
render_opaque_pass_modern :: proc(
    resources: ^Rendering_Resources,
    draw_calls: []Draw_Call,
    camera: Camera,
    light_view_projection: matrix[4,4]f32,
    point_light_params: shader.Fs_Point_Light,
    directional_light_params: shader.Fs_Directional_Light,
) {
    sg.begin_pass({
        action = {
            colors = { 0 = { load_action = .CLEAR, clear_value = {.2,.2,.2,1} } },
        },
        swapchain = sglue.swapchain(),
    })
    
    current_pipeline: u16 = 0xFFFF
    current_material: u16 = 0xFFFF
    current_mesh: u16 = 0xFFFF
    
    for draw_call in draw_calls {
        if draw_call.key.pass_type != 1 do continue // Only opaque
        
        // Batch by pipeline (most expensive state change)
        if current_pipeline != draw_call.pipeline_id {
            pipeline := get_opaque_pipeline(&resources.pipelines)
            sg.apply_pipeline(pipeline)
            current_pipeline = draw_call.pipeline_id
            current_material = 0xFFFF // Force material rebind after pipeline change
            current_mesh = 0xFFFF     // Force mesh rebind after pipeline change
        }
        
        // Batch by material (textures - medium cost state change)
        if current_material != draw_call.material_id {
            //material := resources.materials.materials[draw_call.material_id]
            
            // // Bind texture
            // texture_image := get_or_create_gpu_texture(material.albedo_texture_hash, &resources.textures)
            // texture_sampler := get_or_create_gpu_sampler(material.albedo_texture_hash, &resources.textures)
            
            // We'll bind the mesh in the next step, so just update current_material
            current_material = draw_call.material_id
            current_mesh = 0xFFFF // Force mesh rebind after material change
        }
        
        // Batch by mesh (vertex buffers - cheapest state change)
        if current_mesh != draw_call.mesh_id {
            bindings := resources.meshes.bindings[draw_call.mesh_id]
            
            // Set up textures for this material (only when mesh changes)
            if current_material < MAX_MATERIALS {
                material := resources.materials.materials[current_material]
                texture_image := get_or_create_gpu_texture(material.albedo_texture_hash, &resources.textures)
                texture_sampler := get_or_create_gpu_sampler(material.albedo_texture_hash, &resources.textures)
                
                bindings.images[shader.IMG_tex] = texture_image
                bindings.samplers[shader.SMP_smp] = texture_sampler
                
                // Bind shadow map
                bindings.images[shader.IMG_shadow_tex] = resources.shadows.shadow_map
                bindings.samplers[shader.SMP_shadow_smp] = resources.shadows.shadow_sampler
            }
            
            sg.apply_bindings(bindings)
            current_mesh = draw_call.mesh_id
        }
        
        // Set per-instance uniforms (always changes per draw call)
        transform := resources.entities.transforms[draw_call.entity_id.index]
        model := trans.compute_model_matrix(transform)
        
        vs_params := shader.Vs_Params{
            view_projection = compute_view_projection(camera.position, camera.rotation, camera.fov),
            model = model,
            view_pos = camera.position,
            direct_light_mvp = light_view_projection * model,
        }
        
        // Copy parameters to local variables so we can take their addresses
        point_params := point_light_params
        directional_params := directional_light_params
        
        sg.apply_uniforms(shader.UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })
        sg.apply_uniforms(shader.UB_fs_point_light, { ptr = &point_params, size = size_of(point_params) })
        sg.apply_uniforms(shader.UB_fs_directional_light, { ptr = &directional_params, size = size_of(directional_params) })
        
        sg.draw(0, i32(draw_call.index_count), 1)
    }
    
    sg.end_pass()
}

// Pipeline creation functions
get_default_pipeline_id :: proc() -> u16 { 
    return 1 // Use opaque pipeline for regular entities
}

get_shadow_pipeline :: proc(pipelines: ^Pipeline_Registry) -> sg.Pipeline { 
    return pipelines.pipelines[0] // Shadow pipeline
}

get_opaque_pipeline :: proc(pipelines: ^Pipeline_Registry) -> sg.Pipeline { 
    return pipelines.pipelines[1] // Opaque pipeline
}

get_outline_pipeline :: proc(pipelines: ^Pipeline_Registry) -> sg.Pipeline { 
    return pipelines.pipelines[2] // Outline pipeline
}

// Render outline pass with new system
render_outline_pass_modern :: proc(
    resources: ^Rendering_Resources,
    draw_calls: []Draw_Call,
    camera: Camera,
) {
    sg.begin_pass({
        action = {
            colors = { 0 = { load_action = .DONTCARE, clear_value = {.2,.2,.2,1} } },
            depth = {
                load_action = .LOAD,
                store_action = .DONTCARE,
            },
        },
        swapchain = sglue.swapchain(),
    })
    
    current_pipeline: u16 = 0xFFFF
    current_mesh: u16 = 0xFFFF
    
    for draw_call in draw_calls {
        if draw_call.key.pass_type != 3 do continue // Only outline pass
        
        // Batch by pipeline
        if current_pipeline != draw_call.pipeline_id {
            pipeline := get_outline_pipeline(&resources.pipelines)
            sg.apply_pipeline(pipeline)
            current_pipeline = draw_call.pipeline_id
            current_mesh = 0xFFFF // Force mesh rebind after pipeline change
        }
        
        // Batch by mesh (outline pass doesn't use materials/textures)
        if current_mesh != draw_call.mesh_id {
            sg.apply_bindings(resources.meshes.outline_bindings[draw_call.mesh_id])
            current_mesh = draw_call.mesh_id
        }
        
        // Set per-instance uniforms
        transform := resources.entities.transforms[draw_call.entity_id.index]
        model := trans.compute_model_matrix(transform)
        
        vs_outline_params := shader.Vs_Outline_Params{
            view_projection = compute_view_projection(camera.position, camera.rotation, camera.fov),
            model = model,
            view_pos = camera.position,
            pixel_factor = 0.001,
        }
        
        sg.apply_uniforms(shader.UB_vs_outline_params, {
            ptr = &vs_outline_params,
            size = size_of(vs_outline_params),
        })
        
        sg.draw(0, i32(draw_call.index_count), 1)
    }
    
    sg.end_pass()
} 