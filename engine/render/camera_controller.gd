extends Control

const ORBIT_SPEED : float = 0.01

@onready var camera : Camera3D = $/root/ProcTile/Renderer/CameraPivot/Camera3D as Camera3D
@onready var camera_pivot : Node3D = $/root/ProcTile/Renderer/CameraPivot as Node3D
@onready var mesh : MeshInstance3D = $/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D
@onready var mesh_pivot : Node3D = $/root/ProcTile/Renderer/MeshPivot as Node3D

var mouse_in_render_view : bool = true


func _input(event: InputEvent) -> void:
	if mouse_in_render_view:
		if Input.is_action_pressed("zoom_in"):
			camera.position.z = clamp(camera.position.z * 0.90, 0.1, 20.0)
		elif Input.is_action_pressed("zoom_out"):
			camera.position.z = clamp(camera.position.z * 1.1, 0.1, 20.0)
			
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and event is InputEventMouseMotion:
			camera_pivot.rotate_y(-(event as InputEventMouseMotion).relative.x * ORBIT_SPEED)  # Rotate horizontally
			camera_pivot.rotate_x(-(event as InputEventMouseMotion).relative.y * ORBIT_SPEED)  # Rotate vertically
			camera_pivot.rotation.z = 0


func _on_mouse_entered() -> void:
	mouse_in_render_view = true


func _on_mouse_exited() -> void:
	mouse_in_render_view = false
