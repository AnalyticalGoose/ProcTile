#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D rgba32f_buffer;
layout(r16f, set = 1, binding = 1) uniform image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 2) uniform image2D r16f_buffer_2;
layout(r16f, set = 1, binding = 3) uniform image2D r16f_buffer_3;
layout(r16f, set = 1, binding = 4) uniform image2D noise_buffer;
layout(r16f, set = 1, binding = 5) uniform image2D grunge_buffer;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float brick_colour_seed;
	float perlin_seed_1;
	float perlin_seed_2;
	float perlin_seed_3;
	float perlin_seed_4;
	float perlin_seed_5;
	float perlin_seed_6;
	float b_noise_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly GradientColours {
    vec4 gradient_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly MortarColour {
	vec4 mortar_col;
};

layout(push_constant, std430) uniform restrict readonly Params {
	float pattern;
	float rows;
	float columns;
	float row_offset;
	float mortar;
	float bevel;
	float rounding;
	float repeat;
	float mingle_warp_strength; // Density
	float tone_value; // Displacement Level
	float mingle_smooth; // Plateau Scale
	float tone_width; // Blending
	float blue_noise_tone_width; // Intensity
	float damage_scale_x; // Scale
	float damage_scale_y;
	float damage_iterations; // Complexity
	float damage_persistence; // Intensity
    float blue_noise_brightness; // Mortar Height
    float macro_uniformity;
    float micro_uniformity;
    float normals_format;
	float texture_size;
	float stage;
} params;


// S0 - Grunge Texture Parameters
const int grunge_iterations = 10;
const float persistence = 0.61;
const float offset = 0.00;
const float mingle_opacity = 1.0;
const float mingle_step = 0.5;
const float mingle_warp_x = 0.5;
const float mingle_warp_y = 0.5;

// S1
const float grunge_blend_opacity = 0.80;
const float damage_offset = 0.00;

// S2
const float slope_blur_brightness = 0.25;
const float slope_blur_contrast = 0.50;
const float blue_noise_tone_value = 0.00;
// const float blue_noise_tone_width = 0.22;
// const float blue_noise_brightness = -0.50;
const float blue_noise_contrast = 0.61;
const float roughness_in_min = 0.00;
const float roughness_in_max = 0.15;
const float roughness_out_min = 0.70;
const float roughness_out_max = 0.90;
const float ao_in_min = 0.00;
const float ao_in_max = 1.00;
const float ao_out_min = 0.75;
const float ao_out_max = 1.00;

const float sobel_strength = 0.12;


// Random / noise functions
float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}


vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
}

vec3 rand3(vec2 x) {
    return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
							  dot(x, vec2(3.4562, 17.398)),
                              dot(x, vec2(13.254, 5.867))), vec3(3.14, 3.14, 3.14))) * 43758.5);
}


// Blending functions
float overlay_f(float base, float blend) {
	return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
}

float overlay(float base, float blend, float opacity) {
	return opacity * overlay_f(base, blend) + (1.0 - opacity) * blend;
}

float burn_f(float base, float blend) {
	return (blend == 0.0) ? blend : max((1.0 - ((1.0 - base) / blend)), 0.0);
}

float burn(float base, float blend, float opacity) {
	return opacity * burn_f(base, blend) + (1.0 - opacity) * blend;
}

float dodge_f(float base, float blend) {
	return (blend == 1.0) ? blend : min(base / (1.0 - blend), 1.0);
}

float dodge(float base, float blend, float opacity) {
    return opacity * dodge_f(base, blend) + (1.0 - opacity) * blend;
}

float multiply(float base, float blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}


// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
float hash_ws(vec2 x, float seed) {
    vec3 x3 = fract(vec3(x.xyx) * (0.1031 + seed));
    x3 += dot(x3, x3.yzx + 33.33);
    return fract((x3.x + x3.y) * x3.z);
}

