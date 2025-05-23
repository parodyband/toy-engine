@header package shader
@header import sg "../lib/sokol/gfx"
@header Mat4 :: matrix[4,4]f32

@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

in vec4 pos;
in vec4 color0;
in vec2 texcoord0;

out vec4 color;
out vec2 uv;

void main() {
    gl_Position = mvp * pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs
#import "utils.glsl"

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    vec4 addColor = add(color, vec4(1.0, 0.0, 0.0, 1.0));
    frag_color = texture(sampler2D(tex, smp), uv) * addColor;
}
@end

@program texcube vs fs
