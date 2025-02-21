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

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
	float seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float normals_format;
	float texture_size;
	float stage;
} params;

// Normal map
const float sobel_strength = 0.12;


float rand(vec2 x) {
    return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
}

vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
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


float skewed_uneven_bricks(vec2 uv, vec2 size, float randomness, float mortar, float bevel, float rounding, float seed) {
    const float grid_size = 4096.0;
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
    vec4 brick_fill = round(vec4(fract(rect.xy), rect.zw - rect.xy) * grid_size) / grid_size;
    
    float max_size = max(size.x, size.y);
    bevel /= (max_size / 2.0);
    mortar /= (max_size / 2.0);
    vec2 dist = (min(brick_uv, 1.0 - brick_uv) * -2.0) * brick_fill.zw + vec2(rounding + mortar);
    float brick = length(max(dist, vec2(0.0))) + min(max(dist.x, dist.y), 0.0) - rounding;
    
    return clamp(-brick / bevel, 0.0, 1.0);
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

	if (params.stage == 0.0) {
		float pattern = skewed_uneven_bricks(uv, vec2(4, 10), 1.0, 0.05, 0.05, 0.12, 1.0);
		imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(pattern), 1.0));
	}
}