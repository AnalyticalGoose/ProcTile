#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D r16f_buffer;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float test_seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float normals_format;
	float texture_size;
	float stage;
} params;


const float sobel_strength = 0.12;



ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

// Generate normals
vec3 sobel_filter(ivec2 coord, float amount) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    // Apply Sobel-like filter to compute gradient
    rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer, wrap_coord(coord + ivec2(e.x, e.y))).r;
    rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer, wrap_coord(coord - ivec2(e.x, e.y))).r;
    rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer, wrap_coord(coord + ivec2(e.x, -e.y))).r;
    rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
    rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer, wrap_coord(coord + ivec2(2, 0))).r;
    rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer, wrap_coord(coord - ivec2(2, 0))).r;
    rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer, wrap_coord(coord + ivec2(0, 2))).r;
    rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer, wrap_coord(coord - ivec2(0, 2))).r;

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        imageStore(albedo_buffer, ivec2(pixel), vec4(1.0, 0.0, 0.0, 1.0));
    }

    if (params.stage == 1.0) {
    
    }
}