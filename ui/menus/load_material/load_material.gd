class_name LoadMaterialMenu
extends FileDialog

var asset_manager : AssetsManager
var params_container : ParamSection


func _on_file_selected(path: String) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	if cfg_file.load(path):
		Logger.puts_error("Cannot find user settings at" + path)
	
	var id : int = cfg_file.get_value("compatibility", "material_id")
	if DataManager.current_material_id != id:
		var index : int = DataManager.get_material_index_from_id(id)
		if index:
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
	queue_free()


func _on_canceled() -> void:
	queue_free()
