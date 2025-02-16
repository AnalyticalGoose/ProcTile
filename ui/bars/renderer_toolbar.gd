extends Node

@export var undo_btn : Button
@export var redo_btn : Button
@export var pause_btn : Button
@export var pause_icon : CompressedTexture2D
@export var play_icon : CompressedTexture2D
@export var mesh_btn : Button

@export var mesh_settings : MeshSettings
@export var shader_settings : PanelContainer
@export var camera_settings : PanelContainer

@onready var renderer : Renderer = $/root/ProcTile/Renderer


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


func _on_mesh_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		mesh_settings.show()
	else:
		mesh_settings.hide()


func _on_shader_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		shader_settings.show()
	else:
		shader_settings.hide()


func _on_camera_settings_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		camera_settings.show()
	else:
		camera_settings.hide()


func _on_undo_btn_pressed() -> void:
	ActionsManager.undo_action()


func _on_redo_btn_pressed() -> void:
	ActionsManager.redo_action()
