class_name MaterialDataLoader
extends RefCounted

static var asset_manager: AssetsManager
static var params_container: ParamSection
static var material_props: Array[Array]


static func load_material_from_data(id: int, type: int, _ver: String, props: Array) -> void:
	material_props = props
	
	if DataManager.current_material_id != id:
		var material_result: Array[int] = DataManager.get_material_index_from_id(id)
		var valid_index: bool = material_result[0] as bool
		if valid_index:
			var index: int = material_result[1]
			asset_manager.change_asset_filter(type)
			asset_manager.assets_filter.select(type)
			asset_manager.load_material(index, true)
		else:
			Logger.puts_error("Invalid index in save file, cannot load")
			return
	else:
		load_serialised_material_props()


static func load_serialised_material_props() -> void:
	if material_props:
		params_container.load_serialised_properties(material_props)
		asset_manager.compute_shader.stage = 0 # force shader to reset
