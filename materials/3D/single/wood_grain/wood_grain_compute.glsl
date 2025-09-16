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
    float base_seed;
    float detailed_seed;
    float lines_seed;
    float dirt_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer restrict readonly GradientOffsets {
    float gradient_offsets[];
};

layout(set = 4, binding = 0, std430) buffer restrict readonly GradientColours {
    vec4 gradient_col[];
};

layout(push_constant, std430) uniform restrict readonly Params {
    float grain_scale_x;
    float grain_scale_y;
    float grain_base_highs;
    float grain_base_lows;
    float grain_detailed_iterations;
    float grain_detailed_size;
    float lines_smooth_min;
    float lines_smooth_max;
    float lines_dimension;
    float lines_size;
    float lines_scale;
    float lines_opacity;
    float dirt_scale_x;
    float dirt_scale_y;
    float dirt_dimension;
    float dirt_size;
    float dirt_opacity;
    float roughness_value;
    float roughness_width;
    float blend_strength;
    float normals_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;


const float grain_detailed_scale = 4.6;
const int lines_iterations = 2;
const int dirt_iterations = 15;


float sum_vector(vec2 vec) { 
    return dot(vec, vec2(1.0)); 
}

float hash31(vec3 pos) {
	pos = fract(pos * 0.1031);
	pos += dot(pos, pos.yzx + 333.3456);
    return fract(sum_vector(pos.xy) * pos.z);
}

float hash21(vec2 pos) { 
    return hash31(pos.xyx); 
}


// https://www.shadertoy.com/view/lstGRB - Shane / IQ - Transparent 3D Noise (ported to 2D for this shader)
float value_noise_2d(vec2 pos) {
    const vec2 cell_stride = vec2(157, 113);
    vec2 unit_cell_id = floor(pos);
    pos = fract(pos);
    pos = smoothstep(0.0, 1.0, pos);

    vec2 cell_hash = vec2(0.0, cell_stride.y) + dot(unit_cell_id, cell_stride);
    cell_hash = mix(fract(sin(cell_hash) * 43758.545), fract(sin(cell_hash + cell_stride.x) * 43758.545), pos.x);
    return mix(cell_hash.x, cell_hash.y, pos.y);
}

float fbm_2d(vec2 coord, int iterations, float persistence) {
    float noise_sum = 0.0;
    float amplitude = 1.0;
    float total_amplitude = 0.0;
    persistence = clamp(persistence, 0.0, 1.0);

    for (int i = 0; i < iterations; i++) {
        noise_sum += amplitude * value_noise_2d(coord);
        total_amplitude += amplitude;
        amplitude *= persistence;
        coord *= 2.0;
    }
    return noise_sum / total_amplitude;
}

vec2 random_pos_2d(float seed) {
    return vec2(hash21(vec2(seed, 0.0)), hash21(vec2(seed, 1.0))) * 100.0 + 100.0;
}

float fbm_distorted_2d(vec2 coord, float seed) {
    coord += (vec2(value_noise_2d(coord + random_pos_2d(seed)), 
                   value_noise_2d(coord + random_pos_2d(seed))) * 2.0 - 1.0) * 1.12;

    return fbm_2d(coord, 8, 0.5);
}

float fbm_musgrave_2d(vec2 coord, int iterations, float dimension, float size, float seed) {
    float noise_sum  = 0.0;
    float amplitude = 1.0;
    float persistence = pow(size, -dimension);
    
    vec2 seed_offset = vec2(hash21(vec2(seed, 0.0)), hash21(vec2(seed, 1.0))) * seed;
    coord += seed_offset;

    for (int i = 0; i < iterations; i++) {
        float noise_value = value_noise_2d(coord) * 2.0 - 1.0;
        noise_sum  += noise_value * amplitude;
        amplitude *= persistence;
        coord *= size;
    }
    return noise_sum;
}

vec2 fbm_wave_x_2d(vec2 coord) {
    float wave_phase = coord.x * 20.0;
    wave_phase += 0.4 * fbm_2d(coord * 3.0, 3, 3.0);
    return vec2(sin(wave_phase) * 0.5 + 0.5, coord.y);
}

float make_tileable(vec2 uv, float blend_width) {
    // Sample at original UV & wrapped offsets
    float sample_A = imageLoad(r16f_buffer_1, ivec2(uv * params.texture_size)).r;
    float sample_B = imageLoad(r16f_buffer_1, ivec2(fract(uv + vec2(0.5)) * params.texture_size)).r;
    float sample_C = imageLoad(r16f_buffer_1, ivec2(fract(uv + vec2(0.25)) * params.texture_size)).r;

    // Compute a blend coefficient based on distance from the center (0.5, 0.5).
    float dist_from_centre = length(uv - vec2(0.5));
    float coef_AB = sin(1.57079632679 * clamp((dist_from_centre - 0.5 + blend_width) / blend_width, 0.0, 1.0));
    
    // Compute another blend coefficient based on the distance from the middle of the edges.
    float d_left   = length(uv - vec2(0.0, 0.5));
    float d_bottom = length(uv - vec2(0.5, 0.0));
    float d_right  = length(uv - vec2(1.0, 0.5));
    float d_top    = length(uv - vec2(0.5, 1.0));
    float min_edge_dist = min(min(d_left, d_bottom), min(d_right, d_top));
    float coef_ABC = sin(1.57079632679 * clamp((min_edge_dist - blend_width) / blend_width, 0.0, 1.0));
    
    // Blend the first two samples using coef_AB, then blend with the third sample using coef_ABC.
    float mix_AB = mix(sample_A, sample_B, coef_AB);
    return mix(sample_C, mix_AB, coef_ABC);
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

ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

// Generate normals
vec3 sobel_filter(ivec2 coord, float amount) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0); // Offsets in UV space converted to pixel space
    vec2 rv = vec2(0.0);

    // Apply Sobel-like filter to compute gradient
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


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        imageStore(occlusion_buffer, ivec2(pixel), vec4(1.0)); // No occlusion
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(1.0), 1.0)); // No metallness
    }

	if (params.stage == 1.0) {
        vec2 grain_base_scale = vec2(params.grain_scale_x, params.grain_scale_y);
        float grain_base = fbm_distorted_2d(uv * grain_base_scale, seed.base_seed);
		grain_base = mix(grain_base, params.grain_base_highs, params.grain_base_lows);
        
        float grain_detailed = mix(fbm_musgrave_2d(vec2(grain_base * grain_detailed_scale), int(params.grain_detailed_iterations), 0.0, params.grain_detailed_size, seed.detailed_seed), grain_base, 0.85);
        
        vec2 _dirt_scale = vec2(params.dirt_scale_x, params.dirt_scale_y);
        float dirt = 1.0 - fbm_musgrave_2d(fbm_wave_x_2d(uv * _dirt_scale), dirt_iterations, params.dirt_dimension, params.dirt_size, seed.dirt_seed) * params.dirt_opacity;
        
        vec2 lines_scale;
        if (grain_base_scale.x > grain_base_scale.y) {
            lines_scale = vec2(grain_base_scale.x * 80.0, grain_base_scale.y * 5.0) * params.lines_scale;
        }
        else {
            lines_scale = vec2(grain_base_scale.x * 5.0, grain_base_scale.y * 80.0) * params.lines_scale;
        }
        float grain_lines = 1.0 - smoothstep(params.lines_smooth_min, params.lines_smooth_max, fbm_musgrave_2d(
            uv * lines_scale, lines_iterations, params.lines_dimension, params.lines_size, seed.lines_seed)) * params.lines_opacity;
        
        grain_detailed *= dirt * grain_lines;
         
        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(grain_detailed), 1.0));
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(grain_base), 1.0));
    }

	if (params.stage == 2.0) {
        float grain_detailed = make_tileable(uv, params.blend_strength);
        imageStore(r16f_buffer_2, ivec2(pixel), vec4(vec3(grain_detailed), 1.0));

        vec3 albedo = gradient_fct(clamp(grain_detailed, 0.01, 0.99)).rgb;
		imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));

        float grain_base = imageLoad(r16f_buffer_2, ivec2(pixel)).r;
        float roughness_input = 1.0 - clamp((grain_base - params.roughness_value) / params.roughness_width + 0.5, 0.0, 1.0);
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness_input), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(1.0, roughness_input, 0.0), 1.0));
	}

    if (params.stage == 3.0) {
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