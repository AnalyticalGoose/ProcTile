extends VBoxContainer
class_name ParamSection

@export var section_label : Label
@export var show_hide_btn : TextureButton

var children : Array[Control] = []
var children_visible : bool = true


func setup_properties(data : Array) -> void:
	section_label.text = data[1]


func serialise_properties() -> Array[Array]:
	var properties : Array[Array] = []
	var sections : Array[Node] = get_children()
	
	for section : ParamSection in sections:
		var section_data : Array = []
		var section_nodes : Array[Node] = section.get_children()
		
		for i : int in section_nodes.size():
			var node : Node = section_nodes[i]
			if node is ParamSlider:
				section_data.append([i, 0, (node as ParamSlider).slider_val])
			elif node is ParamDropdown:
				section_data.append([i, 1, (node as ParamDropdown).option_index])
			elif node is ParamGradient:
				section_data.append([i, 2, (node as ParamGradient).get_gradient_data()])
			elif node is ParamColour:
				section_data.append([i, 3, (node as ParamColour).colour_preview.color])
			elif node is ParamSeeds:
				section_data.append([i, 4, (node as ParamSeeds).seed_values])
		
		properties.append(section_data)
	
	return properties


func load_serialised_properties(data : Array[Array]) -> void:
	var sections : Array[Node] = get_children()
	for i : int in data.size():
		var section : ParamSection = sections[i] as ParamSection
		for param : Array in data[i]:
			var child_index : int = param[0]
			match param[1]:
				0:
					var slider : ParamSlider = section.get_child(child_index)
					slider.slider.value = param[2]
					slider.slider_val = param[2]
				1:
					var dropdown : ParamDropdown = section.get_child(child_index)
					var selected_index : int = param[2]
					dropdown.option_button.selected = selected_index
					dropdown.set_dropdown_option(selected_index)
				2:
					var gradient : ParamGradient = section.get_child(child_index)
					var gradient_data : Array = param[2]
					gradient.load_properties(gradient_data)
				3: 
					var uniform : ParamColour = section.get_child(child_index)
					var colour: Color = param[2]
					uniform.change_colour(colour)
				4:
					var seeds : ParamSeeds = section.get_child(child_index)
					var seed_values : Array = param[2]
					seeds.set_seeds_values(seed_values)


func set_section_visibility(visibility : bool) -> void:
	for i : int in len(children):
		children[i].set_visible(visibility)
		children_visible = visibility


func _on_show_hide_button_pressed() -> void:
	var visibility : bool = !children_visible
	set_section_visibility(visibility)

	ActionsManager.new_undo_action = [0, self, !visibility]
