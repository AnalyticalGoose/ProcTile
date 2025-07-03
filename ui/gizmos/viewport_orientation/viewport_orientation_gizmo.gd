extends Node3D

signal GizmoClicked(idx: int)

@export var x_axis_sprite: Sprite3D
@export var x_axis_mesh: MeshInstance3D
@export var y_axis_sprite: Sprite3D
@export var y_axis_mesh: MeshInstance3D
@export var z_axis_sprite: Sprite3D
@export var z_axis_mesh: MeshInstance3D


func _on_x_axis_area_3d_mouse_entered() -> void:
	x_axis_sprite.set_modulate(Color(0.945, 0.386, 0.362))
	((x_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.945, 0.386, 0.362))

func _on_x_axis_area_3d_mouse_exited() -> void:
	x_axis_sprite.set_modulate(Color(0.748, 0.194, 0.197))
	((x_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.748, 0.194, 0.197))


func _on_x_axis_area_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event.is_action_pressed("left_click"):
		GizmoClicked.emit(0)
	else:
		return


func _on_y_axis_area_3d_mouse_entered() -> void:
	y_axis_sprite.set_modulate(Color(0.578, 0.771, 0.374))
	((y_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.578, 0.771, 0.374))


func _on_y_axis_area_3d_mouse_exited() -> void:
	y_axis_sprite.set_modulate(Color(0.438, 0.611, 0.111))
	((y_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.438, 0.611, 0.111))


func _on_y_axis_area_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event.is_action_pressed("left_click"):
		GizmoClicked.emit(1)
	else:
		return


func _on_z_axis_area_3d_mouse_entered() -> void:
	z_axis_sprite.set_modulate(Color(0.391, 0.582, 0.933))
	((z_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.391, 0.582, 0.933))


func _on_z_axis_area_3d_mouse_exited() -> void:
	z_axis_sprite.set_modulate(Color(0.144, 0.395, 0.849))
	((z_axis_mesh.mesh as BoxMesh).material as StandardMaterial3D).set_albedo(Color(0.144, 0.395, 0.849))


func _on_z_axis_area_3d_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event.is_action_pressed("left_click"):
		GizmoClicked.emit(2)
	else:
		return
