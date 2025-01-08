extends MenuButton

@export var export_menu_scene : PackedScene

enum MenuOption {
	NEW,
	OPEN,
	RECENT,
	SAVE,
	SAVE_AS,
	IMPORT_MATERIAL,
	IMPORT_MESH,
	EXPORT,
	QUIT
}


func _ready() -> void:
	@warning_ignore("return_value_discarded")
	get_popup().id_pressed.connect(_on_file_menu_button_pressed)
	
	
func _on_file_menu_button_pressed(button_id : int) -> void:
	match button_id:
		MenuOption.EXPORT:
			var export_menu : Window = export_menu_scene.instantiate()
			add_child(export_menu)
		MenuOption.QUIT:
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			get_tree().quit()
