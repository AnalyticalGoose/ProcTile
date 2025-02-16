#[compute]
#version 450

// Heavily inspired by the Material Maker default bricks material
// https://github.com/RodZill4/material-maker

// Grunge texture ported from leonard7e's layered FBM Perlin noise implementation
// https://www.materialmaker.org/material?id=76


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
layout(r16f, set = 1, binding = 3) uniform image2D noise_buffer;
layout(r16f, set = 1, binding = 4) uniform image2D grunge_buffer;

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
	float b_noise_contrast; // Intensity
	float damage_scale_x; // Scale
	float damage_scale_y;
	float damage_iterations; // Complexity
	float damage_persistence; // Intensity
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

// S1 - Mortar Noise
const float b_noise_brightness = 0.22; // Shifts output curve vertically (brightness)
const float b_noise_rs = 6.0; // Relative slope
const float b_noise_control_x = 0.29; // Control point x-coordinate for the first segment
const float b_noise_control_y = 0.71; // Control point y-coordinate for the first segment

// S2 - Brick Albedo Parameters
const float mortar_col_mask_blend_opacity = 1.0; // Blend between mortar colour and mask
const float mortar_opacity = 1.0; // Blend between mortar and brick colorise
const float step_value = 0.62; // Tones step, creates brick / mortar mask
const float step_width = 0.10;

// Transform grunge texture into brick pattern
const float grunge_translate_x = 0.50;
const float grunge_translate_y = 0.25;
const float grunge_rotate = 0.00;
const float grunge_scale_x = 1.00;
const float grunge_scale_y = 1.00;
const float grunge_blend_opacity = 0.80;

// Brick damage perlin
const float damage_offset = 0.00;

// Roughness map variables
const float roughness_in_min = 0.00;
const float roughness_in_max = 0.15;
const float roughness_out_min = 0.60;
const float roughness_out_max = 0.90;

// Occlusion tone map
const float o_control_x = 0.02; // Control point x-coordinate for the first segment
const float o_control_y = 0.68; // Control point y-coordinate for the first segment
const float o_curve_1_rs = -5.11; // Relative slope for control point 1 of the first segment
const float o_curve_1_ls = -0.54; // Local slope for control point 2 of the first segment
const float o_curve_1_ep_y = 0.69; // End point y-coordinate for the first segment
const float o_curve_1_cp2_rs = 1.23; // Relative slope for control point 1 of the second segment
const float o_curve_2_ls = 0.67; // Local slope for control point 2 of the second segment

// Normal map
const float sobel_strength = 0.12;


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

vec3 normal(vec3 base, vec3 blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
}

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}


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

// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
float hash_ws(vec2 x, float seed) {
    vec3 x3 = fract(vec3(x.xyx) * (0.1031 + seed));
    x3 += dot(x3, x3.yzx + 33.33);
    return fract((x3.x + x3.y) * x3.z);
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

// Bezier curve tone mapping
float tone_map(float x) {
    if (x <= b_noise_control_x) {
        float pos = x; // Distance from start of curve (relative position)
        float len = b_noise_control_x; // Segment length (first segment)
        float prog = pos / len; // Normalised progress as a fraction
        float omp = (1.0 - prog); // Remaining fraction (one minus progress)
        float omp2 = omp * omp;
        float prog2 = prog * prog;
        float prog3 = prog2 * prog;
        len /= 3.0; // Third of segment length for control points
        float cp1_y  = len * b_noise_rs; // Control point 1 y offset
        float cp2_y = b_noise_control_y - len; // Control point 2 y offset
        float ep_y = b_noise_control_y; // End point y value
        
        return (((cp1_y * omp2) * prog) * 3.0) + (((cp2_y * omp) * prog2) * 3.0) + (ep_y * prog3);
    }
    else {
    	float pos = x - b_noise_control_x; // Distance from first segment's end (relative position)
    	float len = 1.0 - b_noise_control_x; // Segment length (second segment)
        float prog = pos / len; 
        float omp = (1.0 - prog);
        float omp2 = omp * omp;
        float omp3 = omp2 * omp;
        float prog2 = prog * prog;
        float prog3 = prog2 * prog; 
        len /= 3.0;  
        float cp_y = b_noise_control_y + len; // Control point y offset
        float sp_y = b_noise_control_y; // Start point y value
        
        return (sp_y * omp3) + (((cp_y * omp2) * prog) * 3.0) + ((omp * prog2) * 3.0) + prog3;
    }
}

float occlusion_tone_map(float x) {
    if (x <= o_control_x) {
        float pos = x; // Distance from start of curve (relative position)
        float len = o_control_x; // Segment length (first segment)
        float prog = pos / len; // Normalized progress as a fraction
        float omp = (1.0 - prog); // Remaining fraction (one minus progress)
        float omp2 = omp * omp;
        float omp3 = omp2 * omp;
        float prog2 = prog * prog;
        float prog3 = prog2 * prog;
        len /= 3.0; // Third of segment length for control points

        float cp1_y = len * o_curve_1_rs; // Control point 1 y offset
        float cp2_y = o_control_y - len * o_curve_1_ls; // Control point 2 y offset
        float ep_y = o_curve_1_ep_y; // End point y value
        
        return (((cp1_y * omp2) * prog) * 3.0) + (((cp2_y * omp) * prog2) * 3.0) + (ep_y * prog3);
    } 
    else {
        float pos = x - o_control_x; // Distance from first segment's end (relative position)
        float len = 1.0 - o_control_x; // Segment length (second segment)
        float prog = pos / len; // Normalized progress as a fraction
        float omp = (1.0 - prog); // Remaining fraction (one minus progress)
        float omp2 = omp * omp;
        float omp3 = omp2 * omp;
        float prog2 = prog * prog;
        float prog3 = prog2 * prog;
        len /= 3.0; // Third of segment length for control points
        
        float sp_y = o_curve_1_ep_y; // Start point y value
        float cp1_y = sp_y + len * o_curve_1_cp2_rs; // Control point 1 y offset
        float cp2_y = 1.0 - len * o_curve_2_ls; // Control point 2 y offset
        float ep_y = 1.0; // End point y value
        
        return (sp_y * omp3) + (((cp1_y * omp2) * prog) * 3.0) + (((cp2_y * omp) * prog2) * 3.0) + (ep_y * prog3);
    }
}

vec2 transform(vec2 uv, vec2 translate, float rotate, vec2 scale) {
 	vec2 rv;
	uv -= translate;
	uv -= vec2(0.5);
	rv.x = cos(rotate) * uv.x + sin(rotate) * uv.y;
	rv.y = -sin(rotate) * uv.x + cos(rotate) * uv.y;
	rv /= scale;
	rv += vec2(0.5);
	return rv;	
}

// Need solution using shared memory and / or less recursion.
vec4 slope_blur(vec2 uv) { 
    // Scale UV to texture size
    vec2 scaled_uv = uv * params.texture_size;
    ivec2 pixel_coords = ivec2(scaled_uv);

    // Fetch precomputed heightmap value
    float v = imageLoad(noise_buffer, pixel_coords).r;

    // Compute slope using precomputed heightmap
    float dx = 1.0 / params.texture_size;
    vec2 slope = vec2(
        imageLoad(noise_buffer, pixel_coords + ivec2(1, 0)).r - v,
        imageLoad(noise_buffer, pixel_coords + ivec2(0, 1)).r - v
    );

    // Normalize slope
    float slope_strength = length(slope) * params.texture_size;
    vec2 norm_slope = (slope_strength == 0.0) ? vec2(0.0, 1.0) : normalize(slope);
    vec2 e = dx * norm_slope;

    // Blur loop
    vec4 rv = vec4(0.0);
    float sum = 0.0;
    float sigma = max(2.0 * slope_strength, 0.0001);

    for (float i = 0.0; i <= 50.0; i += 1.0) {
        float coef = exp(-0.5 * pow(i / sigma, 2.0)) / (6.28318530718 * sigma * sigma);

        // Fetch mask at offset UV
        vec2 offset_uv = uv + i * e;
        ivec2 offset_pixel = ivec2(offset_uv * params.texture_size);
        float mask_value = imageLoad(r16f_buffer_2, offset_pixel).r;

        // Accumulate weighted mask
        rv += vec4(vec3(mask_value), 1.0) * coef;
        sum += coef;
    }

    // Normalize result
    return rv / sum;
}

// Generate normals
vec3 sobel_filter(ivec2 pixel_coords, float amount, float size) {
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    // Apply Sobel-like filter to compute gradient
    rv += vec2(1.0, -1.0) * imageLoad(rgba32f_buffer, pixel_coords + ivec2(e.x, e.y)).r;
    rv += vec2(-1.0, 1.0) * imageLoad(rgba32f_buffer, pixel_coords - ivec2(e.x, e.y)).r;
    rv += vec2(1.0, 1.0) * imageLoad(rgba32f_buffer, pixel_coords + ivec2(e.x, -e.y)).r;
    rv += vec2(-1.0, -1.0) * imageLoad(rgba32f_buffer, pixel_coords - ivec2(e.x, -e.y)).r;
    rv += vec2(2.0, 0.0) * imageLoad(rgba32f_buffer, pixel_coords + ivec2(2, 0)).r;
    rv += vec2(-2.0, 0.0) * imageLoad(rgba32f_buffer, pixel_coords - ivec2(2, 0)).r;
    rv += vec2(0.0, 2.0) * imageLoad(rgba32f_buffer, pixel_coords + ivec2(0, 2)).r;
    rv += vec2(0.0, -2.0) * imageLoad(rgba32f_buffer, pixel_coords - ivec2(0, 2)).r;

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

	if (params.stage == 0.0) { // grunge base texture
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

	if (params.stage == 1.0) { // Generate base brick pattern, brick & mortar masks, albedo texture & mortar b-noise texture
		float _bevel = params.bevel / 100;
		float _mortar = params.mortar / 100;
		float _rounding = params.rounding / 100;

		// Generate base brick pattern
		vec4 brick_bounding_rect = get_brick_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.row_offset, int(params.pattern));
		float pattern = get_brick_pattern(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar, _rounding, _bevel, 1.0 / params.rows);

		float dilated_mask = 1.0 - get_brick_pattern(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar * 1.5, _rounding, _bevel, 1.0 / params.rows);
		imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(dilated_mask), 1.0));

		// tones step to create brick and mortar masks
		float mortar_mask = clamp((pattern - step_value) / max(0.0001, step_width) + 0.5, 0.0, 1.0);
		float brick_mask = 1.0 - mortar_mask;
		imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(brick_mask), 1.0));

		// brick fill output - sampled and each brick given a random colour
		vec4 brick_fill = round(vec4(fract(brick_bounding_rect.xy), brick_bounding_rect.zw - brick_bounding_rect.xy) * params.texture_size) / params.texture_size;
		vec3 random_brick_colour = mix(vec3(0.0, 0.0, 0.0), rand3(vec2(float((seed.brick_colour_seed)), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

		// decomposed random colour by channel
		float random_col_r = random_brick_colour.r;
		float random_col_g = random_brick_colour.g;
		float random_col_b = random_brick_colour.b;

		// Random colour mapped onto gradient brick colour
		vec4 gradient_brick_colour = gradient_fct(random_col_g);

		// Brick and mortar colours are blended together using a mask to create albedo texture
		float brick_mortar_blend_mask = mortar_opacity * brick_mask;
		vec4 albedo = vec4(normal(mortar_col.rgb, gradient_brick_colour.rgb, brick_mortar_blend_mask * 1.0), min(1.0, gradient_brick_colour.a + brick_mortar_blend_mask * 1.0));
		imageStore(albedo_buffer, ivec2(pixel), albedo);

		// Mortar b-noise
		float hash = hash_ws(vec2(pixel), seed.b_noise_seed);
		vec3 blue_noise = vec3(tone_map(hash));
		vec3 blue_noise_desat = clamp(blue_noise * params.b_noise_contrast + vec3(b_noise_brightness + 0.5 * (1.0 - params.b_noise_contrast)), vec3(0.0), vec3(1.0));
		vec3 mortar_noise = normal(vec3(1.0, uv.y, 1.0), blue_noise_desat, mortar_mask);

		// Transform UV coordinates
		vec2 transformed_uv = fract(
			transform(
				uv,
				vec2(grunge_translate_x * (2.0 * random_col_b - 1.0), grunge_translate_y * (2.0 * random_col_b - 1.0)),
				grunge_rotate * 0.01745329251, // Convert degrees to radians
				vec2(grunge_scale_x * (2.0 * 1.0 - 1.0), grunge_scale_y * (2.0 * 1.0 - 1.0))
			)
		);

		// Map UV coordinates to integer pixel coordinates in the buffer
		ivec2 transformed_pixel = ivec2(transformed_uv * _texture_size);

		// Load from the image buffer using transformed coordinates to align with brick pattern, blend to darken some areas and then invert to give final weathered texture for bricks.
		float grunge_pattern = imageLoad(grunge_buffer, transformed_pixel).r;
		vec3 brick_grunge_texture = 1.0 - multiply(vec3(random_col_r), vec3(grunge_pattern), grunge_blend_opacity);

		// Final blend of all the 'physical' characteristics into a base greyscale texture to be used to generate normal, roughness and occlusion maps.
		vec3 base_surface_texture = normal(mortar_noise, brick_grunge_texture, brick_mask);
		imageStore(rgba32f_buffer, ivec2(pixel), vec4(base_surface_texture, 1.0));

		float brick_damage_perlin = fbm_perlin_2d(uv, vec2(params.damage_scale_x, params.damage_scale_y), int(params.damage_iterations), params.damage_persistence, damage_offset, seed.perlin_seed_6);
		imageStore(noise_buffer, ivec2(pixel), vec4(vec3(brick_damage_perlin), 1.0));
	}

	if (params.stage == 2.0) {
		// Brick damage / weathering generated by blending perlin in a slope blur
		vec4 slope_blur_result = 1.0 - slope_blur(uv);
		float brick_mask = imageLoad(r16f_buffer_1, ivec2(pixel)).r;
		
		vec3 masked_brick_damage = normal(vec3(1.0, uv.y, 1.0), slope_blur_result.rgb, brick_mask);
		vec4 base_surface_texture = imageLoad(rgba32f_buffer, ivec2(pixel));
		float mortar_mask = 1.0 - brick_mask; 

		// roughness input
		vec4 inverted_base_surface_texture = 1.0 - base_surface_texture;

		float roughness_input = (roughness_out_min) + (inverted_base_surface_texture.r - roughness_in_min) *
								(roughness_out_max - roughness_out_min) / (roughness_in_max - roughness_in_min);
		imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness_input), 1.0));

		// normal map input
		float normal_input = dot(multiply(base_surface_texture.rgb, masked_brick_damage, 0.5), vec3(1.0) / 3.0);
		imageStore(rgba32f_buffer, ivec2(pixel), vec4(vec3(normal_input), 1.0));

		// occlusion input
		vec3 blend_top = normal(vec3(mortar_mask), base_surface_texture.rgb, 0.80);
		vec3 blend_bottom = normal(slope_blur_result.rgb, base_surface_texture.rgb, 0.80);
		vec3 occlusion_input = multiply(blend_bottom, blend_top, 0.80);
		float occlusion = occlusion_tone_map(occlusion_input.r);
		imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));

		// ORM input
		imageStore(orm_buffer, ivec2(pixel), vec4(occlusion, roughness_input.r, 0.0, 1.0));

        // metallic
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
	}

	if (params.stage == 3.0) {
		vec3 normals = sobel_filter(ivec2(pixel), sobel_strength, params.texture_size);
        
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
