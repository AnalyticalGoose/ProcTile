#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : require

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(derivative_group_quadsNV) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(r16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D rgba32f_buffer;
layout(r16f, set = 1, binding = 1) uniform image2D noise_buffer;
layout(r16f, set = 1, binding = 2) uniform image2D mask_buffer;

layout(push_constant, std430) uniform restrict readonly Params {
    float normals_format;
	float texture_size;
	float stage;
} params;


// Normal map
const float sobel_strength = 0.05;


float rand(vec2 x) {
	return fract(sin(dot(x, vec2(12.9898, 78.233))) * 43758.5453);
}


vec2 rand2(vec2 x) {
    return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
						      dot(x, vec2(3.4562, 17.398))), vec2(3.14, 3.14))) * 43758.5);
}



float multiply(float base, float blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}

float normal(float base, float blend, float opacity) {
	return opacity * base + (1.0 - opacity) * blend;
}


float clamped_difference(float base, float blend) {
    return clamp(blend - base, 0.0, 1.0);
}


float blendSubstract(float base, float blend) {
	return max(base+blend-1.0,0.0);
}


float blendLinearBurn(float base, float blend) {
	// Note : Same implementation as BlendSubtractf
	return max(base+blend-1.0,0.0);
}

float blendLinearDodge(float base, float blend) {
	// Note : Same implementation as BlendAddf
	return min(base+blend,1.0);
}

float blendLinearLight(float base, float blend) {
	return blend<0.5?blendLinearBurn(base,(2.0*blend)):blendLinearDodge(base,(2.0*(blend-0.5)));
}

vec3 blendLinearLight(vec3 base, vec3 blend) {
	return vec3(blendLinearLight(base.r,blend.r),blendLinearLight(base.g,blend.g),blendLinearLight(base.b,blend.b));
}

