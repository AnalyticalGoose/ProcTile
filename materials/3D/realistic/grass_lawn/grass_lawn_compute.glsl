#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer_0;
layout(r16f, set = 1, binding = 1) uniform image2D r16f_buffer_1;
layout(r16f, set = 1, binding = 2) uniform image2D clover_buffer;
layout(r16f, set = 1, binding = 3) uniform image2D soil_perlin_buffer;

layout(push_constant, std430) uniform restrict readonly Params {
    float blades_spacing;
    float lookup_dist;
    float blade_width;
    float direction_bias_x;
    float direction_bias_y;
    float clover_quantity;
    float clover_scale;
    float clover_scale_variation;
    float clover_opacity_variation;
    float normals_format;
	float texture_size;
	float stage;
} params;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float grass_seed;
    float clover_seed;
    float soil_perlin_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly GrassOffsets {
    float grass_offsets[];
};

layout(set = 4, binding = 0, std430) buffer readonly GrassColours {
    vec4 grass_col[];
};

layout(set = 5, binding = 0, std430) buffer readonly SoilOffsets {
    float soil_offsets[];
};

layout(set = 6, binding = 0, std430) buffer readonly SoilColours {
    vec4 soil_col[];
};

layout(set = 7, binding = 0, std430) buffer readonly CloverOffsets {
    float clover_offsets[];
};

layout(set = 8, binding = 0, std430) buffer readonly CloverColours {
    vec4 clover_col[];
};

const vec2 soil_perlin_scale = vec2(10.0);
const int soil_perlin_iterations = 10;
const float soil_perlin_persistence = 1.0;
const float roughness_tone_value = 0.95;
const float roughness_tone_width = 0.25;
const float ao_tone_value = 0.90;
const float ao_tone_width = 1.0;

