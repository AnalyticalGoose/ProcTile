#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D rgba32f_buffer;

layout(push_constant, std430) uniform restrict readonly Params {
    float columns;
	float rows;
	float bevel;
	float grain_layers;
	float grain_width;
	float grain_waviness;	
	float normals_format;
	float texture_size;
	float stage;
} params;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float plank_colour_seed;
    float grain_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly PlankOffsets {
    float plank_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly PlankColours {
    vec4 plank_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly GrainColour {
    vec4 grain_col;
};

layout(set = 6, binding = 0, std430) buffer readonly BevelColour {
    vec4 bevel_col;
};


float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rand2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+19.19);
    return fract((p3.xx+p3.yz) * p3.zy);
}

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}

vec4 get_plank_bounds(vec2 uv, vec2 grid, float row_offset) {
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    
    float row = floor(uv.y * grid.y);
    float x_offset = row_offset * mod(row, 2.0);
    vec2 plank_min, plank_max;

    plank_min = floor(vec2(uv.x * grid.x - x_offset, uv.y * grid.y));
    plank_min.x += x_offset;
    plank_min /= grid;
    plank_max = plank_min + vec2(1.0) / grid;
    
	return vec4(plank_min, plank_max);
}

float get_plank_pattern(vec2 uv, vec2 plank_min, vec2 plank_max, float mortar, float rounding, float bevel, float plank_scale) {
    mortar *= plank_scale;
    rounding *= plank_scale;
    bevel *= plank_scale;
    vec2 plank_size = plank_max - plank_min;
    vec2 plank_center = 0.5 * (plank_min + plank_max);
    vec2 edge_dist = abs(uv - plank_center) - 0.5 * plank_size + vec2(rounding + mortar);
    float distance = length(max(edge_dist, vec2(0))) + min(max(edge_dist.x, edge_dist.y), 0.0) - rounding;
    return clamp(-distance / bevel, 0.0, 1.0);
}

float grain_line(vec2 uv, float line_y, float thickness, float waviness, float seed) {
  float offset_y = line_y + waviness * sin(uv.x * 6.28318 + seed);
  return smoothstep(thickness, 0.0, abs(uv.y - offset_y));
}

float grain(vec2 uv, int layers, float thickness, float waviness, float seed) {
  float result = 0.0;
  for (int i = 0; i < layers; ++i) {
    float line_y = fract(sin(float(i) * 12.9898 + seed * 78.233) * 43758.5453);
    result = max(result, grain_line(uv, line_y, thickness, waviness, seed + float(i)));
  }
  return result;
}

vec4 map_bw_colours(float x, vec4 col_white, vec4 col_black) {
    if (x < 1.0) {
		return mix(col_white, col_black, x);
    }
    return col_black;
}

vec4 gradient_fct(float x) {
    int count = int(plank_col.length());
    if (x < plank_offsets[0]) {
        return plank_col[0];
    }
    for (int i = 1; i < count; i++) {
        if (x < plank_offsets[i]) {
            float range = plank_offsets[i] - plank_offsets[i - 1];
            float factor = (x - plank_offsets[i - 1]) / range;
            return mix(plank_col[i - 1], plank_col[i], factor);
        }
    }
    return plank_col[count - 1];
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0) {
		float _grain_width = params.grain_width / 5000;
		float _grain_waviness = params.grain_waviness / 1000;

		vec4 plank_bounding_rect = get_plank_bounds(uv, vec2(params.columns, params.rows), 0.5);
		float pattern = get_plank_pattern(uv, plank_bounding_rect.xy, plank_bounding_rect.zw, 0.0, 0.0, params.bevel, 1.0 / params.rows);
		vec3 pattern_colour = map_bw_colours(pattern, bevel_col, vec4(1.0)).rgb;

		vec4 plank_fill = round(vec4(fract(plank_bounding_rect.xy), plank_bounding_rect.zw - plank_bounding_rect.xy) * params.texture_size) / params.texture_size;
        float random_plank_gray = mix(0.0, rand(vec2(float((seed.plank_colour_seed)), rand(vec2(rand(plank_fill.xy), rand(plank_fill.zw))))), step(0.0000001, dot(plank_fill.zw, vec2(1.0))));

		vec2 warped_uv = fract(uv -= vec2(0.5 * (2.0 * random_plank_gray - 1.0), 0.250 * (2.0 * random_plank_gray - 1.0)));
		float grain_lines = 1.0 - grain(warped_uv, int(params.grain_layers), _grain_width, _grain_waviness, seed.grain_seed);
		vec3 grain_colour = map_bw_colours(grain_lines, grain_col, vec4(1.0)).rgb;

		vec3 plank_colour = gradient_fct(random_plank_gray).rgb;
		vec3 plank_grain_blend = multiply(plank_colour, grain_colour, 1.0);
		vec3 albedo = multiply(plank_grain_blend, pattern_colour, 1.0);

        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }

}