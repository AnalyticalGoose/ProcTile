#[compute]
#version 450

#define f(p, s) dot(fract((p + vec2(s)) / 70.0) - 0.5, fract((p + vec2(s)) / 70.0) - 0.5)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

// Reusing buffers was giving me Ebola, so... fuck it, everyone gets their own buffer.
// Condensing these is a problem for future me.
layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer_0;
layout(r16f, set = 1, binding = 1) uniform image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 2) uniform image2D r16f_buffer_2;
layout(r16f, set = 1, binding = 3) uniform image2D r16f_buffer_3;
layout(r16f, set = 1, binding = 4) uniform image2D r16f_buffer_4;
layout(r16f, set = 1, binding = 5) uniform image2D r16f_buffer_5;
layout(r16f, set = 1, binding = 6) uniform image2D r16f_buffer_6;
layout(r16f, set = 1, binding = 7) uniform image2D r16f_buffer_7;
layout(rgba32f, set = 1, binding = 8) uniform image2D rgba32f_buffer; 
layout(rgba32f, set = 1, binding = 9) uniform image2D rgba32f_buffer_2;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float brick_pattern_seed;
    float perlin_seed;
    float stones_seed;
    float mortar_perlin_seed;
    float cracks_voronoi_seed;

} seed;

layout(set = 3, binding = 0, std430) buffer readonly StoneOffsets {
    float stone_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly StoneColours {
    vec4 stone_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly AggregateOffsets {
    float aggregate_offsets[];
};

layout(set = 6, binding = 0, std430) buffer readonly AggregateColours {
    vec4 aggregate_col[];
};

layout(set = 7, binding = 0, std430) buffer readonly MortarOffsets {
    float mortar_offsets[];
};

layout(set = 8, binding = 0, std430) buffer readonly MortarColours {
    vec4 mortar_col[];
};

layout(set = 9, binding = 0, std430) buffer readonly StoneBaseColour {
    vec4 stone_base_col;
};


layout(push_constant, std430) uniform restrict readonly Params {
	float rows;
	float columns;
    float brick_randomness;
    float mortar;
	float bevel;
	float rounding;
    float stone_edge_slope_sigma;
    float stone_surf_slope_sigma;
    float stone_surface_intensity;
    float stone_cracks_intensity;
    float cracks_voronoi_size;
    float cracks_coverage;
    float mortar_perlin_x;
    float mortar_perlin_y;
    float mortar_noise_opacity; // depth
    float aggregate_opacity; // col opacity
    float aggregate_height;
    float aggregate_quantity;
    float aggregate_scale_x;
    float aggregate_scale_y;
    float aggregate_scale_variation;
    float aggregate_opactiy_variation;
    float sobel_strength;
    float occlusion_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;


// Noise
const vec2 sparse_perlin_size = vec2(4.0);
const int sparse_perlin_iterations = 8;
const float sparse_perlin_persistence = 0.5;

const int mortar_perlin_iterations = 10;
const float mortar_perlin_persistence = 1.0;

// Cracks
const float cracks_tone_value = 0.01;
const float cracks_tone_width = 0.01;

// Aggregate
const float mortar_tone_value = 0.5;
const float mortar_tone_width = 1.00;

// ORM & Normal
const float roughness_tone_value = 1.0;
const float roughness_tone_width = 0.5;



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

// Blending
float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
}

float clamped_difference(float base, float blend) {
    return clamp(blend - base, 0.0, 1.0);
}

float overlay(float base, float blend) {
	return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
}

vec3 overlay(vec3 base, vec3 blend) {
	return vec3(overlay(base.r, blend.r), overlay(base.g, blend.g), overlay(base.b, blend.b));
}

vec3 overlay(vec3 base, vec3 blend, float opacity) {
	return (overlay(base, blend) * opacity + base * (1.0 - opacity));
}

float add(float base, float blend, float opacity) {
    return min(base + blend, 1.0) * opacity + base * (1.0 - opacity);
}

float lighten(float base, float blend) {
	return max(blend, base);
}

float darken(float base, float blend) {
	return min(blend, base);
}

float multiply(float base, float blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
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
vec3 voronoi(vec2 x, float size, float seed) {
    vec2 _size = vec2(size);
    vec2 n = floor(x);
    vec2 f = fract(x);

	vec2 mr;
    float md = 8.0;
    for( int j=-1; j<=1; j++ )
    for( int i=-1; i<=1; i++ )
    {
        vec2 g = vec2(float(i),float(j));
		vec2 o = hash_ws2(vec2(seed) + mod(n + g + _size, _size));
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
		vec2 o = hash_ws2(vec2(seed) + mod(n + g + _size, _size));
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
    vec2 cell_px = gl_GlobalInvocationID.xy * 1.4 / dot(params.aggregate_scale_x, params.aggregate_scale_y);
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
    float _scale_variation = params.aggregate_scale_variation / 2;
    
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
            pv *= (rand_seed.y - 0.5) * 2.0 * _scale_variation + 1.0;
            pv /= (vec2(params.aggregate_scale_x, params.aggregate_scale_y) / 100);
            pv += 0.5;
            
            // Skip if coord is out of bounds.
            if (any(lessThan(pv, vec2(0.0))) || any(greaterThan(pv, vec2(1.0))))
                continue;
            
            pv = clamp(pv, vec2(0.0), vec2(1.0));
            
            // Evaluate the stone pattern at this instance.
            float tile_value = stone(pv, rand_seed.x) * (1.0 - params.aggregate_opactiy_variation * rand_seed.x);
            
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

    if (gradient == 0) { // aggregate colour
        int count = int(aggregate_col.length());
        if (x < aggregate_offsets[0]) {
            return aggregate_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < aggregate_offsets[i]) {
                float range = aggregate_offsets[i] - aggregate_offsets[i - 1];
                float factor = (x - aggregate_offsets[i - 1]) / range;
                return mix(aggregate_col[i - 1], aggregate_col[i], factor);
            }
        }
        return aggregate_col[count - 1];
    }

    if (gradient == 1) { // mortar colour
        int count = int(mortar_col.length());
        if (x < mortar_offsets[0]) {
            return mortar_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < mortar_offsets[i]) {
                float range = mortar_offsets[i] - mortar_offsets[i - 1];
                float factor = (x - mortar_offsets[i - 1]) / range;
                return mix(mortar_col[i - 1], mortar_col[i], factor);
            }
        }
        return mortar_col[count - 1];
    }

    if (gradient == 2) { // Brick colour
        int count = int(stone_col.length());
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
}

float map_bw_colours(float x, float limit) {
    if (x < limit) {
        return mix(1.0, 0.0, (x - limit) / -limit);
    }
    return 1.0;
}


vec4 slope_blur(vec2 uv, float sigma_strength, float iterations, int idx) { 
    // Scale UV to texture size
    vec2 scaled_uv = uv * params.texture_size;
    ivec2 pixel_coords = ivec2(scaled_uv);

    // Fetch precomputed heightmap value
    float v = imageLoad(r16f_buffer_0, pixel_coords).r;

    // Compute slope using precomputed heightmap
    float dx = 1.0 / 1024;
    vec2 slope = vec2(
        imageLoad(r16f_buffer_0, pixel_coords + ivec2(1, 0)).r - v,
        imageLoad(r16f_buffer_0, pixel_coords + ivec2(0, 1)).r - v
    );

    // Normalize slope
    float slope_strength = length(slope) * params.texture_size;
    vec2 norm_slope = (slope_strength == 0.0) ? vec2(0.0, 1.0) : normalize(slope);
    vec2 e = dx * norm_slope;

    // Blur loop
    vec4 rv = vec4(0.0);
    float sum = 0.0;
    float sigma = max(sigma_strength * slope_strength, 0.0001);

    for (float i = 0.0; i <= iterations; i += 1.0) {
        float coef = exp(-0.5 * pow(i / sigma, 2.0)) / (6.28318530718 * sigma * sigma);

        // Fetch mask at offset UV
        vec2 offset_uv = fract(uv + i * e);
        ivec2 offset_pixel = ivec2(offset_uv * params.texture_size);

        float mask_value;
        if (idx == 0) {
            mask_value = imageLoad(r16f_buffer_5, offset_pixel).r;
        }
        if (idx == 1) {
            mask_value = imageLoad(r16f_buffer_2, offset_pixel).r;
        }

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
    rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_7, pixel_coords + ivec2(e.x, e.y)).r;
    rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_7, pixel_coords - ivec2(e.x, e.y)).r;
    rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_7, pixel_coords + ivec2(e.x, -e.y)).r;
    rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_7, pixel_coords - ivec2(e.x, -e.y)).r;
    rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_7, pixel_coords + ivec2(2, 0)).r;
    rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_7, pixel_coords - ivec2(2, 0)).r;
    rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_7, pixel_coords + ivec2(0, 2)).r;
    rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_7, pixel_coords - ivec2(0, 2)).r;

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


