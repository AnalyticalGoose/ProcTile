shader_type spatial;

uniform sampler2D albedo_input;
uniform sampler2D occlusion_input;
uniform sampler2D roughness_input;
uniform sampler2D metallic_input;
uniform sampler2D normal_input;


void fragment() {
	vec4 albedo_tex = texture(albedo_input, UV);
	vec4 roughness_tex = texture(roughness_input, UV);
	vec4 normal_tex = texture(normal_input, UV);
	vec4 occlusion_tex = texture(occlusion_input, UV);

	ALBEDO = albedo_tex.rgb;
	ROUGHNESS = roughness_tex.r;
	NORMAL_MAP = normal_tex.rgb;
	AO = occlusion_tex.r;
}
