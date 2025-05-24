#define MAX_POINT_LIGHTS 16

struct point_light_t {
    vec4 position;
    vec4 color;
    float intensity;
};

vec3 calculate_point_light(point_light_t light, vec3 frag_pos, vec3 normal) {
    vec3 light_pos   = light.position.xyz;
    vec3 light_color = light.color.xyz;
    float intensity  = light.intensity;

    vec3 light_dir = normalize(light_pos - frag_pos);
    float diff = max(dot(normal, light_dir), 0.0);
    return light_color * diff * intensity;
}