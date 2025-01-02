#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D current_buffer;
layout(rgba32f, set = 1, binding = 0) uniform restrict readonly image2D previous_buffer;
layout(rgba32f, set = 2, binding = 0) uniform restrict writeonly image2D output_buffer;

layout(rgba32f, set = 3, binding = 0) uniform restrict image2D albedo_buffer;
layout(rgba32f, set = 4, binding = 0) uniform restrict image2D roughness_buffer;
layout(rgba32f, set = 5, binding = 0) uniform restrict image2D normal_buffer;
layout(rgba32f, set = 6, binding = 0) uniform restrict image2D occlusion_buffer;

layout(rgba32f, set = 7, binding = 0) uniform restrict image2D r16f_buffer_1;
layout(r16f, set = 8, binding = 0) uniform restrict image2D r16f_buffer_2;
layout(rgba32f, set = 9, binding = 0) uniform restrict image2D rgba32f_buffer;
layout(rgba32f, set = 10, binding = 0) uniform restrict image2D noise_buffer;
layout(rgba32f, set = 11, binding = 0) uniform restrict image2D grunge_buffer;

layout(set = 12, binding = 0, std430) buffer restrict readonly Misc {
	float perlin_seed_1;
	float perlin_seed_2;
	float perlin_seed_3;
	float perlin_seed_4;
	float perlin_seed_5;
	float perlin_seed_6;
	float b_noise_seed;
} misc;

layout(set = 13, binding = 0, std430) buffer restrict readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 14, binding = 0, std430) buffer restrict readonly GradientColours {
    vec4 gradient_col[];
};

layout(set = 15, binding = 0, std430) buffer restrict readonly MortarColour {
	vec4 mortar_col;
};

layout(push_constant, std430) uniform restrict readonly Params {
	// Stage ? - Brick Pattern
	float rows;
	float columns;
	float row_offset;
	float mortar;
	float bevel;
	float rounding;
	float repeat;
	
	// Stage 0 - Grunge Base Texture
	float tone_value; // Displacement
	float tone_width; // Blending
	float mingle_smooth; // Plateau Size
	float mingle_warp_strength; // Texture Density
	
	// Stage 1 - Mortar Noise
	float b_noise_contrast; // 'Intensity' - adjusts steepness of curve (contrast)

	// meta
	float texture_size;

	float stage;

	// float padding_1;
	// float padding_2;
	// float padding_3;


} params;

// S0 - Grunge Texture Parameters
const int grunge_iterations = 10;
const float persistence = 0.61;
const float offset = 0.00;
const float mingle_opacity = 1.0;
const float mingle_step = 0.5;
const float mingle_warp_x = 0.5;
const float mingle_warp_y = 0.5;
// const float mingle_warp_strength = 2.0; // Density of grunge texture, seems to do the same as scale..

// S1 -
const float b_noise_brightness = 0.22; // shifts output curve vertically (brightness)
const float b_noise_rs = 6.0; // highlights / darklspots strength perhaps? testing needed in engine
const float b_noise_control_x = 0.29;
const float b_noise_control_y = 0.71;

// S2 - Brick Albedo Parameters
const float seed_variation = 0.0;
const float mortar_col_mask_blend_opacity = 1.0; // blend between mortar colour and mask // not needed??
const float mortar_opacity = 1.0; // blend between mortar and brick colorise
const float step_value = 0.62; // tones step, creates brick / mortar mask
const float step_width = 0.10;

const vec3 mortar_colour = vec3(1.00, 0.93, 0.81); // does need to be exposed

// // Brick gradient colour - Ideally this should be robust enough for the user to select the number of colours at the very least, and aspirationally move the gradient sliders
// const float brick_col_gradient_pos[7] = float[]( 0.00, 0.16, 0.34, 0.48, 0.61, 0.82, 1.00 );
// const vec4 brick_col_gradient_val[7] = vec4[](vec4(0.78, 0.36, 0.18, 1.00), vec4(0.76, 0.34, 0.17, 1.00), vec4(0.82, 0.40, 0.24, 1.00), vec4(0.76, 0.36, 0.21, 1.00), vec4(0.80, 0.40, 0.24, 1.00), vec4(0.82, 0.41, 0.19, 1.00), vec4(0.89, 0.49, 0.24, 1.00));

