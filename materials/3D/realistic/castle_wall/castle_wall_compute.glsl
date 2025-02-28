#[compute]
#version 450

#define f(p, s) dot(fract((p + vec2(s)) / 70.0) - 0.5, fract((p + vec2(s)) / 70.0) - 0.5)
// #define M1 1597334677U     //1719413*929
// #define M2 3812015801U     //140473*2467*11

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D sparse_perlin_buffer;
layout(r16f, set = 1, binding = 1) uniform image2D mortar_perlin_buffer;
layout(r16f, set = 1, binding = 2) uniform image2D brick_dmg_perlin_buffer;
layout(r16f, set = 1, binding = 3) uniform image2D cracks_buffer;
layout(rgba32f, set = 1, binding = 4) uniform image2D rgba32f_buffer;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float perlin_seed;
    float stones_seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float normals_format;
	float texture_size;
	float stage;
} params;


// Noise
const vec2 sparse_perlin_size = vec2(4.0);
const int sparse_perlin_iterations = 8;
const float sparse_perlin_persistence = 0.5;

const vec2 mortar_perlin_size = vec2(8.0, 32.0);
const int mortar_perlin_iterations = 10;
const float mortar_perlin_persistence = 1.0;
const float mortar_perlin_seed = 0.0;

// Brick pattern
const float fill_colour_seed = 0.0;
const float rows = 10.0;
const float columns = 4.0;
const float brick_randomness = 1.0;
const float mortar = 0.05;
const float bevel = 0.05;
const float rounding = 0.12;
const float brick_pattern_seed =  0.841487825;

// Cracks
const vec2 cracks_voronoi_size = vec2(14.0);
const float cracks_voronoi_seed = 0.0;
const float cracks_tone_value = 0.01;
const float cracks_tone_width = 0.01;
const float cracks_intensity = 0.4;

// Stones & Mortar
const vec2 stones_size = vec2(30, 40);
const float stones_scale_variation = 0.3;
const float stones_scale_x = 0.01;
const float stones_scale_y = 0.01;
const float stones_value_variation = 1.0;
vec4 stones_col[3];
float stones_offset[3];
vec4 mortar_col[2];
float mortar_offset[2];
const float stones_opacity = 0.75;
const float mortar_noise_opacity = 0.50;
const float mortar_tone_value = 0.75;
const float mortar_tone_width = 1.00;

// Normal map
const float sobel_strength = 0.50;



float rand(vec2 x) {
    return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
}

vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
		dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
}

// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
vec2 hash_ws2(vec2 x) {
    vec3 x3 = fract(vec3(x.xyx) * vec3(0.1031, 0.1030, 0.0973));
    x3 += dot(x3, x3.yzx + 19.19);
    return fract(vec2((x3.x + x3.y)  *x3.z, (x3.x + x3.z) * x3.y));
}

vec3 rand3(vec2 x) {
    return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
							  dot(x, vec2(3.4562, 17.398)),
                              dot(x, vec2(13.254, 5.867))), vec3(3.14, 3.14, 3.14))) * 43758.5);
}

// vec2 hash_2d(vec2 x) {
//     uvec2 q = uvec2(x * 100);
//     q *= uvec2(M1, M2); 
//     uint n = (q.x ^ q.y) * M1;
//     return vec2(n) * (1.0 / float(0xffffffffU));
// }


// Blending
vec3 normal(vec3 base, vec3 blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
}

float clamped_difference(float base, float blend) {
    return clamp(blend - base, 0.0, 1.0);
}


float blend_overlay(float base, float blend) {
	return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
}

vec3 blend_overlay(vec3 base, vec3 blend) {
	return vec3(blend_overlay(base.r, blend.r), blend_overlay(base.g, blend.g), blend_overlay(base.b, blend.b));
}

vec3 blend_overlay(vec3 base, vec3 blend, float opacity) {
	return (blend_overlay(base, blend) * opacity + base * (1.0 - opacity));
}

float add(float base, float blend, float opacity) {
    return min(base + blend, 1.0) * opacity + base * (1.0 - opacity);
}

