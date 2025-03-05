class_name MeshSettings
extends PanelContainer
## Mesh settings class for the mesh displayed in the Renderer
##
## Initialises user settings from the database, or falls back to a default if not set.
## Handles changing mesh type, culling faces and scaling UVs by updating mesh data
## or by sending a new mesh to the Renderer.

enum Face { BACK, SIDES }
enum Meshes { TILE, CUBE, PLANE }
enum CameraPosition { NEAR, FAR }

@export_group("Meshes")
@export var tile_meshes : Array[Mesh]
@export var cube_meshes : Array[Mesh]
@export var plane_meshes : Array[Mesh]
@export_group("UI Elements")
@export var mesh_options : OptionButton
@export var back_face_checkbox : CheckBox
@export var bottom_face_checkbox : CheckBox
@export var back_uvs_checkbox : CheckBox
@export var sides_uvs_checkbox : CheckBox

var mesh_index : int = 0
var current_meshes : Array[Mesh]
var camera_position : CameraPosition = CameraPosition.NEAR
var cull_back_face : bool = false
var cull_bottom_face : bool = false
var shrink_back_uvs : bool = false
var shrink_sides_uvs : bool = false
var checkboxes_disabled : bool = false

@onready var mesh_instance : MeshInstance3D = $/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D
@onready var camera : Camera3D = $/root/ProcTile/Renderer/CameraPivot/Camera3D
@onready var array_mesh : ArrayMesh = mesh_instance.mesh as ArrayMesh
@onready var surface_array : Array = array_mesh.surface_get_arrays(0)
@onready var normals : PackedVector3Array = surface_array[Mesh.ARRAY_NORMAL]
@onready var uvs : PackedVector2Array = surface_array[Mesh.ARRAY_TEX_UV]


func _ready() -> void:
	_load_mesh_settings()
	_set_current_meshes()
	_setup_settings_ui()
	rebuild_mesh()


func scale_uvs(face : Face, toggled_on : bool) -> void:
	if face == Face.BACK:
		shrink_back_uvs = toggled_on
	else:
		shrink_sides_uvs = toggled_on
	
	if toggled_on:
		_modify_uvs(face)
	else:
		rebuild_mesh()


func update_checkbox(checkbox : CheckBox, toggled : bool) -> void:
	checkbox.set_pressed_no_signal(toggled)


# Deleting and adding sides is much more complex than shrinking UVs
# As such, this loads and sets a new mesh with the correct faces then adjusts UVs.
func rebuild_mesh() -> void:
	var index : int
	if mesh_index == Meshes.PLANE: # only 1 mesh used
		index = 0
	else:
		# Multiply then add the bool (1 or 0) gives unique index between 0 and 3
		index = int(cull_back_face) * 2 + int(cull_bottom_face)
	
	# Deep duplication of mesh to prevent destructively modifying base meshes
	var rebuilt_mesh : Mesh = current_meshes[index].duplicate(true)
	
	array_mesh = rebuilt_mesh as ArrayMesh
	surface_array = array_mesh.surface_get_arrays(0)
	normals = surface_array[Mesh.ARRAY_NORMAL]
	uvs = surface_array[Mesh.ARRAY_TEX_UV]
	
	_update_uvs()
	mesh_instance.mesh = rebuilt_mesh


func _load_mesh_settings() -> void:
	# if user hasn't saved their preferred settings previously, return and use default.
	if not DataManager.settings_data.size() >= 3 or not DataManager.settings_data[2].name == "mesh_settings":
		return
	
	# else, load settings from database
	var mesh_data : Dictionary = DataManager.settings_data[2]
	mesh_index = mesh_data.mesh_type
	cull_back_face = mesh_data.remove_back_face
	cull_bottom_face = mesh_data.remove_bottom_face
	shrink_back_uvs = mesh_data.shrink_back_UVs
	shrink_sides_uvs = mesh_data.shrink_sides_UVs


func _setup_settings_ui() -> void:
	var mesh_popup : PopupMenu = mesh_options.get_popup()
	for i : int in 3:
		mesh_popup.set_item_as_radio_checkable(i, false)
	
	mesh_options.select(mesh_index)
	back_face_checkbox.set_pressed_no_signal(cull_back_face)
	bottom_face_checkbox.set_pressed_no_signal(cull_bottom_face)
	back_uvs_checkbox.set_pressed_no_signal(shrink_back_uvs)
	sides_uvs_checkbox.set_pressed_no_signal(shrink_sides_uvs)


