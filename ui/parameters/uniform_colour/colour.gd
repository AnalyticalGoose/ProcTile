class_name ParamColour
extends VBoxContainer
## Uniform Colour parameter class
##
## Handles signals from the ParamColourPicker class and updates the shader

@export var label : Label
@export var colour_preview : ColorRect
@export var colour_picker_scene : PackedScene

var compute_shader : ComputeShader
var colour_picker : ParamColourPicker

var dependant_stage : int
var buffer_index : int
var buffer_set : int
var undo_redo_colour : Color


@warning_ignore("unsafe_call_argument")
func setup_properties(data : Array) -> void:
	label.text = data[1]
	var colour_data : Array = data[2]
	var colour : Color = Color(colour_data[0], colour_data[1], colour_data[2])
	undo_redo_colour = colour
	colour_preview.color = colour
	dependant_stage = data[3]
	buffer_index = data[4]
	buffer_set = data[5]


func change_colour(colour : Color) -> void:
	colour_preview.color = colour
	compute_shader.update_storage_buffer(buffer_index, PackedColorArray([colour]).to_byte_array())
	compute_shader.stage = dependant_stage


func _on_colour_picked(colour : Color) -> void:
	change_colour(colour)


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
		
		ActionsManager.new_undo_action = [5, self, false, !colour_picker.visible]


func _on_gui_input(_event: InputEvent) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	else:
		if undo_redo_colour != colour_preview.color:
			ActionsManager.new_undo_action = [5, self, true, undo_redo_colour]
			undo_redo_colour = colour_preview.color


func _create_colour_picker() -> void:
	colour_picker = colour_picker_scene.instantiate() as ParamColourPicker
	colour_picker.set_colour(colour_preview.color)
	@warning_ignore("return_value_discarded")
	colour_picker.col_picked.connect(_on_colour_picked)
	colour_preview.add_sibling(colour_picker) # add node between preview & spacer
	_unblock_hue_slider_filter()


# By default, the native ColorPicker node's inbuilt hue slider has its mouse filter set to block
func _unblock_hue_slider_filter() -> void:
	var node : Control = colour_picker
	for i : int in range(4):
		node = node.get_child(0, true)
	(node.get_child(2, true) as Control).mouse_filter = MOUSE_FILTER_PASS
