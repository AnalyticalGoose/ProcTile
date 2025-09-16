#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform restrict writeonly image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D orm_buffer;

layout(r16f, set = 1, binding = 0) uniform restrict image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 1) uniform restrict image2D r16f_buffer_2;
layout(r16f, set = 1, binding = 2) uniform restrict image2D r16f_buffer_3;

layout(set = 2, binding = 0, std430) buffer restrict readonly Seeds {
    float warp_perlin_seed;
    float grain_perlin_seed;
    float bevel_noise_seed;
    float plank_colour_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer restrict readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 4, binding = 0, std430) buffer restrict readonly GradientColours {
    vec4 gradient_col[];
};

layout(set = 5, binding = 0, std430) buffer restrict readonly GapColour {
	vec4 gap_col;
};

layout(set = 6, binding = 0, std430) buffer restrict readonly NailColour {
    vec4 nail_col;
};

layout(push_constant, std430) uniform restrict readonly Params {
    float plank_pattern;
    float plank_columns;
    float plank_rows;
    float plank_repeat;
    float plank_offset;
    float plank_bevel;
    float nails_disabled; // reversed to UI (nicer to have enabled == true be first in UI, i.e. 0 in the shader)
    float nail_size;
    float nail_edge;
    float nail_margin;
    float grain_perlin_x;
    float grain_perlin_y;
    float grain_perlin_persistence;
    float warp_perlin_x;
    float warp_perlin_y;
    float warp_perlin_persistence;
    float roughness_tone_value;
    float roughness_tone_width;
    float occlusion_tone_width;
    float plank_normal_strength;
    float bevel_normal_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;


#define UNUSED_VAR 0

// S0 - Wood grain
const float warp_perlin_iterations = 10.0;
const float warp_perlin_offset = 0.0;
const float warp_strength = 0.1;
const float warp_x = 0.0;
const float warp_y = 2.0;
const float grain_perlin_iterations = 10.0;
const float grain_perlin_offset = 0.0;

// S1 - Planks
const float bevel_noise_x = 3.0;
const float bevel_noise_y = 10.0;
const float bevel_noise_iterations = 6;
const float bevel_noise_persistence = 0.5;
const float bevel_noise_offset = 0.0;
const float albedo_blend_opacity = 0.5;
const float corner_uv_scale = 1.0;
const float occlusion_blend_opacity = 0.75;
const float occlusion_tone_value = 0.05;
const float roughness_nails_brightness = 0.5;


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

float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

float multiply(float base, float blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
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

vec4 get_corner_bounds(vec2 uv, vec2 plank_min, vec2 plank_max, float gap, float corner) {
    vec2 center = 0.5 * (plank_min + plank_max);
    float gc = gap + (corner);

    vec2 s = vec2(step(center.x, uv.x), step(center.y, uv.y)); // For each axis: 0 if uv < center, else 1
    vec2 corner_pos = mix(plank_min + gap, plank_max - vec2(gc), s);
    corner_pos = round(fract(corner_pos) * params.texture_size) / params.texture_size; // is this needed?
    return vec4(corner_pos, corner, corner);
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

float circle(vec2 uv, float size, float edge) {
    return clamp((1.0 - length(uv * 2.0 - 1.0) / size) / max(edge, 1e-8), 0.0, 1.0);
}

vec2 scale_uv(vec2 uv, float scale) {
    float inv = 1.0 / scale;
    return uv * inv + 0.5 * (1.0 - inv);
}

vec4 gradient_fct(float x) {
    int count = int(gradient_col.length());
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
    } 
    else if (x < 1.0) {
        return mix(col_black, col_white, x);
    }
        return col_white;
}

ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

vec3 sobel_filter(ivec2 coord, float amount, bool gap) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    if (gap == true) {
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

    if (params.stage == 0.0) { // Wood grain texture
        float warp_perlin = fbm_perlin_2d(uv, vec2(params.warp_perlin_x, params.warp_perlin_y), int(warp_perlin_iterations), params.warp_perlin_persistence, warp_perlin_offset, seed.warp_perlin_seed);
        vec2 warped_uv = uv - warp_strength * vec2(warp_x * (warp_perlin - 0.5), - warp_y * warp_perlin - 0.5);
        float grain_perlin = fbm_perlin_2d(warped_uv, vec2(params.grain_perlin_x, params.grain_perlin_y), int(grain_perlin_iterations), params.grain_perlin_persistence, grain_perlin_offset, seed.grain_perlin_seed);
        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(grain_perlin), 1.0));
    }

    if (params.stage == 1.0) { // Plank pattern, ORM & Normal textures
        float _plank_height = 1.0 / params.plank_rows;
        float _roughness_tone_value = 1.0 - params.roughness_tone_value;
        float _roughness_tone_width = 1.0 - params.roughness_tone_width;

        vec4 plank_bounding_rect = get_plank_bounds(uv, vec2(params.plank_columns, params.plank_rows), params.plank_repeat, params.plank_offset, int(params.plank_pattern));
        float bevel_noise = fbm_perlin_2d(uv, vec2(bevel_noise_x, bevel_noise_y), int(bevel_noise_iterations), bevel_noise_persistence, bevel_noise_offset, seed.bevel_noise_seed);
        float pattern = get_plank_pattern(uv, plank_bounding_rect.xy, plank_bounding_rect.zw, UNUSED_VAR, UNUSED_VAR, max(0.001, params.plank_bevel * bevel_noise), _plank_height);

        vec4 plank_fill = round(vec4(fract(plank_bounding_rect.xy), plank_bounding_rect.zw - plank_bounding_rect.xy) * params.texture_size) / params.texture_size;
        
        vec4 corner_bounds = get_corner_bounds(uv, plank_bounding_rect.xy, plank_bounding_rect.zw, (params.plank_bevel / 2) * _plank_height, params.nail_margin * _plank_height);
        vec2 uv_fill = vec2(fract(uv - corner_bounds.xy) / corner_bounds.zw);

        vec2 scaled_uv_fill = scale_uv(uv_fill, (corner_uv_scale / params.nail_margin));
        
        float tiled_circles = 0.0;
        if (params.nails_disabled == 0) {
            tiled_circles = circle(scaled_uv_fill, (params.nail_size * 0.25), params.nail_edge);
        }

        float random_plank_grey = rand(vec2(seed.plank_colour_seed, rand(vec2(plank_fill.x + plank_fill.y, plank_fill.z + plank_fill.w))));
        vec2 plank_uv = fract(uv - vec2(0.5 * (2.0 * random_plank_grey - 1.0), 0.250 * (2.0 * random_plank_grey - 1.0)));
        ivec2 transformed_pixel = ivec2(plank_uv * _texture_size);

        float grain_transformed = imageLoad(r16f_buffer_1, ivec2(transformed_pixel)).r;
        float grain_nails_blend = normal(tiled_circles, grain_transformed, tiled_circles);

        // Albedo
        vec3 grain_colour = gradient_fct(clamp(grain_transformed, 0.01, 0.99)).rgb;
        vec3 gap_colour = map_bw_colours(pattern, vec3(1.0), gap_col.rgb);
        vec3 nail_colour = map_bw_colours(tiled_circles, nail_col.rgb, vec3(0.0));
        vec3 grain_gap_blend = multiply(gap_colour, grain_colour, albedo_blend_opacity);
        vec3 albedo = normal(nail_colour, grain_gap_blend, tiled_circles);
        imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(albedo), 1.0));

        // Occlusion
        float grain_pattern_blend = multiply(pattern, grain_transformed, occlusion_blend_opacity);
        float occlusion = clamp((grain_pattern_blend - occlusion_tone_value) / params.occlusion_tone_width + 0.5, 0.0, 1.0);
        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));

        // Roughness
        float roughness_grain_tones = clamp((grain_pattern_blend - _roughness_tone_value) / _roughness_tone_width + 0.5, 0.0, 1.0);
        float roughness_nails_tones = 1.0 - (tiled_circles * roughness_nails_brightness);
        float roughness = multiply(roughness_grain_tones, roughness_nails_tones, 1.0 - tiled_circles);
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness), 1.0));

        // Metallic
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(tiled_circles), 1.0));
        
        // ORM
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(occlusion, roughness, tiled_circles), 1.0));

        // Normals inputs
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(pattern), 1.0));
        imageStore(r16f_buffer_3, ivec2(pixel), vec4(vec3(grain_nails_blend), 1.0));
    }

    if (params.stage == 2.0) { // Normal maps
        vec3 gap_normals = sobel_filter(ivec2(pixel), params.bevel_normal_strength, true);
        vec3 plank_normals = sobel_filter(ivec2(pixel), params.plank_normal_strength, false);
        vec3 normals_blend = normal_rnm_blend(gap_normals, plank_normals);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = normals_blend * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        } 
        else if (params.normals_format == 1.0) {
            vec3 directx_normals = normals_blend * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }
    }
}