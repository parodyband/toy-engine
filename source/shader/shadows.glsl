//==============================================================================
// SHADOW MAPPING UTILITIES
//==============================================================================

// Circular kernel of evenly distributed offsets for PCF sampling
const vec2 pcf_kernel[16] = vec2[](
    vec2( cos(0.0 * 6.2831853 / 16.0), sin(0.0 * 6.2831853 / 16.0)),
    vec2( cos(1.0 * 6.2831853 / 16.0), sin(1.0 * 6.2831853 / 16.0)),
    vec2( cos(2.0 * 6.2831853 / 16.0), sin(2.0 * 6.2831853 / 16.0)),
    vec2( cos(3.0 * 6.2831853 / 16.0), sin(3.0 * 6.2831853 / 16.0)),
    vec2( cos(4.0 * 6.2831853 / 16.0), sin(4.0 * 6.2831853 / 16.0)),
    vec2( cos(5.0 * 6.2831853 / 16.0), sin(5.0 * 6.2831853 / 16.0)),
    vec2( cos(6.0 * 6.2831853 / 16.0), sin(6.0 * 6.2831853 / 16.0)),
    vec2( cos(7.0 * 6.2831853 / 16.0), sin(7.0 * 6.2831853 / 16.0)),
    vec2( cos(8.0 * 6.2831853 / 16.0), sin(8.0 * 6.2831853 / 16.0)),
    vec2( cos(9.0 * 6.2831853 / 16.0), sin(9.0 * 6.2831853 / 16.0)),
    vec2( cos(10.0 * 6.2831853 / 16.0), sin(10.0 * 6.2831853 / 16.0)),
    vec2( cos(11.0 * 6.2831853 / 16.0), sin(11.0 * 6.2831853 / 16.0)),
    vec2( cos(12.0 * 6.2831853 / 16.0), sin(12.0 * 6.2831853 / 16.0)),
    vec2( cos(13.0 * 6.2831853 / 16.0), sin(13.0 * 6.2831853 / 16.0)),
    vec2( cos(14.0 * 6.2831853 / 16.0), sin(14.0 * 6.2831853 / 16.0)),
    vec2( cos(15.0 * 6.2831853 / 16.0), sin(15.0 * 6.2831853 / 16.0))
);

// PCF configuration
const int PCF_NUM_SAMPLES = 16;
const float PCF_SAMPLE_RADIUS = 0.002;

//------------------------------------------------------------------------------
// Calculate soft shadows using Percentage Closer Filtering (PCF)
//------------------------------------------------------------------------------
float calculate_pcf_shadow(texture2D shadow_texture, sampler shadow_sampler, vec3 light_space_pos, float bias) {
    float shadow = 0.0;
    
    // Sample the shadow map multiple times with offsets
    for (int i = 0; i < PCF_NUM_SAMPLES; i++) {
        vec2 offset = pcf_kernel[i] * PCF_SAMPLE_RADIUS;
        vec3 sample_pos = vec3(light_space_pos.xy + offset, light_space_pos.z - bias);
        shadow += texture(sampler2DShadow(shadow_texture, shadow_sampler), sample_pos);
    }
    
    // Average the samples
    return shadow / float(PCF_NUM_SAMPLES);
}

//------------------------------------------------------------------------------
// Calculate dynamic shadow bias based on surface angle
//------------------------------------------------------------------------------
float calculate_shadow_bias(vec3 normal, vec3 light_dir) {
    // Dynamic bias based on surface angle to light
    // Prevents shadow acne on surfaces at grazing angles
    const float min_bias = 0.0001;
    const float max_bias = 0.001;
    
    float cos_angle = dot(normal, light_dir);
    return max(max_bias * (1.0 - cos_angle), min_bias);
}

//------------------------------------------------------------------------------
// Main shadow calculation function
//------------------------------------------------------------------------------
float calculate_shadow(
    texture2D shadow_texture,
    sampler shadow_sampler,
    vec4 light_space_pos,
    vec3 normal,
    vec3 light_dir
) {
    // Transform from clip space to texture space
    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
    vec3 shadow_coords = vec3((proj_coords.xy + 1.0) * 0.5, proj_coords.z);
    
    // Calculate dynamic bias
    float bias = calculate_shadow_bias(normal, light_dir);
    
    // Calculate soft shadows with PCF
    return calculate_pcf_shadow(shadow_texture, shadow_sampler, shadow_coords, bias);
}

//------------------------------------------------------------------------------
// Apply shadow with ambient term
//------------------------------------------------------------------------------
vec4 apply_shadow(vec4 lighting, float shadow_factor, float ambient_factor) {
    // Mix between ambient and full lighting based on shadow
    return lighting * mix(ambient_factor, 1.0, shadow_factor);
} 