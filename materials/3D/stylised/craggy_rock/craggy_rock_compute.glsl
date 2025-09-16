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

layout(set = 2, binding = 0, std430) buffer restrict readonly Seeds {
    float voronoi_seed;
    float fill_seed;
    float perlin_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer restrict readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 4, binding = 0, std430) buffer restrict readonly GradientColours {
    vec4 gradient_col[];
};

layout(push_constant, std430) uniform restrict readonly Params {
    float v_scale_x;
    float v_scale_y;
    float v_randomness;
    float v_base_offset_high;
    float v_base_col_low;
    float v_depth_offset_low;
    float v_depth_offset_high;
    float perlin_x;
    float perlin_y;
    float perlin_iterations;
    float perlin_persistence;
    float sharpen_grid;
    float normals_strength;
    float roughness_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;


const float PI = 3.14159265359;
const float DEG2RAD = PI / 180.0;

// S0
const float v_base_offset_low = 0.23;
const float v_base_grad_layers = 17.0;
const float v_depth_grad_layers = 80.0;

const float fill_seed = 0.428;
const float voronoi_seed = 0.685;
const float grad_rotate = 0.0;
const float grad_rnd_rotate = 180.0;
const float grad_rnd_offset = 1.0;

// S1
const float a_base_brightness = -0.25;
const float a_base_contrast = 0.20;
const float a_in_blend_opacity = 0.75;

const float n_in_blend_opacity = 0.15;

const float ao_tone_value = 0.25;
const float ao_tone_width = 1.0;
const float ao_offset_low = 0.20;
const float ao_offset_high = 0.75;
const float ao_col_low = 0.25;



float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
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


// Blending
float darken(float base, float blend) {
	return min(blend, base);
}

float overlay(float base, float blend) {
	return base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend));
}

float overlay(float base, float blend, float opacity) {
	return opacity * overlay(base, blend) + (1.0 - opacity) * blend;
}

float multiply(float base, float blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}


/** Voronoi distances by Inigo Quilez - https://www.shadertoy.com/view/ldl3W8, https://www.youtube.com/c/InigoQuilez, https://iquilezles.org/
*
* Adapted to idenfity the given cell for input 'x' and return a fixed size box centred on the cell's feature point.
* .xy is normalised bottom-left corner of site-box, .zw is normalised dimensions of site-box.
* This can then be used to create stretched UV islands. 
*
*/ 
vec4 voronoi_site_box(vec2 x, vec2 grid_size, float randomness, float seed) {
    vec2 n = floor(x); // Integer part of x (grid cell ID)
    vec2 f = fract(x); // Fractional part of x (position within the cell)

    vec2 closest_feature_point;
    float min_dist_sq = 8.0;

    // Check the 3x3 grid of cells around the current one
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 cell_offset = vec2(float(i), float(j));

            vec2 random_offset = randomness * hash_ws2(vec2(seed) + mod(n + cell_offset, grid_size));
            vec2 feature_point = cell_offset + random_offset;
            float dist_sq = dot(feature_point - f, feature_point - f);

            if (dist_sq < min_dist_sq) {
                min_dist_sq = dist_sq;
                closest_feature_point = feature_point;
            }
        }
    }

    vec2 box_center = n + closest_feature_point;
    vec2 box_corner = box_center - 1.0;
    vec2 box_size   = vec2(2.0);

    // Normalize position and size
    vec2 normalized_pos = fract(box_corner / grid_size);
    vec2 normalized_dim = box_size / grid_size;
    vec4 cell_box = vec4(normalized_pos, normalized_dim);

    return round(cell_box * params.texture_size) / params.texture_size;
}


vec3 generate_island_uv(vec2 uv, vec4 cell_info, float seed) {
    // Remap the original UV into the [0, 1] range of the source box.
    vec2 island_uv = fract(uv - cell_info.xy) / cell_info.zw;
    float island_random_value = rand(vec2(seed) + cell_info.xy);
    return vec3(island_uv, island_random_value);
}


vec2 gradient_uv(vec2 uv, float rotate, float rnd_rotate, float rnd_offset, vec2 layer_seed) {
	float angle = (rotate + (layer_seed.x * 2.0 - 1.0) * rnd_rotate) * DEG2RAD;
	float ca = cos(angle);
	float sa = sin(angle);

	uv -= vec2(0.5); // centre for rotation
	mat2 rotation_matrix = mat2(ca, -sa, sa,  ca);
	uv = rotation_matrix * uv;
	uv.x += layer_seed.y * rnd_offset;
	uv /= sqrt(2.0); // normalise

	return clamp(uv + 0.5, 0.0, 1.0);
}


