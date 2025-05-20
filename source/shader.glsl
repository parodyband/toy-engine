@header package main
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
in vec4 position;
in vec4 normal;
in vec2 texcoord0;

layout(std140, binding=0) uniform VSParams {
    mat4 mvp;
    mat4 model;
};

out vec3 v_normal;
out vec2 uv;

void main() {
    gl_Position = mvp * model * position;

    // Transform normal by the model matrix only (no translation)
    v_normal    = normalize(mat3(model) * normal.xyz);
    uv          = texcoord0;
}
@end

@fs fs
in vec3 v_normal; 
in vec2 uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler   smp;

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

    vec4 sampled_texture_color = texture(sampler2D(tex, smp), uv);
    
    vec4 current_tint_value = tint; // from TintBlock.tint

    vec3 total_lighting_effect_rgb = ambient_rgb + diffuse_light_contribution;

    vec3 effective_lighting_rgb = min(total_lighting_effect_rgb, vec3(1.0));

    frag_color.rgb = sampled_texture_color.rgb * current_tint_value.rgb * effective_lighting_rgb;
    frag_color.a = sampled_texture_color.a * current_tint_value.a;
}
@end

@program cube vs fs