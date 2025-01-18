class_name UIManager
extends Control

@export var file_menu : MenuButton
@export var pause_renderer_btn : Button

# Some UI elements are disabled until an asset is loaded.
func enable_full_ui() -> void:
	file_menu.get_popup().set_item_disabled(10, false)
	pause_renderer_btn.disabled = false