float map_gradient_col(float x, float offset_low, float offset_high, float col_low) {
	if (x < offset_low) {
		return col_low;
	} 
	else if (x < offset_high) {
		float range = offset_high - offset_low;
		float factor = (x - offset_low) / range;
		return mix(col_low, 1.0, factor);
	}
	return 1.0;
}


float v_gradient(vec3 island_uv, int layers, float offset_low, float offset_high, float col_low) {
	float final_color = 1.0;
	for( int i = 0; i < layers; i++) {
		vec2 layer_seed = hash_ws2(vec2(island_uv.z, fill_seed + float(i)));
		vec2 grad_uv = gradient_uv(island_uv.xy, grad_rotate, grad_rnd_rotate, grad_rnd_offset, layer_seed);
		float gradient = map_gradient_col(grad_uv.x, offset_low, offset_high, col_low);
		final_color = min(final_color, gradient);
	}
	return final_color;
}


ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}


float sharpen(ivec2 coord) {
	const int stride = int(params.texture_size / int(params.sharpen_grid));

    // Sample the center pixel
    float center = imageLoad(r16f_buffer_1, wrap_coord(coord)).r;

    // Sample the "neighboring" pixels using the calculated stride
    float left   = imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(-stride,  0))).r;
    float right  = imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2( stride,  0))).r;
    float down   = imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2( 0, -stride))).r;
    float up     = imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2( 0,  stride))).r;

    // Apply the sharpening kernel
    return 5.0 * center - (left + right + up + down);
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


vec3 sobel_filter(ivec2 coord, float amount) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(e.x, e.y))).r;
    rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(e.x, e.y))).r;
    rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(e.x, -e.y))).r;
    rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
    rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(2, 0))).r;
    rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(2, 0))).r;
    rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_2, wrap_coord(coord + ivec2(0, 2))).r;
    rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_2, wrap_coord(coord - ivec2(0, 2))).r;

    // Scale the gradient
    rv *= size * amount / 128.0;

    // Generate the normal vector and remap to [0, 1] for visualization
    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


float greyscale(vec3 col) {
	return 0.21 * col.r + 0.72 * col.g + 0.07 * col.b;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
		vec2 v_size = vec2(params.v_scale_x, params.v_scale_y);		
		vec2 p = uv * v_size;

		vec4 voronoi_sb = voronoi_site_box(p, v_size, params.v_randomness, seed.voronoi_seed);
		vec3 island_uv = generate_island_uv(uv, voronoi_sb, seed.fill_seed);
		
		float base_gradient = v_gradient(island_uv, int(v_base_grad_layers), v_base_offset_low, params.v_base_offset_high, params.v_base_col_low);
		float depth_gradient = v_gradient(island_uv, int(v_depth_grad_layers), params.v_depth_offset_low, params.v_depth_offset_high, 0.0);
		float blended_gradient = darken(base_gradient, depth_gradient);
		imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(blended_gradient), 1.0));
    }

	if (params.stage == 1.0) {
		float blended_gradient = imageLoad(r16f_buffer_1, ivec2(pixel)).r;

		float albedo_base = clamp(blended_gradient * a_base_contrast + a_base_brightness + 0.5 * (1.0 - a_base_contrast), 0.0, 1.0);
		float albedo_highlights = sharpen(ivec2(pixel));
		float albedo_blend = overlay(albedo_highlights, albedo_base, a_in_blend_opacity);
		vec4 albedo = gradient_fct(albedo_blend);
		imageStore(albedo_buffer, ivec2(pixel), albedo);

		float perlin = fbm_perlin_2d(uv, vec2(params.perlin_x, params.perlin_y), int(params.perlin_iterations), params.perlin_persistence, 0.0, seed.perlin_seed);
		float base_surface = multiply(perlin, blended_gradient, n_in_blend_opacity);
		imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(base_surface), 1.0));

		float base_lightened = clamp((base_surface - ao_tone_value) / ao_tone_width + 0.5, 0.0, 1.0);
		float ao_in = map_gradient_col(base_lightened, ao_offset_low, ao_offset_high, ao_col_low);
		imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(ao_in), 1.0));
		
		imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(params.roughness_strength), 1.0));
		imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
		imageStore(orm_buffer, ivec2(pixel), vec4(ao_in, params.roughness_strength, 0.0, 1.0));
	}

	if (params.stage == 2.0) {
		vec3 normals = sobel_filter(ivec2(pixel), params.normals_strength);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        } 
        else if (params.normals_format == 1.0) {
            vec3 directx_normals = normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }
	}
}