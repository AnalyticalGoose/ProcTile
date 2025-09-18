class_name LoadMaterialMenu
extends FileDialog

var asset_manager : AssetsManager
var params_container : ParamSection


# Blacklist approach, not a strong safety solution but better than nothing and will dissuade script kiddies,
# Will await further satefy features from Godot - https://github.com/godotengine/godot/issues/80562
func _validate_file(path: String) -> bool:
	var file : FileAccess = FileAccess.open(path, FileAccess.READ)
	if file.get_length() >= 1000: # Check file isn't larger than expected (bundled with code)
		return false
	var file_s : String = file.get_as_text()
	if file_s.contains("Object") or file_s.contains("_init()") or file_s.contains("RefCounted"):
		return false
	file.close()
	return true


func _on_file_selected(path: String) -> void:
	if not _validate_file(path):
		Logger.puts_warning("Potentially unsafe file blocked from loading")
		return
	
	var cfg_file : ConfigFile = ConfigFile.new()
	if cfg_file.load(path):
		Logger.puts_error("Cannot find user settings at" + path)
		
	var id : int = cfg_file.get_value("compatibility", "material_id")
	
	if DataManager.current_material_id != id:
		var material_result : Array[int] = DataManager.get_material_index_from_id(id)
		var valid_index : bool = material_result[0] as bool
		if valid_index:
			var index : int = material_result[1]
			var material_type : int = cfg_file.get_value("compatibility", "material_type")
			asset_manager.change_asset_filter(material_type)
			asset_manager.assets_filter.select(material_type)
			asset_manager.load_material(index, true)
			
			# Ensures UI is setup and prevent crashes from trying to access null
			for i : int in 2:
				await get_tree().process_frame 
		
		else:
			Logger.puts_error("Invalid index in save file, cannot load")
			return

	var material_settings : Array[Array] = DataManager.load_material_settings(cfg_file)
	DataManager.current_save_path = path
	params_container.load_serialised_properties(material_settings)
	asset_manager.compute_shader.stage = 0 # force shader to reset
	queue_free()


func _on_canceled() -> void:
	queue_free()
