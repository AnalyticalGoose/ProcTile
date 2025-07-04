class_name WindowMenu
extends MenuButton

enum MenuOption {
	ORIENTATION_GIZMO,
}

@export var orientation_gizmo_rect: TextureRect

var popup_menu: PopupMenu


func _ready() -> void:
	popup_menu = get_popup()
	@warning_ignore("return_value_discarded")
	popup_menu.id_pressed.connect(_on_file_menu_button_pressed)
	popup_menu.set_hide_on_checkable_item_selection(false)


func _on_file_menu_button_pressed(button_id : int) -> void:
	match button_id:
		MenuOption.ORIENTATION_GIZMO:
			popup_menu.toggle_item_checked(button_id)
			if popup_menu.is_item_checked(button_id):
				orientation_gizmo_rect.show()
			else:
				orientation_gizmo_rect.hide()
