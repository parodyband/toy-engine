@header package shader
@header import sg "../lib/sokol/gfx"
@header Mat4 :: matrix[4,4]f32

@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 view_projection;
    mat4 model;
    vec3 view_pos;
};

in vec4 pos;
in vec4 normal;
in vec2 texcoord0;

out vec2 uv;
out vec4 frag_pos;
out vec3 frag_norm;
out vec3 view_position;

void main() {
    gl_Position = view_projection * model * pos;
    uv = texcoord0;

    frag_pos = model * pos;
    frag_norm = normalize(mat3(model) * normal.xyz);
    view_position = view_pos;
}
@end

@fs fs
#import "utils.glsl"
#import "lights.glsl"

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

layout(binding = 1) uniform fs_spot_light {
    vec4  position[MAX_POINT_LIGHTS];
    vec4  color[MAX_POINT_LIGHTS];
    vec4  intensity[MAX_POINT_LIGHTS];
} spot_lights;

point_light_t get_point_light(int index) {
    int i = index;
    return point_light_t(
        spot_lights.position[i],
        spot_lights.color[i],
        spot_lights.intensity[i].x
    );
}

in vec2 uv;
in vec4 frag_pos;
in vec3 frag_norm;
in vec3 view_position;
out vec4 frag_color;

void main() {
    vec3 normal = normalize(frag_norm);
    vec3 view_dir = normalize(view_position - frag_pos.xyz);

    vec4 lighting = vec4(.1,.1,.2,1);

    for(int i=0; i < MAX_POINT_LIGHTS; i++) {
        lighting += vec4(calculate_point_light(get_point_light(i), frag_pos.xyz, normal),1);
    }

    frag_color = texture(sampler2D(tex, smp), uv) * lighting;
}
@end

@program texcube vs fs