vec3 blendLinearLight(vec3 base, vec3 blend, float opacity) {
	return (blendLinearLight(base, blend) * opacity + base * (1.0 - opacity));
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







float sdf_lens(vec2 p, float width, float height)
{
    // Vesica SDF based on Inigo Quilez
    float d = height / width - width / 4.0;
    float r = width / 2.0 + d;
    
    p = abs(p);

    float b = sqrt(r * r - d * d);
    vec4 par = p.xyxy - vec4(0.0, b, -d, 0.0);
    return (par.y * d > p.x * b) ? length(par.xy) : length(par.zw) - r;
}

vec3 tile_weave(vec2 pos, vec2 scale, float count, float width, float smoothness) {
    vec2 i = floor(pos * scale);    
    float c = mod(i.x + i.y, 2.0);
    
    vec2 p = fract(pos.st * scale);
    p = mix(p.st, p.ts, c);
    p = fract(p * vec2(count, 1.0));
    
    width *= 2.0;
    p = p * 2.0 - 1.0;
    float d = sdf_lens(p, width, 1.0);
    vec2 grad = vec2(dFdx(d), dFdy(d));

    float s = 1.0 - smoothstep(0.0, dot(abs(grad), vec2(1.0)) + smoothness, -d);
    return vec3(s, normalize(grad) * smoothstep(1.0, 0.99, s) * smoothstep(0.0, 0.01, s)); 
}


float map_bw_colours(float x, float col_white, float col_black) {
    if (x < 1.0) {
        return col_black;
    }
    else {
        return col_white;
    }
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


// Reorientated Normal Mapping - Stephen Hill & Colin Barre-Brisebois - https://blog.selfshadow.com/publications/blending-in-detail/
// https://www.shadertoy.com/view/4t2SzR
// Version with opacity adjust
vec3 normal_rnm_blend(vec3 n1, vec3 n2, float opacity) {
    n1.z = 1.0 - n1.z;
    n2.z = 1.0 - n2.z;

    n1 = n1 * vec3(2.0) + vec3(-1.0, -1.0, 0.0);
    vec3 base = n2 * 2.0 - 1.0;
    vec3 blended = n1 * dot(n1, n2) / n1.z + vec3(base.x, base.y, -base.z);
    vec3 rnm = mix(base, blended, opacity);

    rnm.z = -rnm.z; 
    return rnm * 0.5 + 0.5;
}



float sample_bilinear(ivec2 base_coord, vec2 offset) {
    vec2 p = vec2(base_coord) + offset;
    ivec2 ip = ivec2(floor(p));
    vec2 f = fract(p);
    // Load the four neighboring pixels.
    float a = imageLoad(mask_buffer, ip).r;
    float b = imageLoad(mask_buffer, ip + ivec2(1, 0)).r;
    float c = imageLoad(mask_buffer, ip + ivec2(0, 1)).r;
    float d = imageLoad(mask_buffer, ip + ivec2(1, 1)).r;
    // Bilinear mix.
    float lerp1 = mix(a, b, f.x);
    float lerp2 = mix(c, d, f.x);
    return mix(lerp1, lerp2, f.y);
}

float gaussian_blur(ivec2 pixel_coords, float sigma, int quality) {
    float samples = sigma * 4.0;
    
    // Optionally use a LOD factor to step by more than 1 pixel. Mimics using a lower resolution mip level.
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
//////

const float tile_scale = 10.0; 

const float brushed_scale = 30.0;
const float bump_scale = 5.0;
const float noise_blend = 1.0;


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
        float fbm_brushed =  fbm_perlin_2d(uv, vec2(1.0, brushed_scale), 10, 1.0, 0.0, 0.0);
        imageStore(noise_buffer, ivec2(pixel), vec4(vec3(fbm_brushed), 1.0));

        float fbm_bump = fbm_perlin_2d(uv, vec2(bump_scale), 10, 1.0, 0.0, 0.0);
        float fbm_blend = multiply(fbm_bump, fbm_brushed, 1.0); // may wish to reverse args

        imageStore(rgba32f_buffer, ivec2(pixel), vec4(vec3(fbm_blend), noise_blend));
    }

    if (params.stage == 1.0) {
        vec3 tile_weave = tile_weave(uv, vec2(tile_scale), 3.0, 0.4, 0.4);
        vec2 gradient = vec2(tile_weave.y, tile_weave.z);
        vec3 checker_normals = normalize(vec3(-gradient, -1.0));
        checker_normals = checker_normals * 0.5 + 0.5;
        vec3 noise_normals = sobel_filter(ivec2(pixel), sobel_strength, params.texture_size);

        float checker_min = 1.0 - min(checker_normals.r, min(checker_normals.g, checker_normals.b));
        float checker_mask = map_bw_colours(checker_min, 1.0, 0.0);
        imageStore(mask_buffer, ivec2(pixel), vec4(vec3(1.0 - checker_mask), 1.0));

        float blend_opacity = 0.25 * dot(checker_mask, 1.0);
        vec3 blended_normals = normal_rnm_blend(noise_normals, checker_normals, blend_opacity);
        
        if (params.normals_format == 0.0) {
            vec3 opengl_normals = blended_normals * vec3(-1.0, 1.0, -1.0) + vec3(1.0, 0.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(opengl_normals, 1.0));
        } 
        else if (params.normals_format == 1.0) {
            vec3 directx_normals = blended_normals * vec3(-1.0, -1.0, -1.0) + vec3(1.0, 1.0, 1.0);
            imageStore(normal_buffer, ivec2(pixel), vec4(directx_normals, 1.0));
        }

        float fbm_brushed = imageLoad(noise_buffer, ivec2(pixel)).r;
        float a_blend_opac = 0.2 * dot(checker_mask, 1.0);
        vec3 albedo = blendLinearLight(vec3(0.789), vec3(fbm_brushed), a_blend_opac);
        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }

    if (params.stage == 2.0) {
        float mask = imageLoad(mask_buffer, ivec2(pixel)).r;
        
        float blur = gaussian_blur(ivec2(pixel), 15.0, 1);
        float occlusion = 1.0 - clamped_difference(mask, blur);

        float bar_roughness = 0.7;
        float plate_roughness = 0.35;
        float roughness_opacity = min(1.0, -mask + 1.0);
        float roughness = normal(plate_roughness, bar_roughness, roughness_opacity);

        float metallic = 0.9;

        imageStore(occlusion_buffer, ivec2(pixel), vec4(vec3(occlusion), 1.0));
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(roughness), 1.0));
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(metallic), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(occlusion, roughness, metallic, 1.0));
    }
}

