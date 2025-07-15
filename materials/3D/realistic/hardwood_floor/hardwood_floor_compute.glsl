#[compute]
#version 450

// The base wood texture is ported and adapted from 'Procedural Wood texture' dean_the_coder (Twitter: @deanthecoder)
// https://www.shadertoy.com/view/mdy3R1
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
//
// Significant changes have been made from the original reference, primarily around converting it to use 2D UV space and adding tiling

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 1) uniform image2D r16f_buffer_2;
layout(r16f, set = 1, binding = 2) uniform image2D r16f_buffer_3;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float grain_seed_x;
    float grain_seed_y;
    float grain_lines_seed;
    float uv_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly GradientColours {
    vec4 gradient_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly GapColour {
	vec4 gap_col;
};

layout(push_constant, std430) uniform restrict readonly Params {
    float pattern;
    float rows;
    float columns;
    float offset;
    float gap;
    float repeat;
    float grain_base_scale_x;
    float grain_base_scale_y;
    float roughness_value;
    float roughness_width;
    float noise_sobel_strength;
    float gap_sobel_strength;
    float lines_scale_factor;
    float lines_opacity;
    float normals_format;
	float texture_size;
	float stage;
} params;


const float grain_base_highs = 1.0;
const float grain_base_lows = 0.1;

const float grain_detailed_scale = 4.6;
const int grain_detailed_iterations = 8;
const float grain_detailed_size = 2.5;

const float blend_strength = 0.12;

const vec2 dirt_scale = vec2(0.01, 0.15);
const int dirt_iterations = 15;
const float dirt_dimension = 0.26;
const float dirt_size = 2.4;
const float dirt_opacity = 0.2;

const float lines_smooth_min = 0.1;
const float lines_smooth_max = 0.9;
const int lines_iterations = 2;
const float lines_dimension = 2.0;
const float lines_size = 2.5;

const float occlusion_strength = 0.1;


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

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}


