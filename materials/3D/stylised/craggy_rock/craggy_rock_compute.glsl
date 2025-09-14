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
    float seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
    float normals_format;
	float texture_size;
	float stage;
} params;


const float PI = 3.14159265359;
const float DEG2RAD = PI / 180.0;


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


float darken(float base, float blend) {
	return min(blend, base);
}


// S0
const float v_scale_x = 6.0;
const float v_scale_y = 6.0;
const float v_randomness = 1.0;

const float v_base_offset_low = 0.23;
const float v_base_offset_high = 0.69;
const float v_base_col_low = 0.36;
const float v_base_grad_layers = 17.0;

const float v_depth_offset_low = 0.18;
const float v_depth_offset_high = 0.46;
const float v_depth_grad_layers = 80.0;

const float fill_seed = 0.428;
const float voronoi_seed = 0.685;
const float grad_rotate = 0.0;
const float grad_rnd_rotate = 180.0;
const float grad_rnd_offset = 1.0;


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


float v_island_gradient(float x, float offset_low, float offset_high, float col_low) {
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
		float gradient = v_island_gradient(grad_uv.x, offset_low, offset_high, col_low);
		final_color = min(final_color, gradient);
	}
	return final_color;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 1.0) {
		vec2 v_size = vec2(v_scale_x, v_scale_y);		
		vec2 p = uv * v_size;

		vec4 voronoi_sb = voronoi_site_box(p, v_size, v_randomness, seed.seed);
		vec3 island_uv = generate_island_uv(uv, voronoi_sb, seed.seed);
		
		float base_gradient = v_gradient(island_uv, int(v_base_grad_layers), v_base_offset_low, v_base_offset_high, v_base_col_low);
		float depth_gradient = v_gradient(island_uv, int(v_depth_grad_layers), v_depth_offset_low, v_depth_offset_high, 0.0);
		float blended_gradient = darken(base_gradient, depth_gradient);
		imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(blended_gradient), 1.0));
    }
}