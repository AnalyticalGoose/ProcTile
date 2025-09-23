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
@export var presets_scene : PackedScene
@export var slider_scene : PackedScene
@export var dropdown_scene : PackedScene
@export var gradient_scene : PackedScene
@export var colour_scene : PackedScene
@export var seed_scene : PackedScene

var current_container : ParamSection
var compute_shader : ComputeShader


func _ready() -> void:
	MaterialDataLoader.params_container = params_container


func free_params_ui() -> void:
	for child : ParamSection in params_container.get_children():
		child.queue_free()


func build_params_ui(ui_data: Array, presets_data: Array, shader: ComputeShader) -> void:
	compute_shader = shader
	current_container = params_container # if a section is not added first, prevents issues.
	
	if not presets_data.is_empty():
		var section : ParamSection = section_scene.instantiate() as ParamSection
		section.section_label.text = "Material Presets"
		current_container = section
		params_container.add_child(current_container)
		var presets : ParamPresets = presets_scene.instantiate() as ParamPresets
		presets.setup_properties(presets_data)
		presets.compute_shader = compute_shader
		presets.params_container = params_container
		current_container.add_child(presets)
		current_container.children.append(presets)
	
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
				var dropdown : ParamDropdown = dropdown_scene.instantiate() as ParamDropdown
				dropdown.compute_shader = compute_shader
				dropdown.setup_properties(element_data)
				current_container.add_child(dropdown)
				current_container.children.append(dropdown)
				
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
				var seeds : ParamSeeds = seed_scene.instantiate() as ParamSeeds
				seeds.compute_shader = compute_shader
				seeds.setup_properties(element_data)
				current_container.add_child(seeds)
				current_container.children.append(seeds)
