class_name ExportTemplate
extends RefCounted


static func get_export_template_data(output_template : int) -> Array[Array]:
	match output_template:
		0:
			return [
				[0, Image.FORMAT_RGBAF, "_baseColor"],
				[5, Image.FORMAT_RGBAH, "_occlusionRoughnessMetallic"],
				[4, Image.FORMAT_RGBAH, "_normal"],
			]
		1:
			return [
				[0, Image.FORMAT_RGBAH, "_baseColor"],
				[1, Image.FORMAT_RGBAH, "_occlusion"],
				[2, Image.FORMAT_RGBAH, "_roughness"],
				[3, Image.FORMAT_RH, "_metallic"],
				[4, Image.FORMAT_RGBAH, "_normal"],
			]
		_:
			return []
