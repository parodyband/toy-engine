@header package main
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
in vec4 position;
in vec4 normal;
in vec2 texcoord0;

// Use an explicit std140 uniform block to avoid default-uniform collisions
layout(std140, binding=0) uniform VSParams {
    mat4 mvp;   // view-projection matrix
    mat4 model; // per-mesh model matrix
};

out vec3 v_normal;
out vec2 uv;

void main() {
    // First transform vertex position by the model matrix (world transform), then by view-projection
    gl_Position = mvp * model * position;

    // Transform normal by the model matrix only (no translation)
    v_normal    = normalize(mat3(model) * normal.xyz);
    // v_color_0   = color0;
    uv          = texcoord0;
}
@end

@fs fs
in vec3 v_normal; // Input normal from vertex shader
in vec2 uv;

out vec4 frag_color;

layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler   smp;

// Tint colour in a dedicated std140 block, bound at slot 1 (fragment stage)
layout(std140, binding=1) uniform TintBlock {
    vec4 tint;
};

void main(){
    vec3 lightDir = normalize(vec3(0.0, 0.0, -1.0)); // Fixed directional light from top down
    vec3 norm = normalize(v_normal);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * vec3(1.0); // White light

    vec4 texColor = texture(sampler2D(tex,smp),uv); // Still using the texture lookup
    frag_color = vec4(diffuse, 1.0) * texColor + tint; 

}
@end

@program cube vs fs