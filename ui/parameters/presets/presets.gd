class_name ParamPresets
extends VBoxContainer

# TODO: Add thumbnails for presets.

@export var option_button : OptionButton

var params_container : ParamSection
var presets_data : Array[Array] = []

func setup_properties(data : Array) -> void:
	var menu_entries : int = data.size()
	
	for i : int in menu_entries:
		@warning_ignore("unsafe_call_argument")
		option_button.add_item(data[i][0])
		presets_data.append(data[i][1])
		
	var option_menu : PopupMenu = option_button.get_popup()
	for i : int in menu_entries:
		option_menu.set_item_as_radio_checkable(i, false)


func _on_option_button_item_selected(index: int) -> void:
	params_container.load_serialised_properties(presets_data[index])
