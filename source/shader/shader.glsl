@header package shader
@header import sg "../lib/sokol/gfx"
@header Mat4 :: matrix[4,4]f32
@header Vec3 :: [3]f32

@ctype mat4 Mat4
@ctype vec3 Vec3

//==============================================================================
// VERTEX SHADER
//==============================================================================
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
    direct_light_pos = direct_light_mvp * pos;
    
    #if !SOKOL_GLSL
        direct_light_pos.y = -direct_light_pos.y;
    #endif
}
@end

//==============================================================================
// FRAGMENT SHADER
//==============================================================================
@fs fs
#import "utils.glsl"
#import "lights.glsl"
#import "shadows.glsl"

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

in vec2 uv;
in vec4 frag_pos;
in vec3 frag_norm;
in vec3 view_position;
in vec4 direct_light_pos;

out vec4 frag_color;

point_light_t get_point_light(int index) {
    return point_light_t(
        point_lights.position[index].xyz,
        point_lights.color[index].rgb,
        point_lights.range[index].x,
        point_lights.intensity[index].x
    );
}

directional_light_t get_directional_light() {
    return directional_light_t(
        directional_light.position.xyz,
        directional_light.direction.xyz,
        directional_light.color.rgb,
        directional_light.intensity.x
    );
}

void main() {
    vec3 normal   = normalize(frag_norm);
    vec3 view_dir = normalize(view_position - frag_pos.xyz);

    vec4 albedo = gamma_to_linear(texture(sampler2D(tex, smp), uv));
    vec4 lighting = vec4(0.15, 0.15, 0.35, 1.0);

    for(int i = 0; i < MAX_POINT_LIGHTS; i++) {
        vec3 light_contrib = calculate_point_light(get_point_light(i), frag_pos.xyz, normal);
        lighting.rgb += light_contrib;
    }

    vec3 direct_light_contrib = calculate_directional_light(get_directional_light(), normal);
    lighting.rgb += direct_light_contrib;
    
    vec3 light_dir = normalize(directional_light.direction.xyz);
    float shadow_factor = calculate_shadow(
        shadow_tex,
        shadow_smp,
        direct_light_pos,
        normal,
        light_dir,
        gl_FragCoord.xy
    );
    
    lighting = apply_shadow(lighting, shadow_factor, 0.25);
    vec4 final_color = albedo * lighting;
    frag_color = linear_to_gamma(final_color);
}
@end

@program texcube vs fs

//==============================================================================
// SHADOW MAP GENERATION
//==============================================================================
@vs vs_shadow
@glsl_options fixup_clipspace

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
