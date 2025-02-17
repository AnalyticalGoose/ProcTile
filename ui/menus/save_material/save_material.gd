class_name SaveMaterialMenu
extends FileDialog

var params_container : ParamSection


func _on_file_selected(path: String) -> void:
	print(path)
	var properties_state : Array[Array] = params_container.serialise_properties()
	DataManager.save_material(path, properties_state)
	queue_free()


func _on_canceled() -> void:
	queue_free()
