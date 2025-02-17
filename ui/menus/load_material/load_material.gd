class_name LoadMaterialMenu
extends FileDialog

var params_container : ParamSection


func _on_file_selected(path: String) -> void:
	var material_settings : Array[Array] = DataManager.load_material_settings(path)
	params_container.load_serialised_properties(material_settings)
	queue_free()


func _on_canceled() -> void:
	queue_free()
