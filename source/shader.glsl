@header package main
@header import sg "sokol/gfx"

@vs vs
in vec4 position;
in vec4 color0;
in vec2 textcoord0;

out vec4 v_color_0;
out vec2 uv;

void main() {
    gl_Position = position;
    v_color_0   = color0;
    uv          = textcoord0;
}
@end

@fs fs
in vec4 v_color_0;
in vec2 uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler   smp;

layout(binding = 1) uniform Tint {
    vec4 tint;
};

void main(){
    vec4 tex = texture(sampler2D(tex,smp),uv);
    frag_color = tex * v_color_0 * tint;
}
@end

@program quad vs fs