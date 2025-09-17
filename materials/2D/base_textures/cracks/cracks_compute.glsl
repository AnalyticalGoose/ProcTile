#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D albedo_buffer;

layout(r16f, set = 1, binding = 0) uniform restrict image2D r16f_buffer;

layout(set = 2, binding = 0, std430) buffer restrict readonly Seeds {
	float uv_perlin_seed;
    float cracks_voronoi_seed;
	float mask_perlin_seed;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
	float tile_count;
	float uv_perlin_x;
	float uv_perlin_y;
	float uv_perlin_iterations;
	float uv_perlin_persistence;
	float cracks_coverage;
	float mask_enabled;
	float mask_perlin_x;
	float mask_perlin_y;
	float mask_perlin_iterations;
	float mask_perlin_persistence;
	float tone_value;
	float tone_width;
    float normals_format_unused;
	float texture_size;
	float stage;
} params;

float cell_count = params.tile_count; // in-case of need for different cell_count
const float cell_scale = 1.0;


// Adapted from 'Hash without Sine' by David Hoskins - https://www.shadertoy.com/view/4djSRW
vec2 hash_ws2(vec2 x) {
    vec3 x3 = fract(vec3(x.xyx) * vec3(0.1031, 0.1030, 0.0973));
    x3 += dot(x3, x3.yzx + 19.19);
    return fract(vec2((x3.x + x3.y)  *x3.z, (x3.x + x3.z) * x3.y));
}


uint murmurHash12(uvec2 src) {
    const uint M = 0x5bd1e995u;
    uint h = 1190494759u;
    src *= M; src ^= src>>24u; src *= M;
    h *= M; h ^= src.x; h *= M; h ^= src.y;
    h ^= h>>13u; h *= M; h ^= h>>15u;
    return h;
}

float hash12(vec2 src) {
    uint h = murmurHash12(floatBitsToUint(src));
    return uintBitsToFloat(h & 0x007fffffu | 0x3f800000u) - 1.0;
}

uvec2 murmurHash22(uvec2 src) {
    const uint M = 0x5bd1e995u;
    uvec2 h = uvec2(1190494759u, 2147483647u);
    src *= M; src ^= src>>24u; src *= M;
    h *= M; h ^= src.x; h *= M; h ^= src.y;
    h ^= h>>13u; h *= M; h ^= h>>15u;
    return h;
}

vec2 hash22(vec2 src) {
    uvec2 h = murmurHash22(floatBitsToUint(src));
    return uintBitsToFloat(h & 0x007fffffu | 0x3f800000u) - 1.0;
}


float lighten(float base, float blend) {
	return max(blend, base);
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
    vec2 o = floor(coord) + hash22(vec2(seed, 1.0 - seed)) + size;
    vec2 f = fract(coord);

    float a[4];
    a[0] = hash12(mod(o, size)) * 6.28318530718 + offset * 6.28318530718;
    a[1] = hash12(mod(o + vec2(0.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[2] = hash12(mod(o + vec2(1.0, 0.0), size)) * 6.28318530718 + offset * 6.28318530718;
    a[3] = hash12(mod(o + vec2(1.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;

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

float map_bw_colours(float x, float limit) {
    if (x < limit) {
        return mix(1.0, 0.0, (x - limit) / -limit);
    }
    return 1.0;
}


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
		vec2 _uv_perlin_size = vec2(params.uv_perlin_x, params.uv_perlin_y);
		vec2 _mask_perlin_size = vec2(params.mask_perlin_x, params.mask_perlin_y);

		float uv_perlin = fbm_perlin_2d(uv, _uv_perlin_size, int(params.uv_perlin_iterations), params.uv_perlin_persistence, 0.0, seed.uv_perlin_seed);
        vec2 crack_warped_uv = uv -= vec2(0.04 * (2.0 * uv_perlin - 1.0));
		
		vec2 p = crack_warped_uv * params.tile_count;
		p = mod(p, params.tile_count) * cell_scale;

        vec3 cracks_voronoi = voronoi(p, cell_count, seed.cracks_voronoi_seed);
        float cracks = clamp((cracks_voronoi.r - params.tone_value) / params.tone_width + 0.5, 0.0, 1.0);

		if (params.mask_enabled == 1) {
			float mask_perlin = fbm_perlin_2d(uv, _mask_perlin_size, int(params.mask_perlin_iterations), params.mask_perlin_persistence, 0.0, seed.mask_perlin_seed);
			float cracks_mask = map_bw_colours(mask_perlin, params.cracks_coverage);
			float cracks_lightened = lighten(cracks_mask, cracks);

			imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(cracks_lightened), 1.0));
		}

		else if (params.mask_enabled == 0) {
			imageStore(albedo_buffer, ivec2(pixel), vec4(vec3(cracks), 1.0));
		}
    }
}