float rand(vec2 p) {
    return fract(cos(mod(dot(p, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
}

vec3 rand3(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yxz+19.19);
    return fract((p3.xxy+p3.yzz) * p3.zyx);
}

vec2 rand2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+19.19);
    return fract((p3.xx+p3.yz) * p3.zy);
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

vec3 add(vec3 base, vec3 blend, float opacity ) {
    return (min(base + blend, 1.0) * opacity + base * (1.0 - opacity));
}

float multiply(float base, float blend, float opacity) {
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


// Adapated from Bycob / BynaryCobweb - https://github.com/Bycob/world - World generation tool
// https://github.com/Bycob/world/blob/develop/projects/vkworld/shaders/terrains/texture-grass.frag
float get_grass_blade(vec2 position, vec2 grass_pos) {
    // Random blade vector in [-1.0, 1.0]. Scale and bias z component [0.0, 0.4]
    vec3 rand_blade = rand3(grass_pos * 123512.41 * seed.grass_seed) * 2.0 - vec3(params.direction_bias_x, params.direction_bias_y, 1.0);
    rand_blade.z = rand_blade.z * 0.2 + 0.2;
   
    // Direction, length and relative position to pixel
    vec2 blade_dir = normalize(rand_blade.xy);
    float length_bias = max((params.lookup_dist / 100) - 0.06, 0.01);
    float blade_length = rand(grass_pos * 102348.7) * length_bias + 0.012;
   
    // Calculate relative position with proper wrapping
    vec2 rel_pos = position - grass_pos;
    
    // NOTE - I'm unsure how needed all this is - however it's the only way I've managed to get completely reliable wrapping without edge cases.
    // Handle wrapping by checking all possible wrapped positions
    float min_dist_sq = 1e6;
    vec2 best_rel_pos = rel_pos; 
    // Check the 9 possible positions (original + 8 wrapped neighbors)
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            vec2 test_rel_pos = rel_pos + vec2(float(dx), float(dy));
            float dist_sq = dot(test_rel_pos, test_rel_pos);
            if (dist_sq < min_dist_sq) {
                min_dist_sq = dist_sq;
                best_rel_pos = test_rel_pos;
            }
        }
    }
    
    // Use the shortest wrapped relative position
    rel_pos = best_rel_pos;
    
    // Project onto blade direction, compute perpendicular distance and normalise
    float proj = dot(blade_dir, rel_pos);
    vec2 perp = vec2(-blade_dir.y, blade_dir.x);
    float perp_dist = dot(perp, rel_pos);
    float t = proj / blade_length;
   
    // Check if the pixel lies within the blade region.
    if(t >= 0.0 && t <= 1.0 && abs(perp_dist) <= (params.blade_width / 10000) * (1.0 - t * t)) {
        return rand_blade.z * t;
    } else {
        return -1.0;
    }
}


float tile_grass(vec2 position) {
    float blades_spacing = params.blades_spacing / 1000;
    int lookup_dist = int(min(params.lookup_dist, 6.0));
    int x_count = int(1.0 / blades_spacing);
    int y_count = int(1.0 / blades_spacing);
    
    // Wrap the input position to [0,1] range
    vec2 wrapped_position = mod(position, 1.0);
    
    int ox = int(wrapped_position.x * float(x_count));
    int oy = int(wrapped_position.y * float(y_count));
   
    float max_z = 0.0;
    for (int i = -lookup_dist; i < lookup_dist; ++i) {
        for (int j = -lookup_dist; j < lookup_dist; ++j) {
            // Wrap the grid indices to handle boundary conditions
            int wrapped_x = (ox + i + x_count * 100) % x_count; // Add large offset to handle negative values
            int wrapped_y = (oy + j + y_count * 100) % y_count;
            
            vec2 u_pos = vec2(wrapped_x, wrapped_y);
            vec2 grass_pos = mod((u_pos * blades_spacing + rand2(u_pos) * 0.004), 1.0);
            
            float z = get_grass_blade(wrapped_position, grass_pos);
            if (z > max_z) {
                max_z = z;
            }
        }
    }
    return max_z;
}


float clover() {
    vec2 q = 0.6 * (2.0 * gl_GlobalInvocationID.xy - vec2(params.texture_size)) / min(params.texture_size, params.texture_size);
    float r = length( q ); // Radial gradiant
    
    float a = atan( q.x, q.y );
    float s = 0.50001 + 0.5 * sin( 3.0 * a);
    float g = sin( 1.57 + 3.0 * a);
    float d = 0.15 + 0.2 * sqrt(s) + 0.1 * g * g;
    
    float h = clamp( r / d, 0.0, 1.0 );
    float f = smoothstep( 0.95, 1.0, h );
    
    float blend = 1.0 - normal(h, f, 0.5);
    float clover_base = blend * 0.25;

    return clover_base;
}


vec2 tile_clover(vec2 uv, vec2 tile, vec2 seed_offset) {
    float max_contribution = 0.0;
    float final_colour = 0.0;
    float _scale_variation = params.clover_scale_variation / 2;
    
    for (int dx = -2; dx <= 2; ++dx) {
        for (int dy = -2; dy <= 2; ++dy) {
            vec2 pos = uv * tile + vec2(float(dx), float(dy)); 
            pos = fract((floor(mod(pos, tile)) + vec2(0.5)) / tile) - vec2(0.5);
			vec2 seed = rand2(pos+seed_offset);
			float col = rand(seed);
			pos = fract(pos + vec2(0.0 / tile.x, 0.0) * floor(mod(pos.y * tile.y, 2.0)) + 1.0 * seed / tile);

			vec2 pv = fract(uv - pos) - vec2(0.5);
			seed = rand2(seed);
			float angle = (seed.x * 2.0 - 1.0) * 180.0 * 0.01745329251;
			float ca = cos(angle);
			float sa = sin(angle);
			pv = vec2(ca * pv.x + sa * pv.y, -sa * pv.x + ca * pv.y);
			pv *= (seed.y-0.5) * 2.0 * _scale_variation + 1.0;
			pv /= (vec2(params.clover_scale) / 100);
			pv += vec2(0.5);
			seed = rand2(seed);
			vec2 clamped_pv = clamp(pv, vec2(0.0), vec2(1.0));
			if (pv.x != clamped_pv.x || pv.y != clamped_pv.y) {
				continue;
            }
            pv = clamp(pv, vec2(0.0), vec2(1.0));
            
            // Evaluate the stone pattern at this instance.
            float tile_value = imageLoad(clover_buffer, ivec2(pv * params.texture_size)).r * (1.0 - params.clover_opacity_variation * seed.x);
            
            // Keep the instance if its contribution is highest so far.
            if (tile_value > max_contribution) {
                max_contribution = tile_value;
                final_colour = col;
            }
        }
    }
    return vec2(final_colour, max_contribution);
}


vec4 gradient_fct(float x, int gradient) {
    if (gradient == 0) { // soil colour
        int count = int(soil_col.length());
        if (x < soil_offsets[0]) {
            return soil_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < soil_offsets[i]) {
                float range = soil_offsets[i] - soil_offsets[i - 1];
                float factor = (x - soil_offsets[i - 1]) / range;
                return mix(soil_col[i - 1], soil_col[i], factor);
            }
        }
        return soil_col[count - 1];
    }

    else if (gradient == 1) { // grass colour
        int count = int(grass_col.length());
        if (x < grass_offsets[0]) {
            return grass_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < grass_offsets[i]) {
                float range = grass_offsets[i] - grass_offsets[i - 1];
                float factor = (x - grass_offsets[i - 1]) / range;
                return mix(grass_col[i - 1], grass_col[i], factor);
            }
        }
        return grass_col[count - 1];
    }
    
    else if (gradient == 2) { // clover colour
        int count = int(clover_col.length());
        if (x < clover_offsets[0]) {
            return clover_col[0];
        }
        for (int i = 1; i < count; i++) {
            if (x < clover_offsets[i]) {
                float range = clover_offsets[i] - clover_offsets[i - 1];
                float factor = (x - clover_offsets[i - 1]) / range;
                return mix(clover_col[i - 1], clover_col[i], factor);
            }
        }
        return clover_col[count - 1];
    }
}