vec4 get_plank_bounds(vec2 uv, vec2 grid, float repeat, float row_offset, int pattern) {
    vec2 adjusted_grid = grid * repeat;
    float x_offset = row_offset * step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
    vec2 plank_min, plank_max;

    if (pattern == 0 || pattern == 1 || pattern == 2) { // Running, English, Flemish
        if (pattern == 1) {
            adjusted_grid.x *= 1.0 + step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
        }
        plank_min = floor(vec2(uv.x * adjusted_grid.x - x_offset, uv.y * adjusted_grid.y));
        plank_min.x += x_offset;
        plank_min /= adjusted_grid;

        if (pattern == 2) { // Flemish
            plank_max = plank_min + vec2(1.0) / adjusted_grid;
            float split = (plank_max.x - plank_min.x) / 3.0;
            float is_left = step((uv.x - plank_min.x) / (plank_max.x - plank_min.x), 1.0 / 3.0);
            plank_max.x = mix(plank_max.x, plank_min.x + split, is_left);
            plank_min.x = mix(plank_min.x + split, plank_min.x, is_left);
        } else {
            plank_max = plank_min + vec2(1.0) / adjusted_grid;
        }
        return vec4(plank_min, plank_max);
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

float get_plank_pattern(vec2 uv, vec2 plank_min, vec2 plank_max, float gap, float rounding, float bevel, float plank_scale) {
    gap *= plank_scale;
    rounding *= plank_scale;
    bevel *= plank_scale;
    vec2 plank_size = plank_max - plank_min;
    vec2 plank_center = 0.5 * (plank_min + plank_max);
    vec2 edge_dist = abs(uv - plank_center) - 0.5 * plank_size + vec2(rounding + gap);
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


// START OF Wood Texture - Adapted from https://www.shadertoy.com/view/mdy3R1 / dean_the_coder - CC BY-NC-SA 3.0 //
#define sat(x)	clamp(x, 0.0, 1.0)

float sum_vector(vec2 vec) { 
    return dot(vec, vec2(1.0)); 
}

float remap_01(float value, float input_min, float input_max) {
    return sat((value - input_min) / (input_max - input_min)); 
}

float hash31(vec3 pos) {
	pos = fract(pos * 0.1031);
	pos += dot(pos, pos.yzx + 333.3456);
    return fract(sum_vector(pos.xy) * pos.z);
}

float hash21(vec2 pos) { 
    return hash31(pos.xyx); 
}


// https://www.shadertoy.com/view/lstGRB - Shane / IQ - Transparent 3D Noise (ported to 2D for this shader)
float value_noise_2d(vec2 pos) {
    const vec2 cell_stride = vec2(157, 113);
    vec2 unit_cell_id = floor(pos);
    pos = fract(pos);
    pos = smoothstep(0.0, 1.0, pos);

    vec2 cell_hash = vec2(0.0, cell_stride.y) + dot(unit_cell_id, cell_stride);
    cell_hash = mix(fract(sin(cell_hash) * 43758.545), fract(sin(cell_hash + cell_stride.x) * 43758.545), pos.x);
    return mix(cell_hash.x, cell_hash.y, pos.y);
}

float fbm_2d(vec2 coord, int iterations, float persistence) {
    float noise_sum = 0.0;
    float amplitude = 1.0;
    float total_amplitude = 0.0;
    persistence = clamp(persistence, 0.0, 1.0);

    for (int i = 0; i < iterations; i++) {
        noise_sum += amplitude * value_noise_2d(coord);
        total_amplitude += amplitude;
        amplitude *= persistence;
        coord *= 2.0;
    }
    return noise_sum / total_amplitude;
}

vec2 random_pos_2d(float seed) {
    return vec2(hash21(vec2(seed, 0.0)), hash21(vec2(seed, 1.0))) * 100.0 + 100.0;
}

float fbm_distorted_2d(vec2 coord) {
    coord += (vec2(value_noise_2d(coord + random_pos_2d(seed.grain_seed_x)), 
                   value_noise_2d(coord + random_pos_2d(seed.grain_seed_y))) * 2.0 - 1.0) * 1.12;

    return fbm_2d(coord, 8, 0.5);
}


float fbm_musgrave_2d(vec2 coord, int iterations, float dimension, float size, float seed) {
    float noise_sum  = 0.0;
    float amplitude = 1.0;
    float persistence = pow(size, -dimension);
    
    vec2 seed_offset = vec2(hash21(vec2(seed, 0.0)), hash21(vec2(seed, 1.0))) * seed;
    coord += seed_offset;

    for (int i = 0; i < iterations; i++) {
        float noise_value = value_noise_2d(coord) * 2.0 - 1.0;
        noise_sum  += noise_value * amplitude;
        amplitude *= persistence;
        coord *= size;
    }
    return noise_sum;
}

vec2 fbm_wave_x_2d(vec2 coord) {
    float wave_phase = coord.x * 20.0;
    wave_phase += 0.4 * fbm_2d(coord * 3.0, 3, 3.0);
    return vec2(sin(wave_phase) * 0.5 + 0.5, coord.y);
}
// END OF CC BY-NC-SA 3.0 //



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

vec3 map_bw_colours(float x, vec3 col_white, vec3 col_black) {
  if (x < 0.0) {
    return col_black;
  } else if (x < 1.0) {
    return mix(col_black, col_white, x);
  }
  return col_white;
}


float make_tileable(vec2 uv, float blend_width) {
    // Sample at original UV & wrapped offsets
    float sample_A = imageLoad(r16f_buffer_1, ivec2(uv * params.texture_size)).r;
    float sample_B = imageLoad(r16f_buffer_1, ivec2(fract(uv + vec2(0.5)) * params.texture_size)).r;
    float sample_C = imageLoad(r16f_buffer_1, ivec2(fract(uv + vec2(0.25)) * params.texture_size)).r;

    // Compute a blend coefficient based on distance from the center (0.5, 0.5).
    float dist_from_centre = length(uv - vec2(0.5));
    float coef_AB = sin(1.57079632679 * clamp((dist_from_centre - 0.5 + blend_width) / blend_width, 0.0, 1.0));
    
    // Compute another blend coefficient based on the distance from the middle of the edges.
    float d_left   = length(uv - vec2(0.0, 0.5));
    float d_bottom = length(uv - vec2(0.5, 0.0));
    float d_right  = length(uv - vec2(1.0, 0.5));
    float d_top    = length(uv - vec2(0.5, 1.0));
    float min_edge_dist = min(min(d_left, d_bottom), min(d_right, d_top));
    float coef_ABC = sin(1.57079632679 * clamp((min_edge_dist - blend_width) / blend_width, 0.0, 1.0));
    
    // Blend the first two samples using coef_AB, then blend with the third sample using coef_ABC.
    float mix_AB = mix(sample_A, sample_B, coef_AB);
    return mix(sample_C, mix_AB, coef_ABC);
}

ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

// Generate normals
vec3 sobel_filter(ivec2 coord, float amount, bool noise) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    if (noise == true) {
        // Apply Sobel-like filter to compute gradient
        rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(0, 2))).r;
    }
    else {
        rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_3, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_3, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_3, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_3, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_3, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_3, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_3, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_3, wrap_coord(coord - ivec2(0, 2))).r;
    }

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}

