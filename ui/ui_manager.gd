class_name UIManager
extends Control

@export var undo_btn : Button
@export var redo_btn : Button
@export var file_menu : FileMenu
@export var pause_renderer_btn : Button
@export var params_container : ParamSection


func  _ready() -> void:
	Logger.ui_manager_instance = self
	print_orphan_nodes()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("save"):
		if DataManager.current_save_path != "":
			var properties_state : Array[Array] = params_container.serialise_properties()
			DataManager.save_material(DataManager.current_save_path, properties_state)
		else:
			file_menu.save_as()
	
	elif event.is_action_pressed("undo"):
		if !undo_btn.disabled:
			ActionsManager.undo_action()
	
	elif event.is_action_pressed("redo"):
		if !redo_btn.disabled:
			ActionsManager.redo_action()


# Some UI elements are disabled until an asset is loaded.
func enable_full_ui() -> void:
	file_menu.get_popup().set_item_disabled(10, false)
	pause_renderer_btn.disabled = false