vec4 get_brick_bounds(vec2 uv, vec2 grid, float repeat, float row_offset, int pattern) {
    vec2 adjusted_grid = grid * repeat;
    float x_offset = row_offset * step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
    vec2 brick_min, brick_max;

    if (pattern == 0 || pattern == 1 || pattern == 2) { // Running, English, Flemish
        if (pattern == 1) {
            adjusted_grid.x *= 1.0 + step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
        }
        brick_min = floor(vec2(uv.x * adjusted_grid.x - x_offset, uv.y * adjusted_grid.y));
        brick_min.x += x_offset;
        brick_min /= adjusted_grid;

        if (pattern == 2) { // Flemish
            brick_max = brick_min + vec2(1.0) / adjusted_grid;
            float split = (brick_max.x - brick_min.x) / 3.0;
            float is_left = step((uv.x - brick_min.x) / (brick_max.x - brick_min.x), 1.0 / 3.0);
            brick_max.x = mix(brick_max.x, brick_min.x + split, is_left);
            brick_min.x = mix(brick_min.x + split, brick_min.x, is_left);
        } else {
            brick_max = brick_min + vec2(1.0) / adjusted_grid;
        }
        return vec4(brick_min, brick_max);
    }

    if (pattern == 3) { // Herringbone
        float pattern_count = adjusted_grid.x + adjusted_grid.y;
        float cell_count = pattern_count * repeat;
        vec2 cell_coord = floor(uv * cell_count);
        float diagonal_offset = mod(cell_coord.x - cell_coord.y, pattern_count);

        vec2 base_corner = cell_coord - vec2(diagonal_offset, 0.0);
        vec2 alt_corner = cell_coord - vec2(0.0, pattern_count - diagonal_offset - 1.0);
        float use_alt_corner = step(adjusted_grid.x, diagonal_offset);
        vec2 corner = mix(base_corner, alt_corner, use_alt_corner);
        vec2 size = mix(vec2(adjusted_grid.x, 1.0), vec2(1.0, adjusted_grid.y), use_alt_corner);

        return vec4(corner / cell_count, (corner + size) / cell_count);
    }

    if (pattern == 4) { // Basketweave
        vec2 cell_count = 2.0 * adjusted_grid;
        vec2 primary_corner = floor(uv * cell_count);
        vec2 secondary_corner = grid * floor(uv * 2.0 * repeat);

        float toggle = mod(dot(floor(uv * 2.0 * repeat), vec2(1.0)), 2.0);
        vec2 corner = mix(vec2(primary_corner.x, secondary_corner.y), vec2(secondary_corner.x, primary_corner.y), toggle);
        vec2 size = mix(vec2(1.0, adjusted_grid.y), vec2(adjusted_grid.x, 1.0), toggle);

        return vec4(corner / cell_count, (corner + size) / cell_count);
    }
}

