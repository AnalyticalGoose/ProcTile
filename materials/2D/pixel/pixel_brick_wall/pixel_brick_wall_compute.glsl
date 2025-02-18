#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D rgba32f_buffer_1; // Normals will be generated in the near future for those who wish to use them in pseudo 2D.

layout(push_constant, std430) uniform restrict readonly Params {
    float pattern;
	float rows;
	float columns;
	float row_offset;
	float mortar;
	float bevel;
	float rounding;
	float repeat;
    float white_noise_size;
    float noise_lightness;
    float normal;
    float texture_size;
	float stage;
} params;


const float brick_blend_opacity = 0.5;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float brick_colour_seed;
    float white_noise_seed;
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


float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
}

vec4 get_brick_bounds(vec2 uv, vec2 grid, float repeat, float row_offset, int pattern) {
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    
    vec2 adjusted_grid = grid * repeat;
    float row = floor(uv.y * adjusted_grid.y);
    float x_offset = row_offset * mod(row, 2.0);
    // float x_offset = row_offset * step(0.5, fract(uv.y * adjusted_grid.y * 0.5));
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

// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
float hash_ws(vec2 x, float seed) {
    vec3 x3 = fract(vec3(x.xyx) * (0.1031 + seed));
    x3 += dot(x3, x3.yzx + 33.33);
    return fract((x3.x + x3.y) * x3.z);
}

float white_noise(vec2 uv, float size, float seed) {
	uv = floor(uv / size) + vec2(0.5);
	return hash_ws(uv, seed);
}

void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
		float _bevel = params.bevel / 100;
		float _mortar = params.mortar / 100;
		float _rounding = params.rounding / 100;
        float _white_noise_size = params.white_noise_size * 4;

		vec4 brick_bounding_rect = get_brick_bounds(uv, vec2(params.columns, params.rows), params.repeat, params.row_offset, int(params.pattern));
		float pattern = get_brick_pattern(uv, brick_bounding_rect.xy, brick_bounding_rect.zw, _mortar, _rounding, _bevel, 1.0 / params.rows);

        vec4 brick_fill = round(vec4(fract(brick_bounding_rect.xy), brick_bounding_rect.zw - brick_bounding_rect.xy) * params.texture_size) / params.texture_size;
        float random_brick_gray = mix(0.0, rand(vec2(float((seed.brick_colour_seed)), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

        vec4 gradient_brick_colour = gradient_fct(random_brick_gray);

        float white_noise = white_noise(pixel, _white_noise_size, seed.white_noise_seed);
        float lightened_noise = params.noise_lightness + white_noise * (1.0 - params.noise_lightness);

        vec3 brick_blend = multiply(vec3(lightened_noise), gradient_brick_colour.rgb, brick_blend_opacity);

        vec3 albedo = normal(brick_blend, mortar_col.rgb, pattern);

		imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }
}