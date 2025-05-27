@header package shader
@header import sg "../lib/sokol/gfx"
@header Mat4 :: matrix[4,4]f32
@header Vec3 :: [3]f32

@ctype mat4 Mat4
@ctype vec3 Vec3

@vs vs
layout(binding=0) uniform vs_params {
    mat4 view_projection;
    mat4 model;
    mat4 direct_light_mvp;
    vec3 view_pos;
};

in vec4 pos;
in vec4 normal;
in vec2 texcoord0;

out vec2 uv;
out vec4 frag_pos;
out vec3 frag_norm;
out vec3 view_position;
out vec4 direct_light_pos;

void main() {
    gl_Position = view_projection * model * pos;
    uv = texcoord0;
    frag_pos = model * pos;
    frag_norm = normalize(mat3(model) * normal.xyz);
    view_position = view_pos;

    //Direct Light
    direct_light_pos = direct_light_mvp * frag_pos;
    #if !SOKOL_GLSL
        direct_light_pos.y = -direct_light_pos.y;
    #endif
}
@end

@fs fs
#import "utils.glsl"
#import "lights.glsl"

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler   smp;

layout(binding=1) uniform texture2D shadow_tex;
layout(binding=1) uniform sampler   shadow_smp;

layout(binding = 2) uniform fs_point_light {
    vec4 position[MAX_POINT_LIGHTS];
    vec4 color[MAX_POINT_LIGHTS];
    vec4 range[MAX_POINT_LIGHTS];
    vec4 intensity[MAX_POINT_LIGHTS];
} point_lights;

layout(binding = 3) uniform fs_directional_light {
    vec4 position;
    vec4 direction;
    vec4 color;
    vec4 intensity;
} directional_light;

point_light_t get_point_light(int index) {
    int i = index;
    return point_light_t(
        point_lights.position[i].xyz,
        point_lights.color[i].rgb,
        point_lights.range[i].x,
        point_lights.intensity[i].x
    );
}

directional_light_t get_directional_light() {
    return directional_light_t (
        directional_light.position.xyz,
        directional_light.direction.xyz,
        directional_light.color.rgb,
        directional_light.intensity.x
    );
}

in vec2 uv;
in vec4 frag_pos;
in vec3 frag_norm;
in vec3 view_position;
in vec4 direct_light_pos;
out vec4 frag_color;

void main() {
    vec3 normal = normalize(frag_norm);
    vec3 view_dir = normalize(view_position - frag_pos.xyz);

    // Sample texture and convert from sRGB to linear space
    vec4 albedo = gamma_to_linear(texture(sampler2D(tex, smp), uv));

    // Ambient lighting (in linear space)
    vec4 lighting = vec4(0.2, 0.2, 0.3, 1.0);

    // Point Lights (calculations in linear space)
    for(int i=0; i < MAX_POINT_LIGHTS; i++) {
        lighting += vec4(calculate_point_light(get_point_light(i), frag_pos.xyz, normal), 1.0);
    }

    // Directional Lights (calculations in linear space)
    lighting += vec4(calculate_directional_light(get_directional_light(), normal), 1.0);
    vec3 light_pos = direct_light_pos.xyz / direct_light_pos.w;
    
    // Apply shadow bias to prevent shadow acne
    float shadow_bias = 0.0001; // You can adjust this value as needed
    vec3 d_smp_pos = vec3((light_pos.xy + 1.0) * 0.5, light_pos.z - shadow_bias);
    
    float d_shadow = texture(sampler2DShadow(shadow_tex, shadow_smp), d_smp_pos);
    lighting *= (d_shadow + 0.25);

    // Apply lighting to albedo (all in linear space)
    vec4 final_color = albedo * lighting;
    
    // Convert from linear to sRGB for display
    frag_color = linear_to_gamma(final_color);
}
@end

@program texcube vs fs


@vs vs_shadow
@glsl_options fixup_clipspace // important: map clipspace z from -1..+1 to 0..+1 on GL

layout(binding=0) uniform vs_shadow_params {
    mat4 view_projection;
    mat4 model;
};

in vec4 pos;

void main() {
    gl_Position = view_projection * model * pos;
}
@end

@fs fs_shadow
void main() { }
@end

@program shadow vs_shadow fs_shadow
