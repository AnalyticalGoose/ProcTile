#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D albedo_buffer;


layout(push_constant, std430) uniform restrict readonly Params {
	float texture_size;
	float stage;
} params;


void main() {
	vec2 pixel = gl_GlobalInvocationID.xy;
	vec2 _texture_size = vec2(params.texture_size);
	vec2 uv = pixel / _texture_size;

    if (params.stage == 0.0) {
    
    }
}