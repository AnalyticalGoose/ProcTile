extends Node

@export var undo_btn: Button
@export var redo_btn: Button
@export var pause_btn: Button
@export var pause_icon: CompressedTexture2D
@export var play_icon: CompressedTexture2D
@export var mesh_btn: Button
@export var lighting_btn: Button

@export var lighting_settings: LightingSettings
@export var mesh_settings: MeshSettings
@export var shader_settings: PanelContainer
@export var camera_settings: PanelContainer

enum SettingsType {
	LIGHTING,
	MESH,
	CAMERA,
}


var open_menu: PanelContainer

@onready var renderer: Renderer = $/root/ProcTile/Renderer


func _ready() -> void:
	ActionsManager.undo_btn = undo_btn
	ActionsManager.redo_btn = redo_btn


func _on_pause_renderer_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		renderer.paused = true
		renderer.set_process(false)
		pause_btn.icon = play_icon
	else:
		renderer.paused = false
		renderer.set_process(true)
		pause_btn.icon = pause_icon


func _on_lighting_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		lighting_settings.show()
		if open_menu:
			open_menu.hide()
			(open_menu.get_parent() as Button).set_pressed_no_signal(false)
		open_menu = lighting_settings
	else:
		lighting_settings.hide()
		open_menu = null


func _on_mesh_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		mesh_settings.show()
		if open_menu:
			open_menu.hide()
			(open_menu.get_parent() as Button).set_pressed_no_signal(false)
		open_menu = mesh_settings
	else:
		mesh_settings.hide()
		open_menu = null


func _on_shader_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		shader_settings.show()
		if open_menu:
			open_menu.hide()
			(open_menu.get_parent() as Button).set_pressed_no_signal(false)
		open_menu = shader_settings
	else:
		shader_settings.hide()
		open_menu = null


func _on_camera_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		camera_settings.show()
		if open_menu:
			open_menu.hide()
			(open_menu.get_parent() as Button).set_pressed_no_signal(false)
		open_menu = camera_settings
	else:
		camera_settings.hide()
		open_menu = null


func _on_undo_btn_pressed() -> void:
	ActionsManager.undo_action()


func _on_redo_btn_pressed() -> void:
	ActionsManager.redo_action()


func _on_settings_close_menu(menu_idx: int) -> void:
	open_menu = null
	
	match menu_idx:
		SettingsType.LIGHTING:
			lighting_btn.set_pressed_no_signal(false)
		SettingsType.MESH:
			mesh_btn.set_pressed_no_signal(false)
