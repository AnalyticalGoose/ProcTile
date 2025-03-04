class_name ParamSlider
extends VBoxContainer
## Slider class for a compute shader parameter
##
## Initialises value parameters from the database, and handles updates to the shader.

@export var slider_label : Label
@export var slider : HSlider
@export var slider_value : LineEdit

var compute_shader : ComputeShader
var push_constant_index : int
var dependant_stage : int
var slider_val : float


@warning_ignore_start("unsafe_call_argument")
func setup_properties(data : Array) -> void:
	slider_label.set_text(str(data[1]))
	slider.set_min(data[2])
	slider.set_max(data[3])
	slider.set_step(data[4])
	slider.set_value_no_signal(data[5])
	slider_val = data[5]
	slider.set_use_rounded_values(data[6])
	slider_value.set_text(str(data[5]))
	dependant_stage = data[7]
	push_constant_index = data[8]
@warning_ignore_restore("unsafe_call_argument")


func _on_slider_value_changed(value: float) -> void:
	slider_value.set_text(str(value))
	compute_shader.push_constant.set(push_constant_index, value)
	compute_shader.stage = dependant_stage


func _on_slider_value_text_submitted(new_text: String) -> void:
	var val : float = float(new_text)
	if val != slider_val:
		slider.set_value(float(new_text))
		ActionsManager.new_undo_action = [1, self, slider_val]
		slider_val = slider.value


func _on_slider_drag_ended(value_changed: bool) -> void:
	if value_changed:
		ActionsManager.new_undo_action = [1, self, slider_val]
		slider_val = slider.value