// Reorientated Normal Mapping - Stephen Hill & Colin Barre-Brisebois - https://blog.selfshadow.com/publications/blending-in-detail/
// https://www.shadertoy.com/view/4t2SzR
vec3 normal_rnm_blend(vec3 n1, vec3 n2) {
    n1.z = 1.0 - n1.z;
    n2.z = 1.0 - n2.z;

    // unpacked and rmn blend
    n1 = n1 * vec3(2, 2, 2) + vec3(-1, -1, 0);
    n2 = n2 * vec3(-2, -2, 2) + vec3(1, 1, -1);
    vec3 rnm = n1 * dot(n1, n2) / n1.z - n2;

    // Restore z-axis and repack to to [0,1]
    rnm.z = -rnm.z;
    return rnm * 0.5 + 0.5;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        vec2 grain_base_scale = vec2(params.grain_base_scale_x, params.grain_base_scale_y);
        
        float grain_base = fbm_distorted_2d(uv * grain_base_scale);
        grain_base = mix(grain_base, grain_base_highs, grain_base_lows);

        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(grain_base), 1.0));
    }

    if (params.stage == 1.0) {
        float _roughness_value = params.roughness_value / 100;
        float _roughness_width = params.roughness_width / 100;

        vec4 plank_bounding_rect = get_plank_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.offset, int(params.pattern));
        vec4 plank_fill = round(vec4(fract(plank_bounding_rect.xy), plank_bounding_rect.zw - plank_bounding_rect.xy) * params.texture_size) / params.texture_size;
        vec3 random_plank_colour = mix(vec3(0.0, 0.0, 0.0), rand3(vec2(float((seed.uv_seed)), rand(vec2(rand(plank_fill.xy), rand(plank_fill.zw))))), step(0.0000001, dot(plank_fill.zw, vec2(1.0))));

        vec2 plank_uv = fract(uv - vec2(0.5 * (2.0 * random_plank_colour.r - 1.0), 0.250 * (2.0 * random_plank_colour.r - 1.0)));
        // ivec2 transformed_pixel = ivec2(plank_uv * _texture_size);

        vec2 grain_base_scale = vec2(params.grain_base_scale_x, params.grain_base_scale_y);
        float grain_base = make_tileable(plank_uv, blend_strength);

        float roughness_input = 1.0 - clamp((grain_base - _roughness_value) / _roughness_width + 0.5, 0.0, 1.0);
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness_input), 1.0));

        // Apply FBM Musgrave using the grain base to generate a 'wood grain' texture
        float grain_detailed = mix(fbm_musgrave_2d(vec2(grain_base * grain_detailed_scale), grain_detailed_iterations, 0.0, grain_detailed_size, 0.0), grain_base, 0.85);
        
        // Additional layers for extra flavour with grain lines that follow the general grain direction, and a 'dirt' layer which is just some waves / rings
        float dirt = 1.0 - fbm_musgrave_2d(fbm_wave_x_2d(uv * dirt_scale), dirt_iterations, dirt_dimension, dirt_size, 0.0) * dirt_opacity;
        vec2 lines_scale;
        if (params.grain_base_scale_x > params.grain_base_scale_y) {
            lines_scale = vec2(params.grain_base_scale_x * 80.0, params.grain_base_scale_y * 5.0) * params.lines_scale_factor;
        }
        else {
            lines_scale = vec2(params.grain_base_scale_x * 5.0, params.grain_base_scale_y * 80.0) * params.lines_scale_factor;
        }
        float grain_lines = 1.0 - smoothstep(lines_smooth_min, lines_smooth_max, fbm_musgrave_2d(
            uv * lines_scale, lines_iterations, lines_dimension, lines_size, seed.grain_lines_seed)) * params.lines_opacity;
        
        // Mix extra layers with the detailed base
        grain_detailed *= dirt * grain_lines;
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(grain_detailed), 1.0));

        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
    }

    if (params.stage == 2.0) {
        float _gap = params.gap / 100;

        // Generate base plank pattern
        vec4 plank_bounding_rect = get_plank_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.offset, int(params.pattern));
        float bevel_noise = fbm_perlin_2d(uv, vec2(13.0, 20.0), 4, 0.50, 0.0, 0.0);
        float pattern = get_plank_pattern(uv, plank_bounding_rect.xy, plank_bounding_rect.zw, 0.0, 0.0, max(0.001, _gap * bevel_noise), 1.0 / params.rows);
        imageStore(r16f_buffer_3, ivec2(pixel), vec4(vec3(pattern), 1.0));

        // Store occlusion and roughness maps
        float occlusion_tone_val = 1.0 - occlusion_strength;
        float occlusion_input = occlusion_tone_val + pattern * (1.0 - occlusion_tone_val);
        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion_input), 1.0));
        float roughness_input = imageLoad(roughness_buffer, ivec2(pixel)).r;
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(occlusion_input, roughness_input, 0.0), 1.0));

        // Apply colour to the detailed base texture
        float grain_detailed = imageLoad(r16f_buffer_2, ivec2(pixel)).r;

        vec3 wood_colour = gradient_fct(clamp(grain_detailed, 0.01, 0.99)).rgb;    
        vec3 coloured_pattern = map_bw_colours(pattern, vec3(1.0), gap_col.rgb);
        vec3 albedo_input = multiply(wood_colour, coloured_pattern, 1.0);

        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo_input, 1.0));
    }

    if (params.stage == 3.0) {
        float _noise_sobel_strength = params.noise_sobel_strength / 100;
        float _gap_sobel_strength = params.gap_sobel_strength / 100;

        // Create normal maps
        vec3 noise_normals = sobel_filter(ivec2(pixel), _noise_sobel_strength, true);
        vec3 gap_normals = sobel_filter(ivec2(pixel), _gap_sobel_strength, false);
        vec3 blended_normals = normal_rnm_blend(noise_normals, gap_normals);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = blended_normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        } 
        else if (params.normals_format == 1.0) {
            vec3 directx_normals = blended_normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }
    }
}