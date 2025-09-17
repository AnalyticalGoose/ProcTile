#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform restrict image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D orm_buffer;

layout(rgba32f, set = 1, binding = 0) uniform restrict image2D rgba32f_buffer_1;
layout(rgba32f, set = 1, binding = 1) uniform restrict image2D rgba32f_buffer_2;

layout(push_constant, std430) uniform restrict readonly Params {
    float pattern;
    float rows;
    float columns;
    float offset;
    float grout;
    float repeat;
    float micro_perlin_scale;
    float macro_perlin_scale;
    float tile_roughness;
    float micro_perlin_persistence;
    float macro_perlin_persistence;
    float perlin_blend_bias;
    float noise_sobel_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;

layout(set = 2, binding = 0, std430) buffer restrict readonly Seeds {
	float micro_perlin_seed;
	float macro_perlin_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer restrict readonly Tile {
    vec4 tile_col;
};

layout(set = 4, binding = 0, std430) buffer restrict readonly Grout {
    vec4 grout_col;
};


const int micro_perlin_iterations = 10;
const int macro_perlin_iterations = 2;
const float bevel = 0.0;
const float rounding = 0.0;
const float tones_input_min = 0.00;
const float tones_input_max = 1.00;
const float tones_output_min = 0.50;
const float tones_output_max = 0.60;
const float grout_sobel_strength = 1.00;


uint murmurHash12(uvec2 src) {
    const uint M = 0x5bd1e995u;
    uint h = 1190494759u;
    src *= M; src ^= src>>24u; src *= M;
    h *= M; h ^= src.x; h *= M; h ^= src.y;
    h ^= h>>13u; h *= M; h ^= h>>15u;
    return h;
}

float hash12(vec2 src) {
    uint h = murmurHash12(floatBitsToUint(src));
    return uintBitsToFloat(h & 0x007fffffu | 0x3f800000u) - 1.0;
}

// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
vec2 hash_ws2(vec2 x) {
    vec3 x3 = fract(vec3(x.xyx) * vec3(0.1031, 0.1030, 0.0973));
    x3 += dot(x3, x3.yzx + 19.19);
    return fract(vec2((x3.x + x3.y)  *x3.z, (x3.x + x3.z) * x3.y));
}


float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}


float perlin_noise_2d(vec2 coord, vec2 size, float offset, float seed) {
    vec2 o = floor(coord) + hash_ws2(vec2(seed, 1.0 - seed)) + size;
    vec2 f = fract(coord);

    float a[4];
    a[0] = hash12(mod(o, size)) * 6.28318530718 + offset * 6.28318530718;
    a[1] = hash12(mod(o + vec2(0.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[2] = hash12(mod(o + vec2(1.0, 0.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[3] = hash12(mod(o + vec2(1.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;

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

vec4 get_tile_bounds(vec2 uv, vec2 grid, float repeat, float row_offset, int pattern) {
    vec2 adjusted_grid = grid * repeat;
    float x_offset = row_offset * step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
    vec2 tile_min, tile_max;

    if (pattern == 0 || pattern == 1 || pattern == 2) { // Running, English, Flemish
        if (pattern == 1) {
            adjusted_grid.x *= 1.0 + step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
        }
        tile_min = floor(vec2(uv.x * adjusted_grid.x - x_offset, uv.y * adjusted_grid.y));
        tile_min.x += x_offset;
        tile_min /= adjusted_grid;

        if (pattern == 2) { // Flemish
            tile_max = tile_min + vec2(1.0) / adjusted_grid;
            float split = (tile_max.x - tile_min.x) / 3.0;
            float is_left = step((uv.x - tile_min.x) / (tile_max.x - tile_min.x), 1.0 / 3.0);
            tile_max.x = mix(tile_max.x, tile_min.x + split, is_left);
            tile_min.x = mix(tile_min.x + split, tile_min.x, is_left);
        } else {
            tile_max = tile_min + vec2(1.0) / adjusted_grid;
        }
        return vec4(tile_min, tile_max);
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

float get_tile_pattern(vec2 uv, vec2 tile_min, vec2 tile_max, float grout, float rounding, float bevel, float tile_scale) {
    grout *= tile_scale;
    rounding *= tile_scale;
    bevel *= tile_scale;
    vec2 tile_size = tile_max - tile_min;
    vec2 tile_center = 0.5 * (tile_min + tile_max);
    vec2 edge_dist = abs(uv - tile_center) - 0.5 * tile_size + vec2(rounding + grout);
    float distance = length(max(edge_dist, vec2(0))) + min(max(edge_dist.x, edge_dist.y), 0.0) - rounding;
    return clamp(-distance / bevel, 0.0, 1.0);
}

vec4 map_bw_colours(float x, vec4 col_white, vec4 col_black) {
    if (x < 1.0) {
        return col_black;
    }
    return col_white;
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
        rv += vec2(1.0, -1.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(rgba32f_buffer_1, wrap_coord(coord - ivec2(0, 2))).r;
    }

    else if (noise == false) {
        rv += vec2(1.0, -1.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(rgba32f_buffer_2, wrap_coord(coord - ivec2(0, 2))).r;
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
        float _micro_persis = params.micro_perlin_persistence / 100;
        float _macro_persis = params.macro_perlin_persistence / 100;
        float _noise_blend_bias = params.perlin_blend_bias / 100;

        // Generate perlin for macro and micro surface inperfections and texture. Blend both and then tone map
        float micro_perlin = fbm_2d_perlin(uv, vec2(params.micro_perlin_scale), micro_perlin_iterations, _micro_persis, 0.00, seed.micro_perlin_seed);
        float macro_perlin = fbm_2d_perlin(uv, vec2(params.macro_perlin_scale), macro_perlin_iterations, _macro_persis, 0.0, seed.macro_perlin_seed);
        float blended_perlin = normal(micro_perlin, macro_perlin, _noise_blend_bias);
        float normal_input = tones_output_min + (blended_perlin - tones_input_min) * (tones_output_max - tones_output_min) / (tones_input_max - tones_input_min);
        imageStore(rgba32f_buffer_1, ivec2(pixel), vec4(vec3(normal_input), 1.0));

        float _grout = params.grout / 100;
        vec4 tile_bounding_rect = get_tile_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.offset, int(params.pattern));
        float pattern = get_tile_pattern(uv, tile_bounding_rect.xy, tile_bounding_rect.zw, _grout, rounding, bevel, 1.0 / params.rows);
        imageStore(rgba32f_buffer_2, ivec2(pixel), vec4(vec3(pattern), 1.0));

        vec4 occlusion = map_bw_colours(pattern, vec4(1.0), vec4(vec3(0.6), 1.0));
        imageStore(occlusion_buffer, ivec2(pixel), occlusion);

        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
    }

    if (params.stage == 1.0) {
        float _grout = params.grout / 100;
        float _roughness = params.tile_roughness / 100;

        vec3 noise_normals = sobel_filter(ivec2(pixel), params.noise_sobel_strength, true);
        vec3 grout_normals = sobel_filter(ivec2(pixel), grout_sobel_strength, false);
        vec3 blended_normals = normal_rnm_blend(noise_normals, grout_normals);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = blended_normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        } 
        else if (params.normals_format == 1.0) {
            vec3 directx_normals = blended_normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }
        
        vec4 tile_bounding_rect = get_tile_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.offset, int(params.pattern));
        float dilated_pattern = get_tile_pattern(uv, tile_bounding_rect.xy, tile_bounding_rect.zw, _grout * 1.1, rounding, bevel, 1.0 / params.rows);
        vec4 tile_colour = map_bw_colours(dilated_pattern, tile_col, grout_col);
        imageStore(albedo_buffer, ivec2(pixel), tile_colour);

        vec4 tile_roughness = map_bw_colours(dilated_pattern, vec4(_roughness), vec4(1.00));
        imageStore(roughness_buffer, ivec2(pixel), tile_roughness);
    }

    if (params.stage == 2.0) {
        vec4 occlusion = imageLoad(occlusion_buffer, ivec2(pixel));
        vec4 roughness = imageLoad(roughness_buffer, ivec2(pixel));
        imageStore(orm_buffer, ivec2(pixel), vec4(occlusion.r, roughness.r, 0.0, 1.0));
    }
}