shader_type spatial;

uniform sampler2D albedo_input;
uniform sampler2D occlusion_input;
uniform sampler2D roughness_input;
uniform sampler2D metallic_input;
uniform sampler2D normal_input;

uniform bool texture_PBR;
uniform bool placeholder_texture;

// The source-color compiler hint isn't working for the albedo-input for some reason
// so converting manually. I'm unsure if it's a bug or related to using a Texture2DRD
vec4 toLinear(vec4 sRGB) {
	bvec3 cutoff = lessThan(sRGB.rgb, vec3(0.04045));
	vec3 higher = pow((sRGB.rgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
	vec3 lower = sRGB.rgb / vec3(12.92);

	return vec4(mix(higher, lower, cutoff), sRGB.a);
}

void fragment() {
	if (placeholder_texture == true) {
		ALBEDO = vec3(0.2);
		ROUGHNESS = 0.4;
		METALLIC = 1.0;
	}

	else {
		vec4 albedo_tex = texture(albedo_input, UV);
		ALBEDO = toLinear(albedo_tex).rgb;

		if (texture_PBR == true) {
			vec4 occlusion_tex = texture(occlusion_input, UV);
			vec4 roughness_tex = texture(roughness_input, UV);
			vec4 metallic_tex = texture(metallic_input, UV);
			vec4 normal_tex = texture(normal_input, UV);

			AO = occlusion_tex.r;
			ROUGHNESS = roughness_tex.r;
			METALLIC = metallic_tex.r;
			NORMAL_MAP = normal_tex.rgb;
		}
	}
}