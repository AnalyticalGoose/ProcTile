#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D rgba32f_buffer;

layout(push_constant, std430) uniform restrict readonly Params {
    float rows;
    float columns;
    float randomness;
    float mortar;
    float bevel;
    float rounding;
    float perlin_scale_x;
    float perlin_scale_y;
    float white_noise_size;
    float noise_lightness;
    float normals_format;
	float texture_size;
	float stage;
} params;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float brick_pattern_seed;
    float brick_shape_seed;
    float brick_colour_seed;
    float white_noise_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly StoneOffsets {
    float stone_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly StoneColours {
    vec4 stone_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly MortarColour {
    vec4 mortar_col;
};

const int perlin_iterations = 4;
const float brick_blend_opacity = 0.35;


// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
float hash_ws(vec2 x, float seed) {
    vec3 x3 = fract(vec3(x.xyx) * (0.1031 + seed));
    x3 += dot(x3, x3.yzx + 33.33);
    return fract((x3.x + x3.y) * x3.z);
}

float rand(vec2 p) {
    return fract(cos(mod(dot(p, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
}

vec2 rand2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+19.19);
    return fract((p3.xx+p3.yz) * p3.zy);
}

float white_noise(vec2 uv, float size, float seed) {
	uv = floor(uv / size) + vec2(0.5);
	return hash_ws(uv, seed);
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
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


// Returns the intersection point of two lines (each encoded as a vec4)
vec2 get_line_intersection(vec4 line1, vec4 line2) {
    vec2 A = line1.xy, B = line1.zw;
    vec2 C = line2.xy, D = line2.zw;
    vec2 b = B - A, d = D - C;
    float dotperp = b.x * d.y - b.y * d.x;
    vec2 c = C - A;
    float t = (c.x * d.y - c.y * d.x) / dotperp;
    return A + t * b;
}

// Inverts a bilinear interpolation defined by the four corner points.
vec2 inverted_bilinear(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
    vec2 e = b - a, f = d - a, g = a - b + c - d, h = p - a;
    float k2 = g.x * f.y - g.y * f.x;
    float k1 = e.x * f.y - e.y * f.x + h.x * g.y - h.y * g.x; 
    float k0 = h.x * e.y - h.y * e.x;
    k2 /= k0; k1 /= k0; k0 = 1.0;
    
    vec2 res;
    if (abs(k2) < 0.001) {
        res = vec2((h.x * k1 + f.x) / (e.x * k1 - g.x), -1.0 / k1);
    } else {
        float disc = k1 * k1 - 4.0 * k2;
        if (disc < 0.0) return vec2(-1.0);
        disc = sqrt(disc);
        float ik2 = 0.5 / k2;
        float v = (-k1 - disc) * ik2;
        float u = (h.x - f.x * v) / (e.x + g.x * v);
        if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) {
            v = (-k1 + disc) * ik2;
            u = (h.x - f.x * v) / (e.x + g.x * v);
        }
        res = vec2(u, v);
    }
    return res;
}

// Returns true if point c is to the left of the line defined by a->b.
bool point_left_of_line(vec4 line, vec2 c) {
    vec2 a = line.xy, b = line.zw;
    return ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) > 0.0;
}

// Returns a perturbed cut position within the cell.
vec2 skewed_uneven_cut(vec2 x, vec2 size, float randomness) {
    const float grid_size = 4096.0;
    randomness = abs(randomness) < 0.001 ? 0.001 : randomness;
    return 0.5 + (rand2(round(mod(x, size) * grid_size) / grid_size) - 0.5) * randomness;
}


// A port of Material Maker's 'Skewed Uneven Bricks' node with some significant optimisations for brevity.
// https://github.com/RodZill4/material-maker/blob/master/addons/material_maker/nodes/skewed_uneven_bricks.mmg
float skewed_uneven_bricks(vec2 uv, vec2 size, float randomness, float mortar, float bevel, float rounding, float seed, out vec4 brick_fill) {
    const float grid_size = params.texture_size.x;
    vec2 cell_id = floor(uv * size);
    vec4 base = cell_id.xyxy;
    
    vec2 cuts[9];
    cuts[0] = skewed_uneven_cut(cell_id + seed, size, randomness);                   // current
    cuts[1] = skewed_uneven_cut(cell_id + vec2(0.0, -1.0) + seed, size, randomness); // top
    cuts[2] = skewed_uneven_cut(cell_id + vec2(1.0, -1.0) + seed, size, randomness); // top_right
    cuts[3] = skewed_uneven_cut(cell_id + vec2(1.0, 0.0) + seed, size, randomness);  // right
    cuts[4] = skewed_uneven_cut(cell_id + vec2(0.0, 1.0) + seed, size, randomness);  // bottom
    cuts[5] = skewed_uneven_cut(cell_id + vec2(1.0, 1.0) + seed, size, randomness);  // bottom_right
    cuts[6] = skewed_uneven_cut(cell_id + vec2(-1.0, 0.0) + seed, size, randomness); // left
    cuts[7] = skewed_uneven_cut(cell_id + vec2(-1.0, 1.0) + seed, size, randomness); // bottom_left
    cuts[8] = skewed_uneven_cut(cell_id + vec2(-1.0, -1.0) + seed, size, randomness);// top_left
    
    bool odd_cell = mod(cell_id.x + cell_id.y, 2.0) > 0.5;
    vec4 lines[9];
    vec2 a, b, c, d;
    
    if (odd_cell) { // Odd cell lines
        lines[0] = (base + vec4(-1.0, cuts[0].x, 2.0, cuts[0].y)) / size.xyxy;
        lines[1] = (base + vec4(cuts[1].x, -2.0, cuts[1].y, 1.0)) / size.xyxy;
        lines[2] = (base + vec4(0.0, -1.0 + cuts[2].x, 3.0, -1.0 + cuts[2].y)) / size.xyxy;
        lines[3] = (base + vec4(1.0 + cuts[3].x, -1.0, 1.0 + cuts[3].y, 2.0)) / size.xyxy;
        lines[4] = (base + vec4(cuts[4].x, 0.0, cuts[4].y, 3.0)) / size.xyxy;
        lines[5] = (base + vec4(0.0, 1.0 + cuts[5].x, 3.0, 1.0 + cuts[5].y)) / size.xyxy;
        lines[6] = (base + vec4(-1.0 + cuts[6].x, -1.0, -1.0 + cuts[6].y, 2.0)) / size.xyxy;
        lines[7] = (base + vec4(-2.0, 1.0 + cuts[7].x, 1.0, 1.0 + cuts[7].y)) / size.xyxy;
        lines[8] = (base + vec4(-2.0, -1.0 + cuts[8].x, 1.0, -1.0 + cuts[8].y)) / size.xyxy;
        
        if (!point_left_of_line(lines[0], uv)) {
            a = point_left_of_line(lines[1], uv) ? get_line_intersection(lines[8], lines[6]) : get_line_intersection(lines[2], lines[1]);
            b = point_left_of_line(lines[1], uv) ? get_line_intersection(lines[1], lines[8]) : get_line_intersection(lines[3], lines[2]);
            c = point_left_of_line(lines[1], uv) ? get_line_intersection(lines[0], lines[1]) : get_line_intersection(lines[0], lines[3]);
            d = point_left_of_line(lines[1], uv) ? get_line_intersection(lines[0], lines[6]) : get_line_intersection(lines[0], lines[1]);
        } else {
            a = !point_left_of_line(lines[4], uv) ? get_line_intersection(lines[0], lines[4]) : get_line_intersection(lines[6], lines[0]);
            b = !point_left_of_line(lines[4], uv) ? get_line_intersection(lines[0], lines[3]) : get_line_intersection(lines[4], lines[0]);
            c = !point_left_of_line(lines[4], uv) ? get_line_intersection(lines[5], lines[3]) : get_line_intersection(lines[4], lines[7]);
            d = !point_left_of_line(lines[4], uv) ? get_line_intersection(lines[5], lines[4]) : get_line_intersection(lines[6], lines[7]);
        }
    } else { // Even cell lines
        lines[0] = (base + vec4(cuts[0].x, -1.0, cuts[0].y, 2.0)) / size.xyxy;
        lines[1] = (base + vec4(-1.0, -1.0 + cuts[1].x, 2.0, -1.0 + cuts[1].y)) / size.xyxy;
        lines[2] = (base + vec4(1.0 + cuts[2].x, -2.0, 1.0 + cuts[2].y, 1.0)) / size.xyxy;
        lines[3] = (base + vec4(0.0, cuts[3].x, 3.0, cuts[3].y)) / size.xyxy;
        lines[4] = (base + vec4(-1.0, 1.0 + cuts[4].x, 2.0, 1.0 + cuts[4].y)) / size.xyxy;
        lines[5] = (base + vec4(1.0 + cuts[5].x, 0.0, 1.0 + cuts[5].y, 3.0)) / size.xyxy;
        lines[6] = (base + vec4(-2.0, cuts[6].x, 1.0, cuts[6].y)) / size.xyxy;
        lines[7] = (base + vec4(-1.0 + cuts[7].x, 0.0, -1.0 + cuts[7].y, 3.0)) / size.xyxy;
        lines[8] = (base + vec4(-1.0 + cuts[8].x, -2.0, -1.0 + cuts[8].y, 1.0)) / size.xyxy;
        
        if (point_left_of_line(lines[0], uv)) {
            a = !point_left_of_line(lines[6], uv) ? get_line_intersection(lines[8], lines[1]) : get_line_intersection(lines[7], lines[6]);
            b = !point_left_of_line(lines[6], uv) ? get_line_intersection(lines[0], lines[1]) : get_line_intersection(lines[0], lines[6]);
            c = !point_left_of_line(lines[6], uv) ? get_line_intersection(lines[0], lines[6]) : get_line_intersection(lines[0], lines[4]);
            d = !point_left_of_line(lines[6], uv) ? get_line_intersection(lines[8], lines[6]) : get_line_intersection(lines[7], lines[4]);
        } else {
            a = !point_left_of_line(lines[3], uv) ? get_line_intersection(lines[0], lines[1]) : get_line_intersection(lines[0], lines[3]);
            b = !point_left_of_line(lines[3], uv) ? get_line_intersection(lines[2], lines[1]) : get_line_intersection(lines[5], lines[3]);
            c = !point_left_of_line(lines[3], uv) ? get_line_intersection(lines[2], lines[3]) : get_line_intersection(lines[5], lines[4]);
            d = !point_left_of_line(lines[3], uv) ? get_line_intersection(lines[0], lines[3]) : get_line_intersection(lines[0], lines[4]);
        }
    }
    
    vec2 brick_uv = inverted_bilinear(uv, a, b, c, d);
    vec4 rect = vec4(min(min(a, b), min(c, d)), max(max(a, b), max(c, d)));
    brick_fill = round(vec4(fract(rect.xy), rect.zw - rect.xy) * grid_size) / grid_size;
    
    float max_size = max(size.x, size.y);
    bevel /= (max_size / 2.0);
    mortar /= (max_size / 2.0);
    vec2 dist = (min(brick_uv, 1.0 - brick_uv) * -2.0) * brick_fill.zw + vec2(rounding + mortar);
    float brick = length(max(dist, vec2(0.0))) + min(max(dist.x, dist.y), 0.0) - rounding;
    
    return clamp(-brick / bevel, 0.0, 1.0);
}

vec4 gradient_fct(float x) {
    int count = int(stone_col.length()); // Use the number of offsets dynamically
    if (x < stone_offsets[0]) {
        return stone_col[0];
    }

    for (int i = 1; i < count; i++) {
        if (x < stone_offsets[i]) {
            float range = stone_offsets[i] - stone_offsets[i - 1];
            float factor = (x - stone_offsets[i - 1]) / range;
            return mix(stone_col[i - 1], stone_col[i], factor);
        }
    }

    return stone_col[count - 1];
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        float _white_noise_size = params.white_noise_size * 4;

        float perlin = fbm_perlin_2d(uv, vec2(params.perlin_scale_x, params.perlin_scale_y), perlin_iterations, 0.5, 0.0, seed.brick_shape_seed);
        vec2 warped_uv = uv -= vec2(0.03 * (2.0 * perlin - 1.0));

        vec4 brick_fill;
        float pattern = skewed_uneven_bricks(uv, vec2(params.columns, params.rows), params.randomness, params.mortar, params.bevel, params.rounding, seed.brick_pattern_seed, brick_fill);
        float random_brick_gray = mix(0.0, rand(vec2(float((seed.brick_colour_seed)), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

        vec3 brick_colour = gradient_fct(random_brick_gray).rgb;
        vec3 brick_mortar_colour = normal(brick_colour, mortar_col.rgb, pattern);
        float white_noise = white_noise(pixel, _white_noise_size, seed.white_noise_seed);
        float lightened_noise = params.noise_lightness + white_noise * (1.0 - params.noise_lightness);

        vec3 albedo = multiply(vec3(lightened_noise), brick_mortar_colour, brick_blend_opacity);
        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }
}