float sample_bilinear(ivec2 base_coord, vec2 offset) {
    vec2 p = vec2(base_coord) + offset;
    ivec2 ip = ivec2(floor(p));
    vec2 f = fract(p);
    // Load the four neighboring pixels.
    float a = imageLoad(r16f_buffer_7, ip).r;
    float b = imageLoad(r16f_buffer_7, ip + ivec2(1, 0)).r;
    float c = imageLoad(r16f_buffer_7, ip + ivec2(0, 1)).r;
    float d = imageLoad(r16f_buffer_7, ip + ivec2(1, 1)).r;
    // Bilinear mix.
    float lerp1 = mix(a, b, f.x);
    float lerp2 = mix(c, d, f.x);
    return mix(lerp1, lerp2, f.y);
}

float gaussian_blur(ivec2 pixel_coords, float sigma, int quality) {
    float samples = sigma * 4.0;
    
    // LOD factor to step by more than 1 pixel. Mimics using a lower resolution mip level.
    int LOD = max(0, int(log2(samples)) - quality - 2);
    int sLOD = 1 << LOD;  // step size
    // Number of samples per dimension.
    int s = max(1, int(samples / float(sLOD)));
    
    float sumWeights = 0.0;
    float accum = 0.0;
    
    // Loop over a grid of s x s samples centered at the pixel.
    for (int i = 0; i < s * s; i++) {
        int ix = i % s;
        int iy = i / s;
        // Center the grid by subtracting half the total sample range.
        vec2 d = vec2(float(ix), float(iy)) * float(sLOD) - 0.5 * samples;
        // Compute the Gaussian weight.
        vec2 dd = d / sigma;
        float g = exp(-0.5 * dot(dd, dd)) / (6.28 * sigma * sigma);
        
        // Sample the image at pixel_coords + d using our bilinear function.
        float sampleVal = sample_bilinear(pixel_coords, d);
        accum += g * sampleVal;
        sumWeights += g;
    }
    
    float blurred = accum / sumWeights;
    return blurred;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;
    vec2 crack_warped_uv;

    if (params.stage == 0.0) { // Generate noise
        // General use sparse perlin
        float sparse_perlin = fbm_perlin_2d(uv, sparse_perlin_size, sparse_perlin_iterations, sparse_perlin_persistence, 0.0, seed.perlin_seed);
        imageStore(r16f_buffer_0, ivec2(pixel), vec4(vec3(sparse_perlin), 1.0));

        // Mortar texture perlin
        float mortar_perlin = fbm_perlin_2d(uv, vec2(params.mortar_perlin_x, params.mortar_perlin_y), mortar_perlin_iterations, mortar_perlin_persistence, 0.0, seed.mortar_perlin_seed);
        mortar_perlin = clamp((mortar_perlin - 0.95) / 1.0 + 0.5, 0.0, 1.0);
        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(mortar_perlin), 1.0));
        
        // Brick shape perlin 
        float brick_damage_perlin = fbm_perlin_2d(uv, vec2(6.0, 20.0), 4, 0.5, 0.0, 0.0);
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(brick_damage_perlin), 1.0));

        // Cracks voronoi
        crack_warped_uv = uv -= vec2(0.04 * (2.0 * sparse_perlin - 1.0));
        vec3 cracks_voronoi = voronoi(params.cracks_voronoi_size * crack_warped_uv, 100.0, seed.cracks_voronoi_seed);
        float cracks = clamp((cracks_voronoi.r - cracks_tone_value) / cracks_tone_width + 0.5, 0.0, 1.0);

        imageStore(r16f_buffer_3, ivec2(pixel), vec4(vec3(cracks), 1.0));
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
    }

    if (params.stage == 1.0) { // Mortar
        // Generate stone pattern and colour
        vec2 stones = tile_stones(uv, vec2(params.aggregate_quantity), vec2(seed.stones_seed));
        vec4 stones_colour = gradient_fct(stones.x, 0);

        // Colour mortar noise and blend with stones
        float mortar_perlin = imageLoad(r16f_buffer_1, ivec2(pixel)).r;
        vec4 mortar_colour = gradient_fct(mortar_perlin, 1);
        float mortar_blend_opacity = stones.y * params.aggregate_opacity;
        vec3 mortar_albedo = overlay(mortar_colour.rgb, stones_colour.rgb, mortar_blend_opacity);
        
        // Generate mortar roughness
        float sparse_perlin = imageLoad(r16f_buffer_0, ivec2(pixel)).r;
        float mortar_roughness_blend = add(mortar_perlin, sparse_perlin, params.mortar_noise_opacity);
        mortar_roughness_blend = clamp((mortar_roughness_blend - mortar_tone_value) / mortar_tone_width + 0.5, 0.0, 1.0);
        float mortar_roughness = add(mortar_roughness_blend, stones.y, params.aggregate_height);

        imageStore(r16f_buffer_4, ivec2(pixel), vec4(vec3(mortar_roughness), 1.0));
        imageStore(rgba32f_buffer, ivec2(pixel), vec4(mortar_albedo, 1.0));
    }    
        
    if (params.stage == 2.0) {
        float brick_damage_perlin = imageLoad(r16f_buffer_2, ivec2(pixel)).r;

        // Brick pattern
        vec4 brick_fill;
        vec2 brick_damage_uv = uv -= vec2(0.015 * (2.0 * brick_damage_perlin - 1.0));
        float brick_pattern = skewed_uneven_bricks(brick_damage_uv, vec2(params.columns, params.rows), params.brick_randomness, params.mortar, params.bevel, params.rounding, seed.brick_pattern_seed, brick_fill);

        // Cracks pattern, loaded into brick pattern transformed UVs
        vec2 crack_brick_offset = vec2(0.5 * (2.0 * brick_fill.r - 1.0), 0.250 * (2.0 * brick_fill.g - 1.0));
        vec2 crack_brick_uv = fract(uv + crack_warped_uv - crack_brick_offset);
        ivec2 transformed_pixel = ivec2(crack_brick_uv * _texture_size);
        float cracks = imageLoad(r16f_buffer_3, transformed_pixel).r;

        // Blended to make sparse cracks pattern
        float cracks_mask = map_bw_colours(brick_damage_perlin, params.cracks_coverage);
        float cracks_lightened = lighten(cracks_mask, cracks);
        
        // Blend final mortar colour with base brick colour
        vec4 mortar_albedo = imageLoad(rgba32f_buffer, ivec2(pixel));
        vec3 stone_base_mortar_albedo = normal(stone_base_col.rgb, mortar_albedo.rgb, brick_pattern * 1.0);
        
        imageStore(rgba32f_buffer_2, ivec2(pixel), vec4(stone_base_mortar_albedo, cracks_lightened)); // temp storage between stages
        imageStore(r16f_buffer_5, ivec2(pixel), vec4(vec3(brick_pattern), 1.0));
	}

    if (params.stage == 3.0) {
        float pattern = imageLoad(r16f_buffer_5, ivec2(pixel)).r;

        vec4 stone_edge_blur = slope_blur(uv, params.stone_edge_slope_sigma, max(params.stone_edge_slope_sigma, 25.0), 0);
        float stone_edge_wear = darken(stone_edge_blur.r, pattern);

        vec4 stone_surf_blur = slope_blur(uv, params.stone_surf_slope_sigma, 50, 1);
        float stone_surface_base = multiply(stone_surf_blur.r, stone_edge_wear, params.stone_surface_intensity);

        float cracks = imageLoad(rgba32f_buffer_2, ivec2(pixel)).a;
        float stone_cracked_surface = multiply(cracks, stone_surface_base, params.stone_cracks_intensity);

        float mortar_roughness = imageLoad(r16f_buffer_4, ivec2(pixel)).r;
        float base_texture = normal(stone_cracked_surface, mortar_roughness, pattern); // base texture that normals, roughness and occlusion are created from

        imageStore(r16f_buffer_6, ivec2(pixel), vec4(vec3(stone_cracked_surface), 1.0));
        imageStore(r16f_buffer_7, ivec2(pixel), vec4(vec3(base_texture), 1.0));
    }

    if (params.stage == 4.0) { // ORM
        float base_texture = imageLoad(r16f_buffer_7, ivec2(pixel)).r;
        float blur = gaussian_blur(ivec2(pixel), params.occlusion_strength, 1);
        float occlusion = 1.0 - clamped_difference(base_texture, blur);
        float roughness = 1.0 - clamp((base_texture - roughness_tone_value) / roughness_tone_width + 0.5, 0.0, 1.0);

        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(occlusion, roughness, 0.0), 1.0));
    }

    if (params.stage == 5.0) {
        vec3 normals = sobel_filter(ivec2(pixel), (params.sobel_strength / 100), params.texture_size);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        }
        if (params.normals_format == 1.0) {
            vec3 directx_normals = normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }

        float base_bw_bricks = imageLoad(r16f_buffer_6, ivec2(pixel)).r;
        vec4 col = gradient_fct(base_bw_bricks, 2);
        vec4 brick_base_mortar_albedo = imageLoad(rgba32f_buffer_2, ivec2(pixel));
        float brick_pattern = imageLoad(r16f_buffer_5, ivec2(pixel)).r;
        vec3 albedo = normal(col.rgb, brick_base_mortar_albedo.rgb, brick_pattern * 0.5);
        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }
}