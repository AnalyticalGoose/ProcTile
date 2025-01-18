class_name MeshSettings
extends PanelContainer


@export var mesh_options : OptionButton
@export var texel_options : OptionButton

@export var tile_meshes : Array[Mesh]

@onready var mesh_instance : MeshInstance3D = $/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D


var cull_back_face : bool = false:
	set(cull):
		cull_back_face = cull
		_change_mesh()
		
var cull_bottom_face : bool = false:
	set(cull):
		cull_bottom_face = cull
		_change_mesh()


func _change_mesh() -> void:
	if cull_back_face:
		if cull_bottom_face:
			mesh_instance.mesh = tile_meshes[0]
		else:
			mesh_instance.mesh = tile_meshes[1]
	else:
		if cull_bottom_face:
			mesh_instance.mesh = tile_meshes[2]
		else:
			mesh_instance.mesh = tile_meshes[3]


func _ready() -> void:
	for option : OptionButton in [mesh_options, texel_options]:
		var popup : PopupMenu = option.get_popup()
		for i : int in 3:
			popup.set_item_as_radio_checkable(i, false)


func _on_back_face_check_box_toggled(toggled_on: bool) -> void:
	cull_back_face = toggled_on


func _on_bottom_face_check_box_toggled(toggled_on: bool) -> void:
	cull_bottom_face = toggled_on
