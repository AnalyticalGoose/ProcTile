#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 1) uniform image2D r16f_buffer_2;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float test_seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float pattern;

    float normals_format;
	float texture_size;
	float stage;
} params;


float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
}


float perlin_2d(vec2 coord, vec2 size, float offset, float seed) {
    vec2 o = floor(coord) + rand2(vec2(seed, 1.0 - seed)) + size;
    vec2 f = fract(coord);

    float a[4];
    a[0] = rand(mod(o, size)) * 6.28318530718 + offset * 6.28318530718;
    a[1] = rand(mod(o + vec2(0.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[2] = rand(mod(o + vec2(1.0, 0.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[3] = rand(mod(o + vec2(1.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;

    vec2 v[4];
    v[0] = vec2(cos(a[0]), sin(a[0]));
    v[1] = vec2(cos(a[1]), sin(a[1]));
    v[2] = vec2(cos(a[2]), sin(a[2]));
    v[3] = vec2(cos(a[3]), sin(a[3]));
    
    float p[4];
    p[0] = dot(v[0], f);
    p[1] = dot(v[1], f - vec2(0.0, 1.0));
    p[2] = dot(v[2], f - vec2(1.0, 0.0));
    p[3] = dot(v[3], f - vec2(1.0, 1.0));
    
    vec2 t =  f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    return 0.5 + mix(mix(p[0], p[2], t.x), mix(p[1], p[3], t.x), t.y);
}


float fbm_perlin_2d(vec2 coord, vec2 size, int iterations, float persistence, float offset, float seed) {
	float normalize_factor = 0.0;
	float value = 0.0;
	float scale = 1.0;
	for (int i = 0; i < iterations; i++) {
		float noise = perlin_2d(coord * size, size, offset, seed);
		value += noise * scale;
		normalize_factor += scale;
		size *= 2.0;
		scale *= persistence;
	}
	return value / normalize_factor;
}


const float warp_perlin_x = 2.0;
const float warp_perlin_y = 11.0;
const float warp_perlin_interations = 10.0;
const float warp_perlin_persistence = 0.3;
const float warp_perlin_offset = 0.0;
const float warp_perlin_seed = 0.0;

const float warp_strength = 0.1;
const float warp_x = 0.0;
const float warp_y = 2.0;

const float grain_perlin_x = 1.0;
const float grain_perlin_y = 32.0;
const float grain_perlin_iterations = 10.0;
const float grain_perlin_persistence = 0.50;
const float grain_perlin_offset = 0.0;
const float grain_perlin_seed = 0.0;

void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        float warp_perlin = fbm_perlin_2d(uv, vec2(warp_perlin_x, warp_perlin_y), int(warp_perlin_interations), warp_perlin_persistence, warp_perlin_offset, warp_perlin_seed);
        vec2 warped_uv = uv - warp_strength * vec2(warp_x * (warp_perlin - 0.5), - warp_y * warp_perlin - 0.5);
        float grain_perlin = fbm_perlin_2d(warped_uv, vec2(grain_perlin_x, grain_perlin_y), int(grain_perlin_iterations), grain_perlin_persistence, grain_perlin_offset, grain_perlin_seed);

        imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(grain_perlin), 1.0));
    }
}