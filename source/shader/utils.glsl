#pragma once

vec4 add(vec4 a, vec4 b) {
    return a + b;
}

vec4 gamma_to_linear(vec4 color) {
    // Proper sRGB to linear conversion
    // For each color channel, if value <= 0.04045, use simple division
    // Otherwise use power function
    vec3 linear_rgb;
    for (int i = 0; i < 3; i++) {
        if (color[i] <= 0.04045) {
            linear_rgb[i] = color[i] / 12.92;
        } else {
            linear_rgb[i] = pow((color[i] + 0.055) / 1.055, 2.4);
        }
    }
    return vec4(linear_rgb, color.a);
}

vec4 linear_to_gamma(vec4 color) {
    // Proper linear to sRGB conversion
    // For each color channel, if value <= 0.0031308, use simple multiplication
    // Otherwise use power function
    vec3 srgb;
    for (int i = 0; i < 3; i++) {
        if (color[i] <= 0.0031308) {
            srgb[i] = color[i] * 12.92;
        } else {
            srgb[i] = 1.055 * pow(color[i], 1.0/2.4) - 0.055;
        }
    }
    return vec4(srgb, color.a);
}

// Simplified versions for performance (less accurate but faster)
vec4 gamma_to_linear_fast(vec4 color) {
    return vec4(pow(color.rgb, vec3(2.2)), color.a);
}

vec4 linear_to_gamma_fast(vec4 color) {
    return vec4(pow(color.rgb, vec3(1.0/2.2)), color.a);
}