func _disable_checkboxes() -> void:
	back_face_checkbox.disabled = true
	bottom_face_checkbox.disabled = true
	back_uvs_checkbox.disabled = true
	sides_uvs_checkbox.disabled = true
	
	back_face_checkbox.set_pressed_no_signal(false)
	bottom_face_checkbox.set_pressed_no_signal(false)
	back_uvs_checkbox.set_pressed_no_signal(false)
	sides_uvs_checkbox.set_pressed_no_signal(false)
	
	checkboxes_disabled = true


func _enable_checkboxes() -> void:
	back_face_checkbox.disabled = false
	bottom_face_checkbox.disabled = false
	back_uvs_checkbox.disabled = false
	sides_uvs_checkbox.disabled = false
	
	back_face_checkbox.set_pressed_no_signal(cull_back_face)
	bottom_face_checkbox.set_pressed_no_signal(cull_bottom_face)
	back_uvs_checkbox.set_pressed_no_signal(shrink_back_uvs)
	sides_uvs_checkbox.set_pressed_no_signal(shrink_sides_uvs)
	
	checkboxes_disabled = false


func _set_current_meshes() -> void:
	match mesh_index:
		Meshes.TILE:
			current_meshes = tile_meshes
			_set_camera_position(CameraPosition.NEAR)
		Meshes.CUBE:
			current_meshes = cube_meshes
			_set_camera_position(CameraPosition.FAR)
		Meshes.PLANE:
			current_meshes = plane_meshes
			_set_camera_position(CameraPosition.NEAR)
			_disable_checkboxes()


func _set_camera_position(pos : CameraPosition) -> void:
	if camera_position == pos:
		return
	
	if pos == CameraPosition.NEAR:
		camera.position.z -= 0.9
	else:
		camera.position.z += 0.9
	
	camera_position = pos


func _update_uvs() -> void:
	if shrink_back_uvs:
		_modify_uvs(Face.BACK)
	if shrink_sides_uvs:
		_modify_uvs(Face.SIDES)


func _modify_uvs(direction : Face) -> void:
	match direction:
		Face.BACK:
			for i : int in normals.size():
				print(normals)
				var normal_dir : float = normals[i].dot(Vector3(0, 0, 1))
				if normal_dir == -1.0:
					uvs[i] = Vector2(0, 0)
		Face.SIDES:
			for i : int in normals.size():
				var normal_dir : float = normals[i].dot(Vector3(0, 0, 1))
				if normal_dir != 1.0 and normal_dir != -1.0:
					uvs[i] = Vector2(0, 0)
		
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	mesh_instance.mesh = array_mesh


func _on_mesh_option_button_item_selected(index: int) -> void:
	mesh_index = index
	
	if checkboxes_disabled:
		_enable_checkboxes()
	
	_set_current_meshes()
	rebuild_mesh()


func _on_back_face_check_box_toggled(toggled_on: bool) -> void:
	cull_back_face = toggled_on
	rebuild_mesh()
	ActionsManager.new_undo_action = [8, self, 0, toggled_on]


func _on_bottom_face_check_box_toggled(toggled_on: bool) -> void:
	cull_bottom_face = toggled_on
	rebuild_mesh()
	ActionsManager.new_undo_action = [8, self, 1, toggled_on]


func _on_back_uvs_check_box_toggled(toggled_on: bool) -> void:
	scale_uvs(Face.BACK, toggled_on)
	ActionsManager.new_undo_action = [7, self, Face.BACK, toggled_on]


func _on_sides_uvs_check_box_toggled(toggled_on: bool) -> void:
	scale_uvs(Face.SIDES, toggled_on)
	ActionsManager.new_undo_action = [7, self, Face.SIDES, toggled_on]


func _on_save_settings_btn_pressed() -> void:
	DataManager.save_mesh_settings(mesh_index, cull_back_face, cull_bottom_face, shrink_back_uvs, shrink_sides_uvs)


func _on_close_btn_pressed() -> void:
	hide()
