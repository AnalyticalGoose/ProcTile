extends VBoxContainer
class_name ParamSection

@export var section_label : Label

var children : Array[Control] = []
var children_visible : bool = true

func setup_properties(data : Array) -> void:
	section_label.text = data[1]


func _on_show_hide_button_pressed() -> void:
	var visibility : bool = !children_visible
	
	for i : int in len(children):
		children[i].set_visible(visibility)
		
	children_visible = visibility