float lighten(float base, float blend) {
	return max(blend, base);
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

// Voronoi distances by Inigo Quilez - https://www.shadertoy.com/view/ldl3W8, https://www.youtube.com/c/InigoQuilez, https://iquilezles.org/
// Faster Voronoi Edge Distance by Tomkh - https://www.shadertoy.com/view/llG3zy
vec3 voronoi(vec2 x, vec2 size, float seed) {
    vec2 n = floor(x);
    vec2 f = fract(x);

	vec2 mr;
    float md = 8.0;
    for( int j=-1; j<=1; j++ )
    for( int i=-1; i<=1; i++ )
    {
        vec2 g = vec2(float(i),float(j));
		vec2 o = hash_ws2(vec2(seed) + mod(n + g + size, size));
        vec2 r = g + o - f;
        float d = dot(r,r);

        if( d<md ) {
            md = d;
            mr = r;
        }
    }

    vec2 mg = step(.5,f) - 1.;
    md = 8.0;
    for( int j=-1; j<=2; j++ )
    for( int i=-1; i<=2; i++ )
    {
        vec2 g = mg + vec2(float(i),float(j));
		vec2 o = hash_ws2(vec2(seed) + mod(n + g + size, size));
		vec2 r = g + o - f;

        if( dot(mr-r,mr-r)> 0.00001 ) // skip the same cell
        md = min( md, dot( 0.5*(mr+r), normalize(r-mr) ) );
    }

    return vec3( md, mr );
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

float stone(vec2 uv, float seed) {
    // Pseudo cellular noise - adapted from 'One Tweet Cellular Pattern - Shane. https://www.shadertoy.com/view/MdKXDD
    vec2 cell_px = gl_GlobalInvocationID.xy * 1.4;
    mat2 m = mat2(5, -5, 5, 5) * 0.1;
    float _seed = seed;
    float d = min(min(f(cell_px, _seed), f(cell_px * m, -_seed)), f(cell_px * m * m, _seed * 2.0));
    float stones_cellular = 1.0 - sqrt(d) / 0.6;

    // Stone shape
    vec2 center = uv - vec2(0.5);
    float circle = pow(1.0 - smoothstep(0.0, 0.16, dot(center, center)), 0.2);
    return clamped_difference(stones_cellular, circle);
}

vec2 tile_stones(vec2 uv, vec2 tile, vec2 seed_offset) {
    float max_contribution = 0.0;
    float final_colour = 0.0;
    
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            // Compute a temporary tile-space position.
            vec2 pos = uv * tile + vec2(float(dx), float(dy));
            pos = fract((floor(mod(pos, tile)) + 0.5) / tile) - 0.5;
            
            vec2 rand_seed = rand2(pos + seed_offset);
            float rand_colour = rand(rand_seed);
            
            // Random offset variation & compute local UV relative to tile.
            pos = fract(pos + 1.0 * rand_seed / tile);
            vec2 pv = fract(uv - pos) - 0.5;
            
            float angle = (rand_seed.x * 2.0 - 1.0) * 3.14159;
            mat2 rot_mat = mat2(cos(angle), sin(angle), -sin(angle), cos(angle));
            pv = rot_mat * pv;
            pv *= (rand_seed.y - 0.5) * 2.0 * stones_scale_variation + 1.0;
            pv /= vec2(stones_scale_x, stones_scale_y);
            pv += 0.5;
            
            // Skip if coord is out of bounds.
            if (any(lessThan(pv, vec2(0.0))) || any(greaterThan(pv, vec2(1.0))))
                continue;
            
            pv = clamp(pv, vec2(0.0), vec2(1.0));
            
            // Evaluate the stone pattern at this instance.
            float tile_value = stone(pv, rand_seed.x) * (1.0 - stones_value_variation * rand_seed.x);
            
            // Keep the instance if its contribution is highest so far.
            if (tile_value > max_contribution) {
                max_contribution = tile_value;
                final_colour = rand_colour;
            }
        }
    }
    
    return vec2(final_colour, max_contribution);
}


vec4 gradient_fct(float x, int gradient) {

    if (gradient == 0) { // stones colour
        int count = int(stones_col.length());
        if (x < stones_offset[0]) {
            return stones_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < stones_offset[i]) {
                float range = stones_offset[i] - stones_offset[i - 1];
                float factor = (x - stones_offset[i - 1]) / range;
                return mix(stones_col[i - 1], stones_col[i], factor);
            }
        }
        return stones_col[count - 1];
    }

    if (gradient == 1) { // mortar colour
        int count = int(mortar_col.length());
        if (x < mortar_offset[0]) {
            return mortar_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < mortar_offset[i]) {
                float range = mortar_offset[i] - mortar_offset[i - 1];
                float factor = (x - mortar_offset[i - 1]) / range;
                return mix(mortar_col[i - 1], mortar_col[i], factor);
            }
        }
        return mortar_col[count - 1];
    }
}

