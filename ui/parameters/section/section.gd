extends VBoxContainer
class_name ParamSection

@export var section_label : Label
@export var show_hide_btn : TextureButton

var children : Array[Control] = []
var children_visible : bool = true


func setup_properties(data : Array) -> void:
	section_label.text = data[1]


func set_section_visibility(visibility : bool) -> void:
	for i : int in len(children):
		children[i].set_visible(visibility)
		children_visible = visibility


func _on_show_hide_button_pressed() -> void:
	var visibility : bool = !children_visible
	set_section_visibility(visibility)

	ActionsManager.new_undo_action = [0, self, !visibility]
