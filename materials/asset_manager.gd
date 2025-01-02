extends PanelContainer

@export var params_manager : ParamsManager

var compute_shader : ComputeShader
var renderer : Renderer


# Called when ser double-clicks on an asset in the selection window.
func _on_asset_selector_item_activated(index: int) -> void:
	if not renderer: ## TODO: try to get this in _ready()
		renderer = $/root/ProcTile/Renderer as Renderer
	
	compute_shader = renderer.create_compute_shader()
	renderer.set_shader_material()
	params_manager._build_params_ui(index, compute_shader)
