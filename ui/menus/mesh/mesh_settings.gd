class_name MeshSettings
extends PanelContainer

enum Face { BACK, SIDES }

@export var mesh_options : OptionButton
@export var tile_meshes : Array[Mesh]
@export var back_face_checkbox : CheckBox
@export var bottom_face_checkbox : CheckBox
@export var back_uvs_checkbox : CheckBox
@export var sides_uvs_checkbox : CheckBox

@onready var mesh_instance : MeshInstance3D = $/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D
@onready var array_mesh : ArrayMesh = mesh_instance.mesh as ArrayMesh
@onready var surface_array : Array = array_mesh.surface_get_arrays(0)
@onready var normals : PackedVector3Array = surface_array[Mesh.ARRAY_NORMAL]
@onready var uvs : PackedVector2Array = surface_array[Mesh.ARRAY_TEX_UV]

var mesh_index : int = 0:
	set(i):
		mesh_index = i
var cull_back_face : bool = false
var cull_bottom_face : bool = false
var shrink_back_uvs : bool = false
var shrink_sides_uvs : bool = false


func _ready() -> void:
	_load_mesh_settings()
	_setup_settings_ui()


func _load_mesh_settings() -> void:
	if not DataManager.settings_data.size() >= 3 or not DataManager.settings_data[2].name == "mesh_settings":
		return
	
	var mesh_data : Dictionary = DataManager.settings_data[2]
	mesh_index = mesh_data.mesh_type
	cull_back_face = mesh_data.remove_back_face
	cull_bottom_face = mesh_data.remove_bottom_face
	shrink_back_uvs = mesh_data.shrink_back_UVs
	shrink_sides_uvs = mesh_data.shrink_sides_UVs
	

func _setup_settings_ui() -> void:
	mesh_options.select(mesh_index)
	
	var mesh_popup : PopupMenu = mesh_options.get_popup()
	for i : int in 3:
		mesh_popup.set_item_as_radio_checkable(i, false)
	
	back_face_checkbox.set_pressed_no_signal(cull_back_face)
	bottom_face_checkbox.set_pressed_no_signal(cull_bottom_face)
	back_uvs_checkbox.set_pressed_no_signal(shrink_back_uvs)
	sides_uvs_checkbox.set_pressed_no_signal(shrink_sides_uvs)


func _on_back_face_check_box_toggled(toggled_on: bool) -> void:
	cull_back_face = toggled_on
	_rebuild_mesh()


func _on_bottom_face_check_box_toggled(toggled_on: bool) -> void:
	cull_bottom_face = toggled_on
	_rebuild_mesh()
	

func _on_back_uvs_check_box_toggled(toggled_on: bool) -> void:
	shrink_back_uvs = toggled_on
	if toggled_on:
		_modify_uvs(Face.BACK)
	else:
		_rebuild_mesh()
	

func _on_sides_uvs_check_box_toggled(toggled_on: bool) -> void:
	shrink_sides_uvs = toggled_on
	if toggled_on:
		_modify_uvs(Face.SIDES)
	else:
		_rebuild_mesh()


# Deleting and adding sides is much more complex than shrinking UVs
# As such, this loads and sets a new mesh with the correct faces then adjusts UVs.
func _rebuild_mesh() -> void:
	# Multiply then add the bool (1 or 0) gives unique index between 0 and 3
	var index : int = int(cull_back_face) * 2 + int(cull_bottom_face)
	# Deep duplication of mesh to prevent destructively modifying base meshes
	var rebuilt_mesh : Mesh = tile_meshes[index].duplicate(true)
	
	array_mesh = rebuilt_mesh as ArrayMesh
	surface_array = array_mesh.surface_get_arrays(0)
	normals = surface_array[Mesh.ARRAY_NORMAL]
	uvs = surface_array[Mesh.ARRAY_TEX_UV]
	
	_update_uvs()
	mesh_instance.mesh = rebuilt_mesh


func _update_uvs() -> void:
	if shrink_back_uvs:
		_modify_uvs(Face.BACK)
	if shrink_sides_uvs:
		_modify_uvs(Face.SIDES)


func _modify_uvs(direction : Face) -> void:
	match direction:
		Face.BACK:
			for i : int in normals.size():
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


func _on_save_settings_btn_pressed() -> void:
	DataManager.save_mesh_settings(mesh_index, cull_back_face, cull_bottom_face, shrink_back_uvs, shrink_sides_uvs)


func _on_close_btn_pressed() -> void:
	hide()
