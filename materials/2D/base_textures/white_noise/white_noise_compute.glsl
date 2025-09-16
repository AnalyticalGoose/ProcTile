#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D albedo_buffer;

layout(r16f, set = 1, binding = 0) uniform restrict image2D r16f_buffer;

layout(set = 2, binding = 0, std430) buffer restrict readonly Seeds {
    float white_noise_seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
	float size;

	float tone_value;
	float tone_width;

    float normals_format_unused;
	float texture_size;
	float stage;
} params;

// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
float hash_ws(vec2 x, float seed) {
    vec3 x3 = fract(vec3(x.xyx) * (0.1031 + seed));
    x3 += dot(x3, x3.yzx + 33.33);
    return fract((x3.x + x3.y) * x3.z);
}

float white_noise(vec2 uv, float size, float seed) {
	uv = floor(uv * (size / params.texture_size)) + vec2(0.5);
	return hash_ws(uv, seed);
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
		float white_noise = white_noise(pixel, params.size, seed.white_noise_seed);
		float albedo = clamp((white_noise - params.tone_value) / params.tone_width + 0.5, 0.0, 1.0);
		imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(albedo), 1.0));
    }
}