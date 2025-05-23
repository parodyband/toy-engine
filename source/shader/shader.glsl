@header package shader
@header import sg "../lib/sokol/gfx"
@header Mat4 :: matrix[4,4]f32

@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 vp;
    mat4 model;
};

in vec4 pos;
in vec4 normal;
in vec2 texcoord0;

out vec2 uv;
out vec4 world_pos;
out vec3 world_norm;
out vec3 v_normal;

void main() {
    gl_Position = vp * model * pos;
    uv = texcoord0;

    world_pos = model * pos;
    world_norm = normalize((model * vec4(normal.xyz, 0.0)).xyz);
    v_normal = normalize(mat3(model) * normal.xyz);
}
@end

@fs fs
#import "utils.glsl"

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec2 uv;
in vec4 world_pos;
in vec4 world_norm;
in vec3 v_normal;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv);
}
@end

@program texcube vs fs
