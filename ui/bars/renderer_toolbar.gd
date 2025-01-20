extends Node

@export var pause_btn : Button
@export var pause_icon : CompressedTexture2D
@export var play_icon : CompressedTexture2D
@export var mesh_btn : Button
@export var mesh_settings : MeshSettings

@onready var renderer : Renderer = $/root/ProcTile/Renderer


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
