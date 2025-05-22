@header package main
@header import sg "lib/sokol/gfx"

@ctype mat4 Mat4
@ctype mat3 Mat3

@block util

vec4 encode_depth(float v) {
    vec4 enc = vec4(1.0, 255.0, 65025.0, 16581375.0) * v;
    enc = fract(enc);
    enc -= enc.yzww * vec4(1.0/255.0,1.0/255.0,1.0/255.0,0.0);
    return enc;
}

float decodeDepth(vec4 rgba) {
    return dot(rgba, vec4(1.0, 1.0/255.0, 1.0/65025.0, 1.0/16581375.0));
}

float sample_shadow(texture2D tex, sampler smp, vec2 uv, float compare) {
    float depth = decodeDepth(texture(sampler2D(tex, smp), vec2(uv.x, uv.y)));
    return step(compare, depth);
}

float sample_shadow_pcf(texture2D tex, sampler smp, vec3 uv_depth, vec2 sm_size) {
    float result = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y =- 2; y <= 2; y++) {
            vec2 offset = vec2(x, y) / sm_size;
            result += sample_shadow(tex, smp, uv_depth.xy + offset, uv_depth.z);
        }
    }
    return result / 25.0;
}

@end


//=== shadow pass
@vs vs_shadow

layout(std140, binding=0) uniform vs_shadow_params {
    mat4 mvp;
};

in vec4 pos;
out vec2 proj_zw;

void main() {
    gl_Position = mvp * pos;
    proj_zw = gl_Position.zw;
}
@end

@fs fs_shadow
@include_block util

in vec2 proj_zw;
out vec4 frag_color;

void main() {
    float depth = proj_zw.x / proj_zw.y;
    frag_color = encode_depth(depth);
}
@end

@program shadow vs_shadow fs_shadow


@vs vs
in vec4 position;
in vec4 normal;
in vec2 texcoord0;

layout(std140, binding=0) uniform VSParams {
    mat4 mvp;
    mat4 model;
    mat4 light_mvp;
    vec4 diff_color;
};

out vec3 v_normal;
out vec2 uv;
out vec4 light_proj_pos;
out vec4 world_pos;
out vec3 world_norm;
out vec3 color;

void main() {
    gl_Position = mvp * model * position;
    light_proj_pos = light_mvp * model * position;
    #if !SOKOL_GLSL
        light_proj_pos.y = -light_proj_pos.y;
    #endif
    world_pos = model * position;
    world_norm = normalize((model * vec4(normal.xyz, 0.0)).xyz);
    color = diff_color.xyz;
    v_normal    = normalize(mat3(model) * normal.xyz);
    uv          = texcoord0;
}
@end

@fs fs
@include_block util
in vec3 v_normal;
in vec2 uv;
in vec4 light_proj_pos;
in vec4 world_pos;
in vec3 world_norm;
in vec3 color;

out vec4 frag_color;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler   smp;
layout(binding=1) uniform texture2D shadow_map;
layout(binding=1) uniform sampler   shadow_smp;

layout(std140, binding=2) uniform MainLightParams {
    vec3 light_direction;
    vec4 light_color;
};

layout(std140, binding=1) uniform TintBlock {
    vec4 tint;
};

void main() {
    vec3 ambient_rgb = vec3(0.5, 0.5, 0.6);

    vec3 lightDir_normalized = normalize(light_direction);
    vec3 surface_normal_normalized = normalize(v_normal);

    float diffuse_intensity_factor = max(dot(surface_normal_normalized, lightDir_normalized), 0.0);

    vec3 diffuse_light_contribution = diffuse_intensity_factor * light_color.rgb; // from MainLightParams.light_color

    // Compute shadow factor
    vec2 sm_size = textureSize(sampler2D(shadow_map, shadow_smp), 0);
    vec3 lp = light_proj_pos.xyz / light_proj_pos.w;
    vec3 sm_pos = vec3((lp.xy + 1.0) * 0.5, lp.z);
    float shadow = sample_shadow_pcf(shadow_map, shadow_smp, sm_pos, sm_size);
    diffuse_light_contribution *= shadow;

    vec4 sampled_texture_color = texture(sampler2D(tex, smp), uv);
    
    vec4 current_tint_value = tint; // from TintBlock.tint

    vec3 total_lighting_effect_rgb = ambient_rgb + diffuse_light_contribution;

    vec3 effective_lighting_rgb = min(total_lighting_effect_rgb, vec3(1.0));

    frag_color.rgb = sampled_texture_color.rgb * current_tint_value.rgb * effective_lighting_rgb;
    frag_color.a = sampled_texture_color.a * current_tint_value.a;
}
@end

@program cube vs fs