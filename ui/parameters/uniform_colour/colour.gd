class_name ParamColour
extends VBoxContainer

@export var label : Label
@export var colour_preview : ColorRect
@export var colour_picker_scene : PackedScene

var compute_shader : ComputeShader
var colour_picker : ParamColourPicker
var preview_colour : Color:
	set(col):
		preview_colour = col
		colour_preview.color = col
		if colour_picker:
			colour_picker.set_colour(col)
var dependant_stage : int
var buffer_index : int
var buffer_set : int


@warning_ignore("unsafe_call_argument")
func setup_properties(data : Array) -> void:
	label.text = data[1]
	var colour_data : Array = data[2]
	preview_colour = Color(colour_data[0], colour_data[1], colour_data[2])
	dependant_stage = data[3]
	buffer_index = data[4]
	buffer_set = data[5]


func _on_colour_preview_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton: # Early return for non-click
		return
	elif (event as InputEventMouseButton).button_index == 1 and event.is_pressed():
		if colour_picker:
			if colour_picker.visible:
				colour_picker.hide()
			else:
				colour_picker.show()
		else:
			_create_colour_picker()


func _on_colour_picked(col : Color) -> void:
	colour_preview.color = col
	#Update shader storage buffer
	compute_shader.update_storage_buffer(buffer_index, PackedColorArray([col]).to_byte_array())
	compute_shader.stage = dependant_stage


func _create_colour_picker() -> void:
	colour_picker = colour_picker_scene.instantiate() as ParamColourPicker
	colour_picker.set_colour(preview_colour)
	@warning_ignore("return_value_discarded")
	colour_picker.col_picked.connect(_on_colour_picked)
	colour_preview.add_sibling(colour_picker) # add node between preview & spacer
