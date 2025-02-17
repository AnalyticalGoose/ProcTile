extends MenuButton

@export var export_menu_scene : PackedScene
@export var load_material_menu_scene : PackedScene
@export var save_material_menu_scene : PackedScene
@export var params_container : ParamSection

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
		MenuOption.OPEN:
			var load_material_menu : LoadMaterialMenu = load_material_menu_scene.instantiate()
			load_material_menu.params_container = params_container
			add_child(load_material_menu)
			load_material_menu.show()
		
		MenuOption.SAVE_AS:
			var save_material_menu : SaveMaterialMenu = save_material_menu_scene.instantiate()
			save_material_menu.params_container = params_container
			add_child(save_material_menu)
			save_material_menu.show()
			
			#var test_path : String = "C:/Users/Harry/Desktop/Painter/ProcTileTest"
			#var properties_state : Array[Array] = params_container.serialise_properties()
			#DataManager.save_material_settings(test_path, properties_state)
		
		MenuOption.EXPORT:
			var export_menu : Window = export_menu_scene.instantiate()
			add_child(export_menu)
		
		MenuOption.QUIT:
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			get_tree().quit()
