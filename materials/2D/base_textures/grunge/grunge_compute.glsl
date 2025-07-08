#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float perlin_seed_1;
    float perlin_seed_2;
    float perlin_seed_3;
    float perlin_seed_4;
    float perlin_seed_5;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float size_x;
    float size_y;
    float iterations;
    float persistence;
    float offset;
    float mingle_opacity;
    float mingle_step;
    float mingle_warp_x;
    float mingle_warp_y;
    float mingle_warp_strength;
    float mingle_smooth;
    float tone_value;
    float tone_width;

    float normals_format_unused;
	float texture_size;
	float stage;
} params;


// S0 - Grunge Texture Parameters
// const vec2 size = vec2(6.0, 6.0);
// const int grunge_iterations = 10;
// const float persistence = 0.61;
// const float offset = 0.00;
// const float mingle_opacity = 1.0;
// const float mingle_step = 0.5;
// const float mingle_warp_x = 0.5;
// const float mingle_warp_y = 0.5;

// const float mingle_warp_strength = 1.5; // todo
// const float mingle_smooth = 0.5;
// const float tone_value = 0.8;
// const float tone_width = 0.4;


// Random / noise functions
float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}


vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
}


// Blending functions
float overlay(float base, float blend) {
	return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
}

float overlay(float base, float blend, float opacity) {
	return opacity * overlay(base, blend) + (1.0 - opacity) * blend;
}

float burn(float base, float blend) {
	return (blend == 0.0) ? blend : max((1.0 - ((1.0 - base) / blend)), 0.0);
}

float burn(float base, float blend, float opacity) {
	return opacity * burn(base, blend) + (1.0 - opacity) * blend;
}

float dodge(float base, float blend) {
	return (blend == 1.0) ? blend : min(base / (1.0 - blend), 1.0);
}

float dodge(float base, float blend, float opacity) {
    return opacity * dodge(base, blend) + (1.0 - opacity) * blend;
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


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        const vec2 _size = vec2(params.size_x, params.size_y);
        const int _iterations = int(params.iterations);

		float fbm_1 = fbm_perlin_2d((uv), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_1);
		float fbm_2 = fbm_perlin_2d((uv), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_2);
		float fbm_3 = fbm_perlin_2d((uv), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_3);

        vec2 warp_1 = (uv) + params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_1 - 0.5), - params.mingle_warp_y * (fbm_2) - 0.5);
		vec2 warp_2 = (uv) - params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_2 - 0.5), - params.mingle_warp_y * (fbm_1) - 0.5);

        float fbm_1_warp_1 = fbm_perlin_2d((warp_1), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_1);
		float fbm_2_warp_1 = fbm_perlin_2d((warp_1), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_2);
		float fbm_3_warp_1 = fbm_perlin_2d((warp_1), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_3);
		
		float fbm_1_warp_2 = fbm_perlin_2d((warp_2), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_1);
		float fbm_2_warp_2 = fbm_perlin_2d((warp_2), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_2);
		float fbm_3_warp_2 = fbm_perlin_2d((warp_2), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_3);

        // Warp and burn blend operation (darker grunge layer), mixed and controlled by a step.
		vec2 blend_burn_warp_1 = (warp_2) + params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_1_warp_2 - 0.5), - params.mingle_warp_y * (fbm_2_warp_2 - 0.5));
		vec2 blend_burn_warp_2 = (warp_2) - params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_2_warp_2 - 0.5), - params.mingle_warp_y * (fbm_1_warp_2 - 0.5));
		float mingle_burn_opacity_adjust = params.mingle_opacity * smoothstep(params.mingle_step - params.mingle_smooth, params.mingle_step + params.mingle_smooth, fbm_3_warp_2);

        // Warp and dodge blend operation (lighter grunge layer), mixed and controlled by a step.
		vec2 mingle_dodge_warp_1 = (warp_1) + params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_1_warp_1 - 0.5), - params.mingle_warp_y * (fbm_2_warp_1 - 0.5));
		vec2 mingle_dodge_warp_2 = (warp_1) - params.mingle_warp_strength * vec2(params.mingle_warp_x * (fbm_2_warp_1 - 0.5), - params.mingle_warp_y * (fbm_1_warp_1 - 0.5));
		float mingle_dodge_opacity_adjust = params.mingle_opacity * smoothstep(params.mingle_step - params.mingle_smooth, params.mingle_step + params.mingle_smooth, fbm_3_warp_1);

        // Combine burn and dodge layers, with an additional warp and blend (overlay) operation, controlled by a step
		float mingle_overlay_burn_input_1 = fbm_perlin_2d((mingle_dodge_warp_1), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_4);
		float mingle_overlay_burn_input_2 = fbm_perlin_2d((mingle_dodge_warp_2), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_5);
		float mingle_overlay_dodge_input_1 = fbm_perlin_2d((blend_burn_warp_1), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_5);
		float mingle_overlay_dodge_input_2 = fbm_perlin_2d((blend_burn_warp_2), _size, _iterations, params.persistence, params.offset, seed.perlin_seed_4);
		float mingle_overlay_burn = burn(mingle_overlay_burn_input_1, mingle_overlay_burn_input_2, mingle_dodge_opacity_adjust);
    	float mingle_overlay_dodge = dodge(mingle_overlay_dodge_input_1, mingle_overlay_dodge_input_2, mingle_burn_opacity_adjust);
		float mingle_overlay_opacity_adjust_1 = params.mingle_opacity * smoothstep(params.mingle_step - params.mingle_smooth, params.mingle_step + params.mingle_smooth, fbm_3);
		float mingle_overlay_output_1 = overlay(mingle_overlay_burn, mingle_overlay_dodge, mingle_overlay_opacity_adjust_1);

        float grunge_texture = clamp((mingle_overlay_output_1 - params.tone_value) / params.tone_width + 0.5, 0.0, 1.0);
        imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(grunge_texture), 1.0));
    }
}