float map_bw_colours(float x, float limit) {
    if (x < limit) {
        return mix(1.0, 0.0, (x - limit) / -limit);
    }
    return 1.0;
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

    vec2 crack_warped_uv;

    if (params.stage == 0.0) { // Generate noise
        // General use sparse perlin
        float sparse_perlin = fbm_perlin_2d(uv, sparse_perlin_size, sparse_perlin_iterations, sparse_perlin_persistence, 0.0, seed.perlin_seed);
        imageStore(sparse_perlin_buffer, ivec2(pixel), vec4(vec3(sparse_perlin), 1.0));

        // Mortar texture perlin
        float mortar_perlin = fbm_perlin_2d(uv, mortar_perlin_size, mortar_perlin_iterations, mortar_perlin_persistence, 0.0, mortar_perlin_seed);
        mortar_perlin = clamp((mortar_perlin - 0.95) / 1.0 + 0.5, 0.0, 1.0);
        imageStore(mortar_perlin_buffer, ivec2(pixel), vec4(vec3(mortar_perlin), 1.0));
        
        // Brick shape perlin 
        float brick_damage_perlin = fbm_perlin_2d(uv, vec2(6.0, 20.0), 4, 0.5, 0.0, 0.0);
        imageStore(brick_dmg_perlin_buffer, ivec2(pixel), vec4(vec3(brick_damage_perlin), 1.0));

        // Cracks voronoi
        crack_warped_uv = uv -= vec2(0.04 * (2.0 * sparse_perlin - 1.0));
        vec3 cracks_voronoi = voronoi(cracks_voronoi_size.x * crack_warped_uv, cracks_voronoi_size, cracks_voronoi_seed);
        float cracks = clamp((cracks_voronoi.r - cracks_tone_value) / cracks_tone_width + 0.5, 0.0, 1.0);
        imageStore(cracks_buffer, ivec2(pixel), vec4(vec3(cracks), 1.0));
    }

    if (params.stage == 1.0) { // Mortar
        stones_col[0] = vec4(0.56, 0.56, 0.56, 1.0);
        stones_col[1] = vec4(0.97, 0.91, 0.68, 1.0);
        stones_col[2] = vec4(1.00, 0.83, 0.64, 1.0);
        stones_offset[0] = 0.0;
        stones_offset[1] = 0.5;
        stones_offset[2] = 1.0;

        // Generate stone pattern and colour
        vec2 stones = tile_stones(uv, stones_size, vec2(seed.stones_seed));
        vec4 stones_colour = gradient_fct(stones.x, 0);

        mortar_col[0] = vec4(0.37, 0.37, 0.31, 1.0);
        mortar_col[1] = vec4(0.54, 0.52, 0.47, 1.0);
        mortar_offset[0] = 0.0;
        mortar_offset[1] = 1.0;

        // Colour mortar noise and blend with stones
        float mortar_perlin = imageLoad(mortar_perlin_buffer, ivec2(pixel)).r;
        vec4 mortar_colour = gradient_fct(mortar_perlin, 1);
        float mortar_blend_opacity = stones.y * stones_opacity;
        vec3 mortar_blend = blend_overlay(mortar_colour.rgb, stones_colour.rgb, mortar_blend_opacity);
        
        // Generate mortar roughness
        float sparse_perlin = imageLoad(sparse_perlin_buffer, ivec2(pixel)).r;
        float mortar_roughness_blend = add(mortar_perlin, sparse_perlin, 1.0);
        mortar_roughness_blend = clamp((mortar_roughness_blend - mortar_tone_value) / mortar_tone_width + 0.5, 0.0, 1.0);
        float mortar_roughness = add(mortar_roughness_blend, stones.y, 0.5);

        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(mortar_roughness), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(mortar_blend, 1.0));
    }    
        
    if (params.stage == 2.0) { // can reuse morter_perlin_buffer
        float brick_damage_perlin = imageLoad(brick_dmg_perlin_buffer, ivec2(pixel)).r;

        // Brick pattern
        vec4 brick_fill;
        vec2 brick_damage_uv = uv -= vec2(0.015 * (2.0 * brick_damage_perlin - 1.0));
        float brick_pattern = skewed_uneven_bricks(brick_damage_uv, vec2(columns, rows), brick_randomness, mortar, bevel, rounding, brick_pattern_seed, brick_fill);
        vec3 random_brick_colour = mix(vec3(0.0, 0.0, 0.0), rand3(vec2(float((fill_colour_seed)), rand(vec2(rand(brick_fill.xy), rand(brick_fill.zw))))), step(0.0000001, dot(brick_fill.zw, vec2(1.0))));

        // Cracks pattern, loaded into brick pattern transformed UVs
        vec2 crack_brick_offset = vec2(0.5 * (2.0 * brick_fill.r - 1.0), 0.250 * (2.0 * brick_fill.g - 1.0));
        vec2 crack_brick_uv = fract(uv + crack_warped_uv - crack_brick_offset);
        ivec2 transformed_pixel = ivec2(crack_brick_uv * _texture_size);
        float cracks = imageLoad(cracks_buffer, transformed_pixel).r;

        // Blended to make sparse cracks pattern
        float cracks_mask = map_bw_colours(brick_damage_perlin, cracks_intensity);
        float cracks_lightened = lighten(cracks_mask, cracks);



        // imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(cracks_lightened), 1.0));
        imageStore(albedo_buffer, ivec2(pixel), brick_fill);
	}
}