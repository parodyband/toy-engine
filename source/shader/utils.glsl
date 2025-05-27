vec4 add(vec4 a, vec4 b) {
    return a + b;
}

vec4 gamma_to_linear(vec4 color) {
    // Proper sRGB to linear conversion
    // For each color channel, if value <= 0.04045, use simple division
    // Otherwise use power function
    vec3 linear_rgb;
    
    // Unroll loop to avoid array indexing issues
    // Red channel
    if (color.r <= 0.04045) {
        linear_rgb.r = color.r / 12.92;
    } else {
        linear_rgb.r = pow(abs(color.r + 0.055) / 1.055, 2.4);
    }
    
    // Green channel
    if (color.g <= 0.04045) {
        linear_rgb.g = color.g / 12.92;
    } else {
        linear_rgb.g = pow(abs(color.g + 0.055) / 1.055, 2.4);
    }
    
    // Blue channel
    if (color.b <= 0.04045) {
        linear_rgb.b = color.b / 12.92;
    } else {
        linear_rgb.b = pow(abs(color.b + 0.055) / 1.055, 2.4);
    }
    
    return vec4(linear_rgb, color.a);
}

vec4 linear_to_gamma(vec4 color) {
    // Proper linear to sRGB conversion
    // For each color channel, if value <= 0.0031308, use simple multiplication
    // Otherwise use power function
    vec3 srgb;
    
    // Unroll loop to avoid array indexing issues
    // Red channel
    if (color.r <= 0.0031308) {
        srgb.r = color.r * 12.92;
    } else {
        srgb.r = 1.055 * pow(abs(color.r), 1.0/2.4) - 0.055;
    }
    
    // Green channel
    if (color.g <= 0.0031308) {
        srgb.g = color.g * 12.92;
    } else {
        srgb.g = 1.055 * pow(abs(color.g), 1.0/2.4) - 0.055;
    }
    
    // Blue channel
    if (color.b <= 0.0031308) {
        srgb.b = color.b * 12.92;
    } else {
        srgb.b = 1.055 * pow(abs(color.b), 1.0/2.4) - 0.055;
    }
    
    return vec4(srgb, color.a);
}

// Simplified versions for performance (less accurate but faster)
vec4 gamma_to_linear_fast(vec4 color) {
    return vec4(pow(abs(color.rgb), vec3(2.2)), color.a);
}

vec4 linear_to_gamma_fast(vec4 color) {
    return vec4(pow(abs(color.rgb), vec3(1.0/2.2)), color.a);
}