ivec2 wrap_coord(ivec2 coord) {
    float s = params.texture_size;
    return ivec2(mod(mod(coord, s + s), s));
}

// Generate normals
vec3 sobel_filter(ivec2 coord, float amount, int index) {
    float size = params.texture_size;
    vec3 e = vec3(1.0 / size, -1.0 / size, 0.0);
    vec2 rv = vec2(0.0);

    if (index == 0) { // soil
        rv += vec2(1.0, 0.0) * imageLoad(soil_perlin_buffer, wrap_coord(coord + ivec2(1, 0))).r;
        rv += vec2(0.0, 1.0) * imageLoad(soil_perlin_buffer, wrap_coord(coord + ivec2(0, 1))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(soil_perlin_buffer, wrap_coord(coord)).r;

        rv *= size * amount / 20.0;
    }

    else if (index == 1) {
        rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(0, 2))).r;

        rv *= size * amount / 128.0;
    }

    else if (index == 2) {
        rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_0, wrap_coord(coord + ivec2(e.x, e.y))).r;
        rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_0, wrap_coord(coord - ivec2(e.x, e.y))).r;
        rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_0, wrap_coord(coord + ivec2(e.x, -e.y))).r;
        rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_0, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
        rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_0, wrap_coord(coord + ivec2(2, 0))).r;
        rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_0, wrap_coord(coord - ivec2(2, 0))).r;
        rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_0, wrap_coord(coord + ivec2(0, 2))).r;
        rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_0, wrap_coord(coord - ivec2(0, 2))).r;

        rv *= size * amount / 128.0;
    }

    return vec3(0.5) + 0.5 * normalize(vec3(rv, -1.0));
}


