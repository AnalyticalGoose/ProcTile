#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;
layout(rgba16f, set = 0, binding = 1) uniform image2D occlusion_buffer;
layout(rgba16f, set = 0, binding = 2) uniform image2D roughness_buffer;
layout(rgba16f, set = 0, binding = 3) uniform image2D metallic_buffer;
layout(rgba16f, set = 0, binding = 4) uniform image2D normal_buffer;
layout(rgba16f, set = 0, binding = 5) uniform image2D orm_buffer;

layout(rgba32f, set = 1, binding = 0) uniform image2D r16f_buffer_1;

layout(set = 2, binding = 0, std430) buffer readonly Seeds {
    float strand_seed;
} seed;

layout(set = 3, binding = 0, std430) buffer readonly HCol {
    vec4 h_col;
};

layout(set = 4, binding = 0, std430) buffer readonly VCol {
    vec4 v_col;
};

layout(push_constant, std430) uniform restrict readonly Params {
    float weave_size_x;
    float weave_size_y;
    float weave_stitch;
    float clearcoat;
    float carbon_strands;
    float roughness;
    float metalness;
    float normals_strength;
    float normals_format;
	float texture_size;
	float stage;
} params;


const float PI = 3.1415926;
const float carbon_brightness = 0.35;
const float carbon_contrast = 0.06;
const float vertical_blend_opacity = 0.65;
const float horizontal_blend_opacity = 0.89;


// Hash wihtout Sine - Dave Hoskins - https://www.shadertoy.com/view/4djSRW
float hash11(float p) {
    p = fract(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float normal(float base, float blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

vec3 normal(vec3 base, vec3 blend, float opacity) {
    return opacity * base + (1.0 - opacity) * blend;
}

vec3 multiply(vec3 base, vec3 blend, float opacity) {
	return opacity * base * blend + (1.0 - opacity) * blend;
}


vec2 lines_noise(vec2 uv, float lines, float seed) {
    int band_x = int(floor(uv.x * lines));
	int band_y = int(floor(uv.y * lines));
    return vec2(hash11(float(band_x) + seed), hash11(band_y) + seed);
}


// Adapted from Material Maker weave node - RodZill4 - https://github.com/RodZill4/material-maker/blob/master/addons/material_maker/nodes/weave.mmg
vec3 weave(vec2 uv, vec2 count, float stitch) {
    vec2 grid = (uv * stitch) * count;
    vec2 id   = floor(grid); // cell coords
    vec2 f    = fract(grid); // cell position

    float weave1 = sin(PI / stitch * (grid.x + id.y - (stitch - 1.0))) * 0.25 + 0.75;
    float weave2 = sin(PI / stitch * (grid.y + id.x + 1.0)) * 0.25 + 0.75;
    float maskY = step(abs(f.y - 0.5), 0.5);
    float maskX = step(abs(f.x - 0.5), 0.5);
    
    float c1 = weave1 * maskY;
    float c2 = weave2 * maskX;
    bool horiz = c1 > c2;
    bool vert  = c2 > c1;

    return vec3(max(c1, c2), vert ? 1.0 : 0.0, horiz ? 1.0 : 0.0);
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
    rv += vec2(1.0, -1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(e.x, e.y))).r;
    rv += vec2(-1.0, 1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(e.x, e.y))).r;
    rv += vec2(1.0, 1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(e.x, -e.y))).r;
    rv += vec2(-1.0, -1.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(e.x, -e.y))).r;  
    rv += vec2(2.0, 0.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(2, 0))).r;
    rv += vec2(-2.0, 0.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(2, 0))).r;
    rv += vec2(0.0, 2.0) * imageLoad(r16f_buffer_1, wrap_coord(coord + ivec2(0, 2))).r;
    rv += vec2(0.0, -2.0) * imageLoad(r16f_buffer_1, wrap_coord(coord - ivec2(0, 2))).r;

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
        
        float _roughness = params.roughness;

        if (params.clearcoat == 1.0) {
            _roughness *= 0.3;
        }

        imageStore(occlusion_buffer, ivec2(pixel), vec4(1.0));
        imageStore(roughness_buffer, ivec2(pixel), vec4(vec3(_roughness), 1.0));
        imageStore(metallic_buffer, ivec2(pixel), vec4(vec3(params.metalness), 1.0));
        imageStore(orm_buffer, ivec2(pixel), vec4(vec3(1.0, _roughness, params.metalness), 1.0));
    }

    if (params.stage == 1.0) {
		vec2 strands = lines_noise(uv, params.carbon_strands, seed.strand_seed);
        vec2 strands_lightened = clamp(strands * carbon_contrast + carbon_brightness + 0.5 * (1.0 - carbon_contrast), 0.0, 1.0);
        
        vec3 weave = weave(uv, vec2(params.weave_size_x, params.weave_size_y), params.weave_stitch);
        float pattern = weave.x;
        float h_mask = weave.y;
        float v_mask = weave.z;

        float vertical_weave_blend = normal(pattern, strands_lightened.x, h_mask * vertical_blend_opacity);
        float horizontal_weave_blend = normal(pattern, strands_lightened.y, v_mask * horizontal_blend_opacity);          
        float weave_blend = normal(vertical_weave_blend, horizontal_weave_blend, h_mask);
        imageStore(r16f_buffer_1, ivec2(pixel), vec4(vec3(weave_blend), 1.0));

        vec3 _h_col = multiply(h_col.rgb, vec3(strands_lightened.y), v_mask);
        vec3 _v_col = multiply(v_col.rgb, vec3(strands_lightened.x), h_mask);
        vec3 base_col = normal(_h_col, _v_col, v_mask);
        vec3 albedo = multiply(vec3(weave_blend), base_col, 1.0);
        imageStore(albedo_buffer, ivec2(pixel), vec4(albedo, 1.0));
    }

    if (params.stage == 2.0) {
        float _normals_strength = params.normals_strength;

        if (params.clearcoat == 1.0) {
            _normals_strength *= 0.1;
        }

        vec3 normals = sobel_filter(ivec2(pixel), _normals_strength);

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