//==============================================================================
// SHADOW MAPPING UTILITIES
//==============================================================================

// Interleaved gradient noise for per-fragment randomization
float interleaved_gradient_noise(vec2 position) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(position, magic.xy)));
}

// Generate rotation matrix from angle
mat2 rotation_matrix(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

// Vogel disk sampling - generates evenly distributed points in a disk
vec2 vogel_disk_sample(int sample_index, int sample_count, float phi) {
    float golden_angle = 2.4; // approximation of 2π/φ² where φ is golden ratio
    float radius = sqrt(float(sample_index) + 0.5) / sqrt(float(sample_count));
    float theta = float(sample_index) * golden_angle + phi;
    return radius * vec2(cos(theta), sin(theta));
}

// 16-sample kernel (high quality)
// 16-sample kernel (high quality), random circular offsets
const vec2 pcf_kernel_16x16[16] = vec2[](
    vec2(0.98, 0.18),    // random angle, radius ~1.0
    vec2(0.71, 0.67),    // random angle, radius ~0.97
    vec2(0.29, 0.96),    // random angle, radius ~1.0
    vec2(-0.19, 0.81),   // random angle, radius ~0.83
    vec2(-0.62, 0.78),   // random angle, radius ~1.0
    vec2(-0.92, 0.23),   // random angle, radius ~0.95
    vec2(-0.99, -0.10),  // random angle, radius ~1.0
    vec2(-0.73, -0.68),  // random angle, radius ~1.0
    vec2(-0.31, -0.95),  // random angle, radius ~1.0
    vec2(0.18, -0.98),   // random angle, radius ~1.0
    vec2(0.60, -0.80),   // random angle, radius ~1.0
    vec2(0.93, -0.36),   // random angle, radius ~0.99
    vec2(0.54, 0.32),    // random angle, radius ~0.62
    vec2(-0.44, 0.12),   // random angle, radius ~0.46
    vec2(-0.56, -0.41),  // random angle, radius ~0.69
    vec2(0.21, -0.44)    // random angle, radius ~0.48
);

// 8-sample kernel (medium quality)
// 8-sample kernel (medium quality), random circular offsets
const vec2 pcf_kernel_8x8[8] = vec2[](
    vec2(0.92, 0.19),    // random angle, radius ~0.94
    vec2(0.38, 0.92),    // random angle, radius ~1.00
    vec2(-0.36, 0.62),   // random angle, radius ~0.72
    vec2(-0.85, 0.52),   // random angle, radius ~0.99
    vec2(-0.92, -0.19),  // random angle, radius ~0.94
    vec2(-0.21, -0.44),  // random angle, radius ~0.48
    vec2(0.73, -0.68),   // random angle, radius ~1.00
    vec2(0.19, -0.98)    // random angle, radius ~1.00
);

// 4-sample kernel (low quality/performance)
// 4-sample kernel (low quality/performance), random circular offsets
const vec2 pcf_kernel_4x4[4] = vec2[](
    vec2(0.92, 0.19),    // random angle, radius ~1
    vec2(-0.38, 0.60),   // random angle, radius ~0.71
    vec2(-0.73, -0.68),  // random angle, radius ~1
    vec2(0.21, -0.44)    // random angle, radius ~0.48
);

const int PCF_NUM_SAMPLES_16x16 = 16;
const int PCF_NUM_SAMPLES_8X8 = 8;
const int PCF_NUM_SAMPLES_4X4 = 4;
const float PCF_SAMPLE_RADIUS = 0.002;

// Modern PCF with per-fragment randomization using Vogel disk
float calculate_pcf_shadow_vogel(texture2D shadow_texture, sampler shadow_sampler, vec3 light_space_pos, float bias, int sample_count, vec2 frag_coord) {
    float shadow = 0.0;
    
    // Per-fragment random rotation
    float noise = interleaved_gradient_noise(frag_coord);
    float rotation_angle = noise * 6.28318530718; // 2π
    
    for (int i = 0; i < sample_count; i++) {
        vec2 offset = vogel_disk_sample(i, sample_count, rotation_angle) * PCF_SAMPLE_RADIUS;
        vec3 sample_pos = vec3(light_space_pos.xy + offset, light_space_pos.z - bias);
        shadow += texture(sampler2DShadow(shadow_texture, shadow_sampler), sample_pos);
    }
    
    return shadow / float(sample_count);
}

// Improved PCF with per-fragment random rotation
float calculate_pcf_shadow_16x16(texture2D shadow_texture, sampler shadow_sampler, vec3 light_space_pos, float bias, vec2 frag_coord) {
    float shadow = 0.0;
    
    // Per-fragment random rotation
    float noise = interleaved_gradient_noise(frag_coord);
    mat2 rotation = rotation_matrix(noise * 6.28318530718);
    
    for (int i = 0; i < PCF_NUM_SAMPLES_16x16; i++) {
        vec2 offset = rotation * pcf_kernel_16x16[i] * PCF_SAMPLE_RADIUS;
        vec3 sample_pos = vec3(light_space_pos.xy + offset, light_space_pos.z - bias);
        shadow += texture(sampler2DShadow(shadow_texture, shadow_sampler), sample_pos);
    }
    
    return shadow / float(PCF_NUM_SAMPLES_16x16);
}

float calculate_pcf_shadow_8x8(texture2D shadow_texture, sampler shadow_sampler, vec3 light_space_pos, float bias, vec2 frag_coord) {
    float shadow = 0.0;
    
    // Per-fragment random rotation
    float noise = interleaved_gradient_noise(frag_coord);
    mat2 rotation = rotation_matrix(noise * 6.28318530718);
    
    for (int i = 0; i < PCF_NUM_SAMPLES_8X8; i++) {
        vec2 offset = rotation * pcf_kernel_8x8[i] * PCF_SAMPLE_RADIUS;
        vec3 sample_pos = vec3(light_space_pos.xy + offset, light_space_pos.z - bias);
        shadow += texture(sampler2DShadow(shadow_texture, shadow_sampler), sample_pos);
    }
    
    return shadow / float(PCF_NUM_SAMPLES_8X8);
}

float calculate_pcf_shadow_4x4(texture2D shadow_texture, sampler shadow_sampler, vec3 light_space_pos, float bias, vec2 frag_coord) {
    float shadow = 0.0;
    
    // Per-fragment random rotation
    float noise = interleaved_gradient_noise(frag_coord);
    mat2 rotation = rotation_matrix(noise * 6.28318530718);
    
    for (int i = 0; i < PCF_NUM_SAMPLES_4X4; i++) {
        vec2 offset = rotation * pcf_kernel_4x4[i] * PCF_SAMPLE_RADIUS;
        vec3 sample_pos = vec3(light_space_pos.xy + offset, light_space_pos.z - bias);
        shadow += texture(sampler2DShadow(shadow_texture, shadow_sampler), sample_pos);
    }
    
    return shadow / float(PCF_NUM_SAMPLES_4X4);
}

float calculate_shadow_bias(vec3 normal, vec3 light_dir) {
    const float min_bias = 0.0001;
    const float max_bias = 0.001;
    
    float cos_angle = dot(normal, light_dir);
    return max(max_bias * (1.0 - cos_angle), min_bias);
}

float calculate_shadow(
    texture2D shadow_texture,
    sampler shadow_sampler,
    vec4 light_space_pos,
    vec3 normal,
    vec3 light_dir,
    vec2 frag_coord
) {
    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
    vec3 shadow_coords = vec3((proj_coords.xy + 1.0) * 0.5, proj_coords.z);
    
    float bias = calculate_shadow_bias(normal, light_dir);
    
    // Use Vogel disk sampling for best quality
    return calculate_pcf_shadow_vogel(shadow_texture, shadow_sampler, shadow_coords, bias, 15, frag_coord);
    
    // Or use rotated PCF for compatibility
    // return calculate_pcf_shadow_8x8(shadow_texture, shadow_sampler, shadow_coords, bias, frag_coord);
}

vec4 apply_shadow(vec4 lighting, float shadow_factor, float ambient_factor) {
    return lighting * mix(ambient_factor, 1.0, shadow_factor);
} 