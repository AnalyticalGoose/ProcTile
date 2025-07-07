extends Control

const CAMERA_SPEED: float = 0.01

@export var rotation_gizmo: Node3D

var mouse_in_render_view: bool = true
var orbit_speed: float = 1.0
var camera_tween: Tween

@onready var camera: Camera3D = $/root/ProcTile/Renderer/CameraPivot/Camera3D as Camera3D
@onready var camera_pivot: Node3D = $/root/ProcTile/Renderer/CameraPivot as Node3D
@onready var mesh: MeshInstance3D = $/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D
@onready var mesh_pivot: Node3D = $/root/ProcTile/Renderer/MeshPivot as Node3D


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	camera_pivot.rotate_y(orbit_speed * delta)
	rotation_gizmo.rotation = camera_pivot.rotation


func _input(event: InputEvent) -> void:
	if mouse_in_render_view:
		if Input.is_action_pressed("zoom_in"):
			camera.position.z = clamp(camera.position.z * 0.90, 0.1, 20.0)
			
		elif Input.is_action_pressed("zoom_out"):
			camera.position.z = clamp(camera.position.z * 1.1, 0.1, 20.0)
		
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and event is InputEventMouseMotion:
			camera_pivot.rotate_y(-(event as InputEventMouseMotion).relative.x * CAMERA_SPEED)
			camera_pivot.rotation_degrees.x = clamp(
					camera_pivot.rotation_degrees.x - (event as InputEventMouseMotion).relative.y, -89, 89
			)
			# Reset roll so it doesn't accumulate
			camera_pivot.rotation_degrees.z = 0
			
			rotation_gizmo.rotation = camera_pivot.rotation


func _on_mouse_entered() -> void:
	mouse_in_render_view = true
	print("mouse in render view")


func _on_mouse_exited() -> void:
	mouse_in_render_view = false
	print("mouse out render view")


func _on_orbit_mesh_check_box_toggled(toggled_on: bool) -> void:
	if toggled_on:
		set_process(true)
	else:
		set_process(false)


func _on_orbit_speed_h_slider_value_changed(value: float) -> void:
	orbit_speed = value


func _tween_camera(new_rotation: Vector3) -> void:
	if camera_tween:
		camera_tween.kill()
	camera_tween = create_tween()
	
	@warning_ignore_start("return_value_discarded")
	camera_tween.set_parallel(true)
	camera_tween.tween_property(camera_pivot, "rotation_degrees", new_rotation, 0.1)
	camera_tween.tween_property(rotation_gizmo, "rotation_degrees", new_rotation, 0.1)
	@warning_ignore_restore("return_value_discarded")


func _on_viewport_orientation_gizmo_gizmo_clicked(idx: int) -> void:
	match idx:
		0:
			_tween_camera(Vector3(0.0, 90.0, 0.0))
		1:
			_tween_camera(Vector3(-90.0, 0.0, 0.0))
		2:
			_tween_camera(Vector3(0.0, 0.0, 0.0))
