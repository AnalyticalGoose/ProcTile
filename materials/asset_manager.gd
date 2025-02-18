class_name AssetsManager
extends PanelContainer

@export var ui_manager : UIManager
@export var params_manager : ParamsManager
@export var menu_manager : HBoxContainer
@export var assets_filter : ItemList
@export var asset_selectors : Array[ItemList]

var compute_shader : ComputeShader
var current_asset_selector_idx : int = 0
var current_asset_type : int = 0
var asset_selector_offets : Array[int]

@onready var renderer : Renderer = $/root/ProcTile/Renderer as Renderer


func _ready() -> void:
		assets_filter.set_item_tooltip(0, "3D PBR")
		assets_filter.set_item_tooltip(1, "2D Pixel")
		asset_selector_offets = DataManager.material_offets


func load_material(index : int, load_from_save : bool = false) -> void:
	var material_index : int
	if load_from_save:
		material_index = index
	else:
		material_index = index + asset_selector_offets[current_asset_selector_idx]
	
	if current_asset_type != current_asset_selector_idx: # Different material shader needed
		print("change shader")
		current_asset_type = current_asset_selector_idx
		renderer.change_mesh_shader(current_asset_type)
	
	if compute_shader:
		renderer.free_compute_resources()
		params_manager.free_params_ui()
		compute_shader.stage = 0
	else:
		compute_shader = renderer.create_compute_shader()
		ui_manager.enable_full_ui()
		
	var asset_data : Dictionary = DataManager.material_data[material_index].duplicate(true)
	var shader_path : String = DataManager.shader_paths[material_index][0]
	var shader_data : Array = asset_data.shader_data
	var ui_data : Array = asset_data.ui_elements
	
	DataManager.current_material_name = asset_data.name
	DataManager.current_material_id = asset_data.id
	
	renderer.set_shader_material(shader_data, shader_path)
	params_manager.build_params_ui(ui_data, compute_shader)


func change_asset_filter(index: int) -> void:
	if current_asset_selector_idx == index:
		return
	else:
		asset_selectors[index].show()
		asset_selectors[current_asset_selector_idx].hide()
		current_asset_selector_idx = index


# Called when user double-clicks on an asset in the selection window.
func _on_asset_selector_item_activated(index: int) -> void:
	load_material(index)


func _on_assets_filter_item_selected(index: int) -> void:
	change_asset_filter(index)
