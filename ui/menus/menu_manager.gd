extends HBoxContainer

@export var file_menu : MenuButton

# Temporary
func enable_export() -> void:
	file_menu.get_popup().set_item_disabled(10, false)
