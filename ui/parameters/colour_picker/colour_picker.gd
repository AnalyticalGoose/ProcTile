class_name ParamColourPicker
extends MarginContainer
## ColourPicker class for colour gradient and uniform colour parameters
##
## Signals up when the colour is changed by the user.

signal col_picked(col : Color)

@export var picker : ColorPicker


func set_colour(col : Color) -> void:
	picker.color = col


func _on_colour_changed(col: Color) -> void:
	col_picked.emit(col)