// Reorientated Normal Mapping - Stephen Hill & Colin Barre-Brisebois - https://blog.selfshadow.com/publications/blending-in-detail/
// https://www.shadertoy.com/view/4t2SzR
vec3 normal_rnm_blend(vec3 n1, vec3 n2, float opacity) {
    n1.z = 1.0 - n1.z;
    n2.z = 1.0 - n2.z;

    // unpacked and rmn blend
	vec3 t = n1*vec3( 2,  2, 2) + vec3(-1, -1,  0);
	vec3 u = n2*vec3(-2, -2, 2) + vec3( 1,  1, -1);
	vec3 rnm = mix(n2 * 2.0 - 1.0, t * dot(t, u) / t.z - u, opacity);

    // Restore z-axis and repack to to [0,1]
    rnm.z = -rnm.z;
    return rnm * 0.5 + 0.5;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        float soil_perlin = fbm_perlin_2d(uv, soil_perlin_scale, soil_perlin_iterations, soil_perlin_persistence, 0.0, seed.soil_perlin_seed);
        imageStore(soil_perlin_buffer, ivec2(pixel), vec4(vec3(soil_perlin), 1.0));

        float clover = clover();
        imageStore(clover_buffer, ivec2(pixel), vec4(vec3(clover), 1.0));
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(0.0), 1.0));
    }

    if (params.stage == 1.0) {
        float clover_base = tile_clover(uv, vec2(params.clover_quantity), vec2(seed.clover_seed)).y;
        imageStore(r16f_buffer_0, ivec2(pixel), vec4(vec3(clover_base), 1.0));
    }

    if (params.stage == 2.0) {
        float grass_base = tile_grass(uv);
        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(grass_base), 1.0));
    }

    if (params.stage == 3.0) {
        float soil_perlin = imageLoad(soil_perlin_buffer, ivec2(pixel)).r;
        float clover_base = imageLoad(r16f_buffer_0, ivec2(pixel)).r;
        float grass_base = imageLoad(r16f_buffer_1, ivec2(pixel)).r;

        vec3 soil_colour = gradient_fct(soil_perlin, 0).rgb;
        vec3 grass_colour = gradient_fct(grass_base, 1).rgb;
        vec3 grass_soil_blend = add(soil_colour, grass_colour, 1.0);

        float clover_texture = multiply(soil_perlin, clover_base, 1.0);
        vec3 clover_colour = gradient_fct(clover_texture, 2).rgb;

        float mask = 1.0 - step(clover_base, (dot(grass_base, 1.0) / 3.0));
        vec3 albedo = normal(clover_colour, grass_soil_blend, mask);

        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }

    if (params.stage == 4.0) {
        float clover_mask = step(imageLoad(r16f_buffer_0, ivec2(pixel)).r, (dot(imageLoad(r16f_buffer_1, ivec2(pixel)).r, 1.0) / 3.0));

        vec3 soil_normals = sobel_filter(ivec2(pixel), 0.5, 0);
        vec3 grass_normals = sobel_filter(ivec2(pixel), 1.0, 1);
        vec3 clover_normals = sobel_filter(ivec2(pixel), 2.0, 2);

        vec3 grass_soil_rnm = normal_rnm_blend(soil_normals, grass_normals, 0.5);
        vec3 normals = normal_rnm_blend(grass_soil_rnm, clover_normals, clover_mask);

        if (params.normals_format == 0.0) {
            vec3 opengl_normals = normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        }
        
        if (params.normals_format == 1.0) {
            vec3 directx_normals = normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }

        float gs = max(normals.r, max(normals.g, normals.b));
        float occlusion = 1.0 - clamp((gs - ao_tone_value) / ao_tone_width + 0.5, 0.0, 1.0);
        float roughness = 1.0 - clamp((gs - roughness_tone_value) / roughness_tone_width + 0.5, 0.0, 1.0);

        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(occlusion, roughness, 0.0), 1.0));
    }
}