// Fill to random color
const float brick_colour_seed = 0.064537466;
const vec4 random_edge_col = vec4(1.0, 1.0, 1.0, 1.0); // "Color used for outlines" - fairly sure this isn't needed and never will be, likely remove and code into shader.


// transform params
const float grunge_translate_x = 0.50;
const float grunge_translate_y = 0.25;
const float grunge_rotate = 0.00;
const float grunge_scale_x = 1.00;
const float grunge_scale_y = 1.00;

const float grunge_blend_opacity = 0.80;


// brick damage perlin variables
const float damage_scale_x = 10.00;
const float damage_scale_y = 15.00;
const float damage_iterations = 3.00;
const float damage_persistence = 0.50;
const float damage_offset = 0.00;

const int dilation_size = 10;


// roughness map variables
const float roughness_in_min = 0.00;
const float roughness_in_max = 0.15;
const float roughness_out_min = 0.60;
const float roughness_out_max = 0.90;


vec4 calc_brick_properties(vec2 uv, vec2 brick_min, vec2 brick_max, float mortar_thickness, float rounding, float bevel_size, float brick_height) {
	float brick_color;
	vec2 brick_size = brick_max - brick_min;
	float min_size = min(brick_size.x, brick_size.y);

	// scale properties based on brick height
	mortar_thickness *= brick_height;
	bevel_size *= brick_height;
	rounding *= brick_height;

	vec2 brick_center = 0.5 * (brick_min + brick_max);
	vec2 distance_to_edge = abs(uv - brick_center) - 0.5 * (brick_size) + vec2(rounding + mortar_thickness);
	brick_color = length(max(distance_to_edge, vec2(0))) + min(max(distance_to_edge.x, distance_to_edge.y), 0.0) - rounding;
	brick_color = clamp(-brick_color / bevel_size, 0.0, 1.0);
	vec2 tiled_brick_position = mod(brick_min, vec2(1.0, 1.0));
	return vec4(brick_color, brick_center, tiled_brick_position.x + 7.0 * tiled_brick_position.y);
}

vec4 get_brick_bounding_rect_rb(vec2 uv, vec2 grid_count, float repeat_factor, float row_offset) {
    grid_count *= repeat_factor;
    float x_offset = row_offset * step(0.5, fract(uv.y * grid_count.y * 0.5));
    vec2 brick_min = floor(vec2(uv.x * grid_count.x - x_offset, uv.y * grid_count.y));
    brick_min.x += x_offset;
    brick_min /= grid_count;
    return vec4(brick_min, brick_min + vec2(1.0) / grid_count);
}


// float rand(vec2 x) { // 4K - 11/12 -- 2k - 43/44
//     return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
// }

// float rand(vec2 x) { // 4K - 11 -- 2k - 45/46
//     vec3 x3 = fract(vec3(x.xyx) * 0.1031);
//     x3 += dot(x3, x3.yzx + 33.33);
//     return fract((x3.x + x3.y) * x3.z);
// }