float get_brick_pattern(vec2 uv, vec2 brick_min, vec2 brick_max, float mortar, float rounding, float bevel, float brick_scale) {
    mortar *= brick_scale;
    rounding *= brick_scale;
    bevel *= brick_scale;
    vec2 brick_size = brick_max - brick_min;
    vec2 brick_center = 0.5 * (brick_min + brick_max);
    vec2 edge_dist = abs(uv - brick_center) - 0.5 * brick_size + vec2(rounding + mortar);
    float distance = length(max(edge_dist, vec2(0))) + min(max(edge_dist.x, edge_dist.y), 0.0) - rounding;
    return clamp(-distance / bevel, 0.0, 1.0);
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


vec4 gradient_fct(float x) {
    int count = int(gradient_col.length()); // Use the number of offsets dynamically
    if (x < gradient_offsets[0]) {
        return gradient_col[0];
    }
    for (int i = 1; i < count; i++) {
        if (x < gradient_offsets[i]) {
            float range = gradient_offsets[i] - gradient_offsets[i - 1];
            float factor = (x - gradient_offsets[i - 1]) / range;
            return mix(gradient_col[i - 1], gradient_col[i], factor);
        }
    }
    return gradient_col[count - 1];
}

ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

float slope_blur(vec2 uv) {
    // Scale UV to texture size & fetch buffer
    const ivec2 pixel_coords = ivec2(uv * params.texture_size);
    const float v = imageLoad(noise_buffer, pixel_coords).r;

    // Compute slope using precomputed heightmap
    const float dx = 1.0 / params.texture_size;
    const vec2 slope = vec2(
        imageLoad(noise_buffer, wrap_coord(pixel_coords + ivec2(1, 0))).r - v,
        imageLoad(noise_buffer, wrap_coord(pixel_coords + ivec2(0, 1))).r - v
    );

    // Normalize slope & setup blur loop
    const float  slope_len   = length(slope) + 1e-6;
    vec2   norm_slope  = slope / slope_len;
    norm_slope         = mix(norm_slope, vec2(0,1), step(slope_len, 1e-6));
    const float  slope_str   = slope_len * params.texture_size;
    const float  sigma       = max(2.0 * slope_str, 1e-4);
    const float  inv_sigma   = 1.0 / (sigma * sigma);
    const float  norm_factor  = 1.0 / (6.28318530718 * sigma * sigma);

    float  rv = 0.0;
    float  sum = 0.0;

    for (int i = 0; i <= 50; ++i) {
        // Fetch mask at offset UV
        float fi = float(i);
        float coef = norm_factor * exp(-0.5 * fi * fi * inv_sigma);
        ivec2 pixel = wrap_coord(pixel_coords + ivec2(norm_slope * fi));
        float mask_value = imageLoad(r16f_buffer_1, pixel).r;

        // Accumulate weighted mask
        rv += mask_value * coef;
        sum += coef;
    }

    // Normalize result
    return rv / sum;
}

// Generate normals
vec3 sobel_filter(ivec2 coord, float amount) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    // Apply Sobel-like filter to compute gradient
    rv += vec2(1.0, -1.0) * imageLoad(rgba32f_buffer, wrap_coord(coord + ivec2(e.x, e.y))).r;
    rv += vec2(-1.0, 1.0) * imageLoad(rgba32f_buffer, wrap_coord(coord - ivec2(e.x, e.y))).r;
    rv += vec2(1.0, 1.0) * imageLoad(rgba32f_buffer, wrap_coord(coord + ivec2(e.x, -e.y))).r;
    rv += vec2(-1.0, -1.0) * imageLoad(rgba32f_buffer, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
    rv += vec2(2.0, 0.0) * imageLoad(rgba32f_buffer, wrap_coord(coord + ivec2(2, 0))).r;
    rv += vec2(-2.0, 0.0) * imageLoad(rgba32f_buffer, wrap_coord(coord - ivec2(2, 0))).r;
    rv += vec2(0.0, 2.0) * imageLoad(rgba32f_buffer, wrap_coord(coord + ivec2(0, 2))).r;
    rv += vec2(0.0, -2.0) * imageLoad(rgba32f_buffer, wrap_coord(coord - ivec2(0, 2))).r;

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) { // grunge layer
        vec2 _size = vec2(6.0, 6.0);

		float fbm_1 = fbm_perlin_2d((uv), _size, grunge_iterations, persistence, offset, seed.perlin_seed_1);
		float fbm_2 = fbm_perlin_2d((uv), _size, grunge_iterations, persistence, offset, seed.perlin_seed_2);
		float fbm_3 = fbm_perlin_2d((uv), _size, grunge_iterations, persistence, offset, seed.perlin_seed_3);

		vec2 warp_1 = (uv) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1 - 0.5), - mingle_warp_y * (fbm_2) - 0.5);
		vec2 warp_2 = (uv) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2 - 0.5), - mingle_warp_y * (fbm_1) - 0.5);

		float fbm_1_warp_1 = fbm_perlin_2d((warp_1), _size, grunge_iterations, persistence, offset, seed.perlin_seed_1);
		float fbm_2_warp_1 = fbm_perlin_2d((warp_1), _size, grunge_iterations, persistence, offset, seed.perlin_seed_2);
		float fbm_3_warp_1 = fbm_perlin_2d((warp_1), _size, grunge_iterations, persistence, offset, seed.perlin_seed_3);
		
		float fbm_1_warp_2 = fbm_perlin_2d((warp_2), _size, grunge_iterations, persistence, offset, seed.perlin_seed_1);
		float fbm_2_warp_2 = fbm_perlin_2d((warp_2), _size, grunge_iterations, persistence, offset, seed.perlin_seed_2);
		float fbm_3_warp_2 = fbm_perlin_2d((warp_2), _size, grunge_iterations, persistence, offset, seed.perlin_seed_3);

		// Warp and burn blend operation (darker grunge layer), mixed and controlled by a step.
		vec2 blend_burn_warp_1 = (warp_2) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1_warp_2 - 0.5), - mingle_warp_y * (fbm_2_warp_2 - 0.5));
		vec2 blend_burn_warp_2 = (warp_2) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2_warp_2 - 0.5), - mingle_warp_y * (fbm_1_warp_2 - 0.5));
		float mingle_burn_opacity_adjust = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3_warp_2);
		
		// Warp and dodge blend operation (lighter grunge layer), mixed and controlled by a step.
		vec2 mingle_dodge_warp_1 = (warp_1) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1_warp_1 - 0.5), - mingle_warp_y * (fbm_2_warp_1 - 0.5));
		vec2 mingle_dodge_warp_2 = (warp_1) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2_warp_1 - 0.5), - mingle_warp_y * (fbm_1_warp_1 - 0.5));
		float mingle_dodge_opacity_adjust = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3_warp_1);

		// Combine burn and dodge layers, with an additional warp and blend (overlay) operation, controlled by a step
		float mingle_overlay_burn_input_1 = fbm_perlin_2d((mingle_dodge_warp_1), _size, grunge_iterations, persistence, offset, seed.perlin_seed_4);
		float mingle_overlay_burn_input_2 = fbm_perlin_2d((mingle_dodge_warp_2), _size, grunge_iterations, persistence, offset, seed.perlin_seed_5);
		float mingle_overlay_dodge_input_1 = fbm_perlin_2d((blend_burn_warp_1), _size, grunge_iterations, persistence, offset, seed.perlin_seed_5);
		float mingle_overlay_dodge_input_2 = fbm_perlin_2d((blend_burn_warp_2), _size, grunge_iterations, persistence, offset, seed.perlin_seed_4);
		float mingle_overlay_burn = burn(mingle_overlay_burn_input_1, mingle_overlay_burn_input_2, mingle_dodge_opacity_adjust);
    	float mingle_overlay_dodge = dodge(mingle_overlay_dodge_input_1, mingle_overlay_dodge_input_2, mingle_burn_opacity_adjust);
		float mingle_overlay_opacity_adjust_1 = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3);
		float mingle_overlay_output_1 = overlay(mingle_overlay_burn, mingle_overlay_dodge, mingle_overlay_opacity_adjust_1);
		
		float grunge_texture = clamp((mingle_overlay_output_1 - params.tone_value) / params.tone_width + 0.5, 0.0, 1.0);
		imageStore(grunge_buffer, ivec2(pixel), vec4(vec3(grunge_texture), 1.0));
    }

    if (params.stage == 1.0) {
		float _bevel = params.bevel / 100;
		float _mortar = params.mortar / 100;
		float _rounding = params.rounding / 100;
        float _macro_uniformity = params.macro_uniformity * 1e-4;
        float _micro_uniformity = params.micro_uniformity * 1e-4;;

		// transform UVs with noise - break up straight brick lines
		float transform_perlin_macro = fbm_perlin_2d(uv, vec2(2.0, 6.0), 6, 0.5, 0.0, 0.0);
		float transform_perlin_micro = fbm_perlin_2d(uv, vec2(25.0), 6, 0.5, 0.0, 0.0);
		vec2 transformed_uv = uv - vec2(_macro_uniformity * (2.0 * transform_perlin_macro - 1.0));
		transformed_uv = transformed_uv - vec2((_micro_uniformity / 2) * (2.0 * transform_perlin_micro - 1.0), _micro_uniformity * (2.0 * transform_perlin_micro - 1.0));

		// Generate base brick pattern
		vec4 wavy_brick_bounding_rect = get_brick_bounds(transformed_uv, vec2(params.columns, params.rows), params.repeat, params.row_offset, int(params.pattern));
		float brick_mask = 1.0 - get_brick_pattern(transformed_uv, wavy_brick_bounding_rect.xy, wavy_brick_bounding_rect.zw, _mortar, _rounding, _bevel, 1.0 / params.rows);
        imageStore(r16f_buffer_3, ivec2(pixel), vec4(vec3(brick_mask), 1.0));
        float dilated_mask = get_brick_pattern(transformed_uv, wavy_brick_bounding_rect.xy, wavy_brick_bounding_rect.zw, _mortar * 1.5, _rounding, _bevel, 1.0 / params.rows);
		imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(dilated_mask), 1.0));

        float brick_damage_perlin = fbm_perlin_2d(uv, vec2(params.damage_scale_x, params.damage_scale_y), int(params.damage_iterations), params.damage_persistence, damage_offset, seed.perlin_seed_6);
        imageStore(noise_buffer, ivec2(pixel), vec4(vec3(brick_damage_perlin), 1.0));

        vec4 brick_bounding_rect = get_brick_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.row_offset, int(params.pattern));
        float pattern = 1.0 - get_brick_pattern(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar, _rounding, _bevel, 1.0 / params.rows);
        
        vec4 brick_fill = round(vec4(fract(brick_bounding_rect.xy), brick_bounding_rect.zw - brick_bounding_rect.xy) * params.texture_size) / params.texture_size;
        vec3 random_brick_colour = mix(vec3(0.0, 0.0, 0.0), rand3(vec2(float((seed.brick_colour_seed)), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

        vec2 grunge_uv = fract(uv - vec2(0.5 * (2.0 * random_brick_colour.b - 1.0), 0.250 * (2.0 * random_brick_colour.b - 1.0)));
		ivec2 transformed_pixel = ivec2(grunge_uv * _texture_size);
        float grunge = imageLoad(grunge_buffer, transformed_pixel).r;

        float brick_grunge_texture = 1.0 - multiply(random_brick_colour.r, grunge, grunge_blend_opacity);
        float brick_grunge_mortar_mask_blend = normal(1.0, brick_grunge_texture, brick_mask);
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(brick_grunge_mortar_mask_blend), 1.0));

        vec3 albedo = normal(mortar_col.rgb, gradient_fct(random_brick_colour.g).rgb, brick_mask);
        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }

    if (params.stage == 2.0) {
        const float blue_noise_brightness = (params.blue_noise_brightness - 70) / 100;

        float macro_damage = slope_blur(uv);
        macro_damage = clamp(macro_damage * slope_blur_contrast + slope_blur_brightness + 0.5 * (1.0 - slope_blur_contrast), 0.0, 1.0);
        float micro_damage = imageLoad(r16f_buffer_2, ivec2(pixel)).r;
        
        float blue_noise = hash_ws(vec2(pixel), seed.b_noise_seed);
        float blue_noise_tone_mapped = clamp((blue_noise - blue_noise_tone_value) / params.blue_noise_tone_width + 0.5, 0.0, 1.0);
        float blue_noise_darkened = clamp(blue_noise_tone_mapped * blue_noise_contrast + blue_noise_brightness + 0.5 * (1.0 - blue_noise_contrast), 0.0, 1.0);

        float mask = imageLoad(r16f_buffer_3, ivec2(pixel)).r;
        float macro_blend = normal(blue_noise_darkened, macro_damage, mask);

        float base_texture_blend = multiply(macro_blend, micro_damage, 1.0);
        imageStore(rgba32f_buffer, ivec2(pixel), vec4(vec3(base_texture_blend), 1.0));

        float occlusion_input = (ao_out_min) + (base_texture_blend - ao_in_min) * (ao_out_max - ao_out_min) / (ao_in_max - ao_in_min);
        float roughness_input = (roughness_out_min) + ((1.0 - base_texture_blend) - roughness_in_min) * (roughness_out_max - roughness_out_min) / (roughness_in_max - roughness_in_min);
        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion_input), 1.0));
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness_input), 1.0));
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(occlusion_input, roughness_input, 0.0), 1.0));
    }

    if (params.stage == 3.0) {
		vec3 normals = sobel_filter(ivec2(pixel), sobel_strength);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        }
        
        if (params.normals_format == 1.0) {
            vec3 directx_normals = normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }
	}
}