#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;

layout(r16f, set = 1, binding = 0) uniform image2D r16f_buffer;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float voronoi_seed;
	float voronoi_col;
} seed;

layout(push_constant, std430) uniform restrict readonly Params {
	float type;
	float tone_value;
	float tone_width;
	float invert;
	float tile_count;
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


// Random / noise functions
float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 rand3(vec2 x) {
    return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
							  dot(x, vec2(3.4562, 17.398)),
                              dot(x, vec2(13.254, 5.867))), vec3(3.14, 3.14, 3.14))) * 43758.5);
}


// Voronoi distances by Inigo Quilez - https://www.shadertoy.com/view/ldl3W8, https://www.youtube.com/c/InigoQuilez, https://iquilezles.org/
// Faster Voronoi Edge Distance by Tomkh - https://www.shadertoy.com/view/llG3zy
vec3 voronoi_edge_distance(vec2 x, float size, float seed, bool early_return) {
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

	if (early_return == true) {
		return vec3(md, mr);
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

vec2 voronoi(vec2 x, float size, float seed) {
    vec2 _size = vec2(size);
    vec2 n = floor(x);
    vec2 f = fract(x);

	vec3 m = vec3( 8.0 );
    for( int j=-1; j<=1; j++ )
    for( int i=-1; i<=1; i++ )
    {
        vec2  g = vec2( float(i), float(j) );
        vec2  o = hash_ws2(vec2(seed) + mod(n + g + _size, _size));
      	vec2  r = g - f + o;
		float d = dot( r, r );
        if( d<m.x ) {
        	m = vec3( d, o );
		}
    }
    return vec2( sqrt(m.x), m.y+m.z );
}

void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
		vec2 p = uv * params.tile_count;
		p = mod(p, params.tile_count) * cell_scale;

		vec3 _output;
		int _type = int(params.type);

		switch(_type) {
			case 0:
				float voronoi_basic = voronoi(p, cell_count, seed.voronoi_seed).x;
				_output = vec3(voronoi_basic);
				break;
			case 1:
				float voronoi_smooth = voronoi_edge_distance(p, cell_count, seed.voronoi_seed, true).r;
				_output = vec3(voronoi_smooth);
				break;
			case 2:
				float voronoi_flat = voronoi(p, cell_count, seed.voronoi_seed).y;
				_output = vec3(voronoi_flat * 0.5);
				break;
			case 3:
				float voronoi_col = voronoi(p, cell_count, seed.voronoi_seed).y;
				_output = mix(vec3(0.0, 0.0, 0.0), rand3(vec2(float((seed.voronoi_col)), voronoi_col)), step(0.0000001, dot(voronoi_col, 1.0)));
				break;
			case 4:
				float voronoi_edge = voronoi_edge_distance(p, cell_count, seed.voronoi_seed, false).r;
				_output = vec3(voronoi_edge);
				break;
			case 5:
				vec3 voronoi_3d = voronoi_edge_distance(p, cell_count, seed.voronoi_seed, false);
				_output = voronoi_3d;
				break;
		}

		vec3 albedo = clamp((_output - params.tone_value) / params.tone_width + 0.5, 0.0, 1.0);

		if (params.invert == 1.0) {
			albedo = 1.0 - albedo;
		}

		imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }
}