class_name ParamsManager
extends PanelContainer

enum ui_element {
		SECTION, 
		SLIDER, 
		DROPDOWN, 
		GRADIENT, 
		COLOUR,
		SEED,
}

@export var params_container : ParamSection
@export var section_scene : PackedScene
@export var slider_scene : PackedScene
@export var gradient_scene : PackedScene
@export var colour_scene : PackedScene
@export var seed_single_scene : PackedScene
@export var seed_multiple_scene : PackedScene

var current_container : ParamSection
var compute_shader : ComputeShader

func _build_params_ui(index : int, shader : ComputeShader) -> void:
	var ui_data : Array = DataManager.material_data[index].ui_elements
	compute_shader = shader
	current_container = params_container
	
	for i : int in len(ui_data):
		var element_data : Array = ui_data[i]

		match element_data[0]:
			ui_element.SECTION:
				var section : ParamSection = section_scene.instantiate() as ParamSection
				section.setup_properties(element_data)
				current_container = section
				params_container.add_child(current_container)
			
			ui_element.SLIDER:
				var slider : ParamSlider = slider_scene.instantiate() as ParamSlider
				slider.compute_shader = compute_shader
				slider.setup_properties(element_data)
				current_container.add_child(slider)
				current_container.children.append(slider)
			
			ui_element.DROPDOWN:
				print("dropdown")
				
			ui_element.GRADIENT:
				var gradient : ParamGradient = gradient_scene.instantiate() as ParamGradient
				gradient.compute_shader = compute_shader
				gradient.setup_properties(element_data)
				current_container.add_child(gradient)
				current_container.children.append(gradient)
				
			ui_element.COLOUR:
				var colour : ParamColour = colour_scene.instantiate() as ParamColour
				colour.compute_shader = compute_shader
				colour.setup_properties(element_data)
				current_container.add_child(colour)
				current_container.children.append(colour)
				
			ui_element.SEED:
				var seed_multiple : ParamSeeds = seed_multiple_scene.instantiate() as ParamSeeds
				seed_multiple.compute_shader = compute_shader
				seed_multiple.setup_properties(element_data)
				current_container.add_child(seed_multiple)
				current_container.children.append(seed_multiple)
