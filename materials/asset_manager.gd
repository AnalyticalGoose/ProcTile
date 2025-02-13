extends PanelContainer

@export var ui_manager : UIManager
@export var params_manager : ParamsManager
@export var menu_manager : HBoxContainer

var compute_shader : ComputeShader

@onready var renderer : Renderer = $/root/ProcTile/Renderer as Renderer


# Called when user double-clicks on an asset in the selection window.
func _on_asset_selector_item_activated(index: int) -> void:
	if compute_shader:
		renderer.free_compute_resources()
		params_manager.free_params_ui()
		compute_shader.stage = 0
	else:
		compute_shader = renderer.create_compute_shader()
		ui_manager.enable_full_ui()

	var asset_data : Dictionary = DataManager.material_data[index].duplicate(true)
	var shader_path : String = DataManager.shader_paths[index][0]
	var shader_data : Array = asset_data.shader_data
	var ui_data : Array = asset_data.ui_elements
	
	renderer.set_shader_material(shader_data, shader_path)
	params_manager.build_params_ui(ui_data, compute_shader)
	renderer.asset_name = asset_data.name
	
	print_orphan_nodes()
