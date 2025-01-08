extends PanelContainer

@export var params_manager : ParamsManager
@export var menu_manager : HBoxContainer

var compute_shader : ComputeShader
var renderer : Renderer


# Called when ser double-clicks on an asset in the selection window.
@warning_ignore("unsafe_call_argument")
func _on_asset_selector_item_activated(index: int) -> void:
	if not renderer: ## TODO: try to get this in _ready()
		renderer = $/root/ProcTile/Renderer as Renderer
		
	var asset_data : Dictionary = DataManager.material_data[index]
	
	compute_shader = renderer.create_compute_shader()
	renderer.set_shader_material(asset_data.shader_data)
	params_manager._build_params_ui(asset_data.ui_elements, compute_shader)

	@warning_ignore("unsafe_method_access")
	menu_manager.enable_export()
