@header package shader
@header import sg "../lib/sokol/gfx"

//=== shadow pass
@vs vs_shadow
@glsl_options fixup_clipspace // important: map clipspace z from -1..+1 to 0..+1 on GL

layout(binding=0) uniform vs_shadow_params {
    mat4 view_projection;
};

in vec4 pos;

void main() {
    gl_Position = view_projection * pos;
}
@end

@fs fs_shadow
void main() { }
@end

@program shadow vs_shadow fs_shadow