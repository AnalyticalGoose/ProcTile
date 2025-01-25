class_name ParamDropdown
extends VBoxContainer

@export var label : Label
@export var option_button : OptionButton

var compute_shader : ComputeShader
var push_constant_index : float
var dependant_stage : float
var option_index : int = 0

@warning_ignore("unsafe_call_argument")
func setup_properties(data : Array) -> void:
	label.set_text(str(data[1]))
	dependant_stage = data[3]
	push_constant_index = data[4]
	
	var popup_menu : PopupMenu = option_button.get_popup()
	var dropdown_items : Array = data[2]
	for i : int in dropdown_items.size():
		option_button.add_item(dropdown_items[i])
		popup_menu.set_item_as_radio_checkable(i, false)


func set_dropdown_option(index : int) -> void:
	@warning_ignore("narrowing_conversion")
	compute_shader.push_constant.set(push_constant_index, float(index))
	compute_shader.stage = dependant_stage
	option_index = index


func _on_option_button_item_selected(index : int) -> void:
	ActionsManager.new_undo_action = [2, self, option_index]
	set_dropdown_option(index)