float rand(vec2 p) { // 4K - 13/14 -- 2L - 49/50 
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
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

float blend_overlay_f(float c1, float c2) {
	return (c1 < 0.5) ? (2.0 * c1 * c2) : (1.0-2.0 * (1.0 - c1) * (1.0 - c2));
}

vec3 blend_overlay(vec2 uv, vec3 c1, vec3 c2, float opacity) {
	return opacity * vec3(blend_overlay_f(c1.x, c2.x), blend_overlay_f(c1.y, c2.y), blend_overlay_f(c1.z, c2.z)) + (1.0-opacity) * c2;
}

float blend_burn_f(float c1, float c2) {
	return (c1==0.0) ? c1 : max((1.0 - ((1.0 - c2) / c1)), 0.0);
}

vec3 blend_burn(vec2 uv, vec3 c1, vec3 c2, float opacity) {
	return opacity * vec3(blend_burn_f(c1.x, c2.x), blend_burn_f(c1.y, c2.y), blend_burn_f(c1.z, c2.z)) + (1.0-opacity) * c2;
}

float blend_dodge_f(float c1, float c2) {
	return (c1 == 1.0) ? c1 : min(c2 / (1.0 - c1), 1.0);
}

vec3 blend_dodge(vec2 uv, vec3 c1, vec3 c2, float opacity) {
	return opacity * vec3(blend_dodge_f(c1.x, c2.x), blend_dodge_f(c1.y, c2.y), blend_dodge_f(c1.z, c2.z)) + (1.0-opacity) * c2;
}

vec3 blend_normal(vec2 uv, vec3 c1, vec3 c2, float opacity) {
	return opacity * c1 + (1.0 - opacity) * c2;
}

vec3 blend_multiply(vec2 uv, vec3 c1, vec3 c2, float opacity) {
	return opacity * c1 * c2 + (1.0 - opacity) * c2;
}


float perlin_noise_2d(vec2 coord, vec2 size, float offset, float seed) {
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


float fbm_2d_perlin(vec2 coord, vec2 size, int iterations, float persistence, float offset, float seed) {
	float normalize_factor = 0.0;
	float value = 0.0;
	float scale = 1.0;
	for (int i = 0; i < iterations; i++) {
		float noise = perlin_noise_2d(coord * size, size, offset, seed);
		value += noise * scale;
		normalize_factor += scale;
		size *= 2.0;
		scale *= persistence;
	}
	return value / normalize_factor;
}

// Takes in a grayscale pixel and assigns a colour depending on the value
// vec4 gradient_fct(float x) {
// 	if (x < brick_col_gradient_pos[0]) {
// 		return brick_col_gradient_val[0];
//   	} 
//   	else if (x < brick_col_gradient_pos[1]) {
//     	return mix(brick_col_gradient_val[0], brick_col_gradient_val[1], ((x-brick_col_gradient_pos[0]) / (brick_col_gradient_pos[1] - brick_col_gradient_pos[0])));
//   	} 
//   	else if (x < brick_col_gradient_pos[2]) {
//     	return mix(brick_col_gradient_val[1], brick_col_gradient_val[2], ((x-brick_col_gradient_pos[1])/(brick_col_gradient_pos[2] - brick_col_gradient_pos[1])));
//   	} 
//   	else if (x < brick_col_gradient_pos[3]) {
//     	return mix(brick_col_gradient_val[2], brick_col_gradient_val[3], ((x-brick_col_gradient_pos[2]) / (brick_col_gradient_pos[3] - brick_col_gradient_pos[2])));
//   	} 
//   	else if (x < brick_col_gradient_pos[4]) {
//     	return mix(brick_col_gradient_val[3], brick_col_gradient_val[4], ((x-brick_col_gradient_pos[3]) / (brick_col_gradient_pos[4] - brick_col_gradient_pos[3])));
//   	} 
//   	else if (x < brick_col_gradient_pos[5]) {
//     	return mix(brick_col_gradient_val[4], brick_col_gradient_val[5], ((x-brick_col_gradient_pos[4]) / (brick_col_gradient_pos[5] - brick_col_gradient_pos[4])));
//   	} 
//   	else if (x < brick_col_gradient_pos[6]) {
//     	return mix(brick_col_gradient_val[5], brick_col_gradient_val[6], ((x-brick_col_gradient_pos[5]) / (brick_col_gradient_pos[6] - brick_col_gradient_pos[5])));
//   	}
  
//   return brick_col_gradient_val[6];
// }


vec4 gradient_fct(float x) {
    int count = int(gl_NumWorkGroups.x); // Use the number of offsets dynamically
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







vec4 toLinear(vec4 sRGB)
{
	bvec3 cutoff = lessThan(sRGB.rgb, vec3(0.04045));
	vec3 higher = pow((sRGB.rgb + vec3(0.055))/vec3(1.055), vec3(2.4));
	vec3 lower = sRGB.rgb/vec3(12.92);

	return vec4(mix(higher, lower, cutoff), sRGB.a);
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
        float cp1y  = len * b_noise_rs; // Control point 1 y offset
        float cp2y = b_noise_control_y - len; // Control point 2 y offset
        float epy = b_noise_control_y; // End point y value
        
        return (((cp1y * omp2) * prog) * 3.0) + (((cp2y * omp) * prog2) * 3.0) + (epy * prog3);
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
        float cpy = b_noise_control_y + len; // Control point y offset
        float spy = b_noise_control_y; // Start point y value
        
        return (spy * omp3) + (((cpy * omp2) * prog) * 3.0) + ((omp * prog2) * 3.0) + prog3;
    }
}


const float occlusion_control_x = 0.020689655;
const float occulsion_control_y = 0.683391571;
const float occlusion_rs = -5.106000781;
const float p_o276789955930592_curve_1_ls = -0.538809011;
const float p_o276789955930592_curve_1_y = 0.687344193;
const float p_o276789955930592_curve_1_rs = 1.230451057;
const float p_o276789955930592_curve_2_ls = 0.665561667;

float occlusion_tone_map(float x) {
	if (x <= occlusion_control_x) {
		float pos = x;
		float len = occlusion_control_x;
		float prog = pos / len;
		float omt = (1.0 - prog);
		float omt2 = omt * omt;
		float omt3 = omt2 * omt;
		float prog2 = prog * prog;
		float prog3 = prog2 * prog;
		len /= 3.0;
		float y1 = 0.0;
		float yac = len * occlusion_rs;
		float ybc = occulsion_control_y - len * p_o276789955930592_curve_1_ls;
		float y2 = p_o276789955930592_curve_1_y;
		
		return y1 * omt3 + yac * omt2 * prog * 3.0 + ybc * omt * prog2 * 3.0 + y2 * prog3;
	}
	else {
		float pos = x - occlusion_control_x;
		float len = 1.0 - occlusion_control_x;
		float prog = pos/ len;
		float omt = (1.0 - prog);
		float omt2 = omt * omt;
		float omt3 = omt2 * omt;
		float prog2 = prog * prog;
		float prog3 = prog2 * prog;
		len /= 3.0;
		float y1 = p_o276789955930592_curve_1_y;
		float yac = p_o276789955930592_curve_1_y + len * p_o276789955930592_curve_1_rs;
		float ybc = 1.0 - len * p_o276789955930592_curve_2_ls;
		float y2 = 1.0;
		
		return y1 * omt3 + yac * omt2 * prog * 3.0 + ybc * omt * prog2 * 3.0 + y2 * prog3;
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



// float dilate_mask(ivec2 pixel) {
//     float max_neighbor_value = 0.0; // Start with no dilation effect

// 	ivec2 offsets[9] = ivec2[](
//     ivec2(-10, -10), ivec2(0, -10), ivec2(10, -10),
//     ivec2(-10,  0), ivec2(0,  0), ivec2(10,  0),
//     ivec2(-10,  10), ivec2(0,  10), ivec2(10,  10)
// 	);

//     for (int i = 0; i < 9; i++) {
//         ivec2 neighbor_pixel = pixel + offsets[i];

//         // Ensure pixel coordinates are within bounds
//         neighbor_pixel = ivec2(
//             clamp(neighbor_pixel.x, 0, params.texture_size - 1),
//             clamp(neighbor_pixel.y, 0, params.texture_size - 1)
//         );

//         // Sample neighbor mortar mask from buffer
//         float neighbor_mortar = imageLoad(r16f_buffer_1, neighbor_pixel).r;

//         // Update maximum value
//         max_neighbor_value = max(max_neighbor_value, neighbor_mortar);
//     }

//     return max_neighbor_value;
// }

/*
Both slope_blur() and dilate_mask() above use recursive texture lookups that have caused some nasty data races.
I think the race conditions are largely solved in the current config with the way the shader stages are laid out,
However I'm not happy with the current implementation of these functions and would ideally like a solution using shared memory and / or less recursion.
I am concerned that on less powerful hardware there might be side effects that are not immediately apparent to the user by simply producing a poor quality texture with artifacts. 
*/
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



// Input sampling from an image buffer using pixel coordinates
float o419916945495_input_in(ivec2 pixel_coords) {
    // Clamp to avoid out-of-bounds issues
    // pixel_coords = clamp(pixel_coords, ivec2(0), ivec2(params.texture_size - 1));

    // Access red channel from buffer
    return imageLoad(rgba32f_buffer, pixel_coords).r;
}

// Generate normals using a simplified filter
vec3 nm_o419916945495(ivec2 pixel_coords, float amount, float size) {
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    // Apply Sobel-like filter to compute gradient
	rv += vec2(1.0, -1.0) * o419916945495_input_in(pixel_coords + ivec2(e.x, e.y));
	rv += vec2(-1.0, 1.0) * o419916945495_input_in(pixel_coords - ivec2(e.x, e.y));
	rv += vec2(1.0, 1.0) * o419916945495_input_in(pixel_coords + ivec2(e.x, -e.y));
	rv += vec2(-1.0, -1.0) * o419916945495_input_in(pixel_coords - ivec2(e.x, -e.y));
	rv += vec2(2.0, 0.0) * o419916945495_input_in(pixel_coords + ivec2(2, 0));
	rv += vec2(-2.0, 0.0) * o419916945495_input_in(pixel_coords - ivec2(2, 0));
	rv += vec2(0.0, 2.0) * o419916945495_input_in(pixel_coords + ivec2(0, 2));
	rv += vec2(0.0, -2.0) * o419916945495_input_in(pixel_coords - ivec2(0, 2));

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

	float _seed_variation_ = seed_variation;

	vec2 scale = vec2(6.0, 6.0);

	if (params.stage == 0.0) { // grunge base texture
		float fbm_1 = fbm_2d_perlin((uv), scale, grunge_iterations, persistence, offset, misc.perlin_seed_1);
		float fbm_2 = fbm_2d_perlin((uv), scale, grunge_iterations, persistence, offset, misc.perlin_seed_2);
		float fbm_3 = fbm_2d_perlin((uv), scale, grunge_iterations, persistence, offset, misc.perlin_seed_3);

		vec2 warp_1 = (uv) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1 - 0.5), - mingle_warp_y * (fbm_2) - 0.5);
		vec2 warp_2 = (uv) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2 - 0.5), - mingle_warp_y * (fbm_1) - 0.5);

		float fbm_1_warp_1 = fbm_2d_perlin((warp_1), scale, grunge_iterations, persistence, offset, misc.perlin_seed_1);
		float fbm_2_warp_1 = fbm_2d_perlin((warp_1), scale, grunge_iterations, persistence, offset, misc.perlin_seed_2);
		float fbm_3_warp_1 = fbm_2d_perlin((warp_1), scale, grunge_iterations, persistence, offset, misc.perlin_seed_3);
		
		float fbm_1_warp_2 = fbm_2d_perlin((warp_2), scale, grunge_iterations, persistence, offset, misc.perlin_seed_1);
		float fbm_2_warp_2 = fbm_2d_perlin((warp_2), scale, grunge_iterations, persistence, offset, misc.perlin_seed_2);
		float fbm_3_warp_2 = fbm_2d_perlin((warp_2), scale, grunge_iterations, persistence, offset, misc.perlin_seed_3);

		// Warp and burn blend operation (darker grunge layer), mixed and controlled by a step.
		vec2 blend_burn_warp_1 = (warp_2) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1_warp_2 - 0.5), - mingle_warp_y * (fbm_2_warp_2 - 0.5));
		vec2 blend_burn_warp_2 = (warp_2) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2_warp_2 - 0.5), - mingle_warp_y * (fbm_1_warp_2 - 0.5));
		float mingle_burn_opacity_adjust = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3_warp_2);
		
		// Warp and dodge blend operation (lighter grunge layer), mixed and controlled by a step.
		vec2 mingle_dodge_warp_1 = (warp_1) + params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_1_warp_1 - 0.5), - mingle_warp_y * (fbm_2_warp_1 - 0.5));
		vec2 mingle_dodge_warp_2 = (warp_1) - params.mingle_warp_strength * vec2(mingle_warp_x * (fbm_2_warp_1 - 0.5), - mingle_warp_y * (fbm_1_warp_1 - 0.5));
		float mingle_dodge_opacity_adjust = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3_warp_1);

		// Combine burn and dodge layers, with an additional warp and blend (overlay) operation, controlled by a step
		float mingle_overlay_burn_input_1 = fbm_2d_perlin((mingle_dodge_warp_1), scale, grunge_iterations, persistence, offset, misc.perlin_seed_4);
		float mingle_overlay_burn_input_2 = fbm_2d_perlin((mingle_dodge_warp_2), scale, grunge_iterations, persistence, offset, misc.perlin_seed_5);
		float mingle_overlay_dodge_input_1 = fbm_2d_perlin((blend_burn_warp_1), scale, grunge_iterations, persistence, offset, misc.perlin_seed_5);
		float mingle_overlay_dodge_input_2 = fbm_2d_perlin((blend_burn_warp_2), scale, grunge_iterations, persistence, offset, misc.perlin_seed_4);
		vec3 mingle_overlay_burn = blend_burn((warp_1), vec3(mingle_overlay_burn_input_1), vec3(mingle_overlay_burn_input_2), mingle_dodge_opacity_adjust);
		vec3 mingle_overlay_dodge = blend_dodge((warp_2), vec3(mingle_overlay_dodge_input_1), vec3(mingle_overlay_dodge_input_2), mingle_burn_opacity_adjust);
		float mingle_overlay_opacity_adjust_1 = mingle_opacity * smoothstep(mingle_step - params.mingle_smooth, mingle_step + params.mingle_smooth, fbm_3);
		vec3 mingle_overlay_output_1 = blend_overlay((uv), mingle_overlay_burn, mingle_overlay_dodge, mingle_overlay_opacity_adjust_1);
		
		vec3 grunge_texture = clamp((mingle_overlay_output_1 - vec3(params.tone_value)) / params.tone_width + vec3(0.5), vec3(0.0), vec3(1.0));
		imageStore(grunge_buffer, ivec2(pixel), vec4(grunge_texture, 1.0));
	}


	if (params.stage == 1.0) { // Generate base brick pattern, brick & mortar masks, albedo texture & mortar b-noise texture
		float _bevel = params.bevel / 100;
		float _mortar = params.mortar / 100;
		float _rounding = params.rounding / 100;

		// Generate base brick pattern
		vec4 brick_bounding_rect = get_brick_bounding_rect_rb(uv, vec2(params.columns, params.rows), params.repeat, params.row_offset);
		vec4 brick_properties = calc_brick_properties(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar, _rounding, max(0.001, _bevel), 1.0 / params.rows);
		float pattern = brick_properties.x;

		float dilated_mask = 1.0 - calc_brick_properties(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar * 1.5, _rounding, max(0.001, _bevel), 1.0 / params.rows).x;
		imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(dilated_mask), 1.0));

		// tones step to create brick and mortar masks
		float mortar_mask = clamp((pattern - step_value) / max(0.0001, step_width) + 0.5, 0.0, 1.0);
		float brick_mask = 1.0 - mortar_mask;
		imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(brick_mask), 1.0));

		// brick fill output - sampled and each brick given a random colour
		vec4 brick_fill = round(vec4(fract(brick_bounding_rect.xy), brick_bounding_rect.zw - brick_bounding_rect.xy)*4096.0)/4096.0;
		vec3 random_brick_colour = mix(random_edge_col.rgb, rand3(vec2(float((brick_colour_seed+fract(_seed_variation_))), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

		// decomposed random colour by channel
		float random_col_r = random_brick_colour.r;
		float random_col_g = random_brick_colour.g;
		float random_col_b = random_brick_colour.b;

		// Random colour mapped onto gradient brick colour
		vec4 gradient_brick_colour = gradient_fct(random_col_g);

		// Brick and mortar colours are blended together using a mask to create albedo texture
		float brick_mortar_blend_mask = mortar_opacity * brick_mask;
		gradient_brick_colour = vec4(blend_normal((uv), mortar_col.rgb, gradient_brick_colour.rgb, brick_mortar_blend_mask * 1.0), min(1.0, gradient_brick_colour.a + brick_mortar_blend_mask * 1.0));
		
		// Albedo texture is converted from sRGB to Linear
		vec4 albedo = toLinear(gradient_brick_colour);
		imageStore(albedo_buffer, ivec2(pixel), albedo);

		// Mortar b-noise
		float hash = hash_ws(vec2(pixel), misc.b_noise_seed);
		vec3 blue_noise = vec3(tone_map(hash));
		vec3 blue_noise_desat = clamp(blue_noise * params.b_noise_contrast + vec3(b_noise_brightness + 0.5 * (1.0 - params.b_noise_contrast)), vec3(0.0), vec3(1.0));
		vec3 mortar_noise = blend_normal(uv, vec3(1.0, uv.y, 1.0), blue_noise_desat, mortar_mask);

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
		vec4 grunge_pattern = imageLoad(grunge_buffer, transformed_pixel);
		vec3 brick_grunge_texture = 1.0 - blend_multiply(uv, vec3(random_col_r), grunge_pattern.rgb, grunge_blend_opacity);

		// Final blend of all the 'physical' characteristics into a base greyscale texture to be used to generate normal, roughness and occlusion maps.
		vec3 base_surface_texture = blend_normal(uv, mortar_noise, brick_grunge_texture, brick_mask);
		imageStore(rgba32f_buffer, ivec2(pixel), vec4(base_surface_texture, 1.0));
		// Brick damage / weathering generated by blending perlin in a slope blur
		// The normal brick mask is sampled in the dilate_mask function and is stored in a buffer
		// The perlin noise and dilated mask must be repeatedly sampled in the slope blur function and are stored in buffers
		float brick_damage_perlin = fbm_2d_perlin(uv, vec2(damage_scale_x, damage_scale_y), int(damage_iterations), damage_persistence, damage_offset, misc.perlin_seed_6);
		imageStore(noise_buffer, ivec2(pixel), vec4(vec3(brick_damage_perlin), 1.0));
	}

	if (params.stage == 2.0) {
		// float dilated_mask = dilate_mask(ivec2(pixel));
		// imageStore(r16f_buffer_2, ivec2(pixel), vec4(dilated_mask));

		vec4 slope_blur_result = 1.0 - slope_blur(uv); // 37 fps rgba32f // 70 fps r16f
		float brick_mask = imageLoad(r16f_buffer_1, ivec2(pixel)).r;
		
		vec3 masked_brick_damage = blend_normal(uv, vec3(1.0, uv.y, 1.0), slope_blur_result.rgb, brick_mask);
		vec4 base_surface_texture = imageLoad(rgba32f_buffer, ivec2(pixel));
		float mortar_mask = 1.0 - brick_mask; 

		// roughness input
		vec4 inverted_base_surface_texture = 1.0 - base_surface_texture;
		vec4 roughness_input = vec4(
			vec3(roughness_out_min) + (inverted_base_surface_texture.rgb - vec3(roughness_in_min)) * 
			vec3((roughness_out_max - (roughness_out_min)) / (roughness_in_max - (roughness_in_min))), 1.0
			);
		imageStore(roughness_buffer, ivec2(pixel), roughness_input);

		// normal map input
		float normal_input = dot(blend_multiply(uv, base_surface_texture.rgb, masked_brick_damage, 0.5), vec3(1.0) / 3.0);
		imageStore(rgba32f_buffer, ivec2(pixel), vec4(vec3(normal_input), 1.0));

		// occlusion input
		vec3 blend_top = blend_normal(uv, vec3(mortar_mask), base_surface_texture.rgb, 0.80);
		vec3 blend_bottom = blend_normal(uv, slope_blur_result.rgb, base_surface_texture.rgb, 0.80);
		vec3 occlusion_input = blend_multiply(uv, blend_bottom, blend_top, 0.80);
		float occlusion = occlusion_tone_map(occlusion_input.r);
		imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));
	}

	if (params.stage == 3.0) {
		// vec4 albedo = imageLoad(albedo_buffer, ivec2(pixel));
		// imageStore(output_buffer, ivec2(pixel), albedo);

		// vec4 roughness = imageLoad(roughness_buffer, ivec2(pixel));
		// imageStore(output_buffer, ivec2(pixel), roughness);
		
		vec3 normals = nm_o419916945495(ivec2(pixel), 0.13, params.texture_size);
		vec3 converted_normals = normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
		imageStore(normal_buffer, ivec2(pixel), vec4(converted_normals, 1.0));

		// imageStore(output_buffer, ivec2(pixel), vec4(converted_normals, 1.0));

		// vec4 occlusion = imageLoad(occlusion_buffer, ivec2(pixel));
		// imageStore(output_buffer, ivec2(pixel), occlusion);
	}
}
