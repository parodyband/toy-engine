#define MAX_POINT_LIGHTS 8

struct point_light_t {
    vec3 position;
    vec3 color;
    float range;
    float intensity;
};

struct directional_light_t {
    vec3 position;
    vec3 direction;
    vec3 color;
    float intensity;
};

vec3 calculate_point_light(point_light_t light, vec3 frag_pos, vec3 normal, vec3 view_dir) {
    vec3 light_pos   = light.position;
    vec3 light_color = light.color;
    float intensity  = light.intensity;
    float range      = light.range;

    vec3 light_dir = normalize(light_pos - frag_pos);
    float distance = length(light_pos - frag_pos);
    
    // Calculate attenuation based on range
    float attenuation = 1.0 - clamp(distance / range, 0.0, 1.0);
    attenuation = attenuation * attenuation; // Quadratic falloff for more realistic lighting
    
    // Diffuse lighting
    float diff = max(dot(normal, light_dir), 0.0);
    
    // Specular lighting (Blinn-Phong)
    vec3 halfway_dir = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway_dir), 0.0), 64.0); // 32 is shininess
    
    vec3 diffuse = light_color * diff * intensity * attenuation;
    vec3 specular = light_color * spec * intensity * attenuation * 2; // 0.5 to tone down specular
    
    return diffuse + specular;
}

vec3 calculate_directional_light(directional_light_t light, vec3 normal, vec3 view_dir) {
    vec3 light_dir = normalize(-light.direction);
    
    // Diffuse lighting
    float diff = max(dot(normal, light_dir), 0.0);
    
    // Specular lighting (Blinn-Phong)
    vec3 halfway_dir = normalize(light_dir + view_dir);
    float spec = pow(max(dot(normal, halfway_dir), 0.0), 64.0); // 32 is shininess
    
    vec3 diffuse = light.color * diff * light.intensity;
    vec3 specular = light.color * spec * light.intensity * 2; // 0.5 to tone down specular
    
    return diffuse + specular;
}