class_name ParamSeeds
extends VBoxContainer
## Seeds class for a compute shader parameter
## 
## Handles rng, instancing children for individual seeds and refreshing the
## shader with new buffer data

@export var seed_single_scene : PackedScene
@export var label : Label
@export var hide_btn : TextureButton
@export var randomise_btn : Button
@export var show_all_btn : Button
@export var edit_btn : TextureButton
@export var buttons_container : HBoxContainer
@export var spacer : MarginContainer

var compute_shader : ComputeShader
var dependant_stage : int
var seed_values : Array
var seed_indexes : Array # idx of the seed in the storage array for all seeds.
var buffer_index : int # idx of the buffer, used when updating shader

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _seed_nodes : Array[ParamSeedLine]
var _single_seeds_created : bool


func setup_properties(data : Array) -> void:
	label.text = data[1]
	seed_values = data[2]
	seed_indexes = data[3]
	dependant_stage = data[4]
	buffer_index = data[5]
	
	if seed_values.size() > 1:
		randomise_btn.set_text("Randomise All")
		edit_btn.queue_free()
	else:
		show_all_btn.queue_free()


func _on_show_all_btn_pressed() -> void:
	hide_btn.show()
	buttons_container.hide()
	_show_seed_controls()


func _on_show_hide_button_pressed() -> void:
	hide_btn.hide()
	
	if buttons_container.visible:
		buttons_container.hide()
		_show_seed_controls()
	else:
		buttons_container.show()
		for i : int in _seed_nodes.size():
			_seed_nodes[i].hide()


func _create_seed_controls() -> void:
	for i : int in seed_values.size():
		var single_seed : ParamSeedLine = seed_single_scene.instantiate() as ParamSeedLine
		@warning_ignore("return_value_discarded")
		single_seed.randomised.connect(_on_seed_randomised.bind(i, seed_indexes[i]))
		single_seed.seed_value.set_text(str(seed_values[i]))
		_seed_nodes.append(single_seed)
		add_child(single_seed)
		move_child(spacer, -1) # move spacer to the bottom
		

func _show_seed_controls() -> void:
	if _single_seeds_created:
		for i : int in _seed_nodes.size():
			_seed_nodes[i].show()
	else:
		_create_seed_controls()
		_single_seeds_created = true


func _on_randomise_btn_pressed() -> void:
	for i : int in seed_values.size():
		var random_float : float = snappedf(_rng.randf(), 0.000000001)
		seed_values[i] = random_float
		compute_shader.seeds_array[seed_indexes[i]] = random_float
		
		if _single_seeds_created:
			_seed_nodes[i].seed_value.set_text(str(random_float))

	_update_storage_buffer()


func _on_seed_randomised(i : int, seed_array_index : int) -> void:
	var random_float : float = snappedf(_rng.randf(), 0.000000001)
	seed_values[i] = random_float
	compute_shader.seeds_array[seed_array_index] = random_float
	_seed_nodes[i].seed_value.set_text(str(random_float))
	_update_storage_buffer()


func _update_storage_buffer() -> void:
	compute_shader.update_storage_buffer(buffer_index, PackedFloat32Array(compute_shader.seeds_array).to_byte_array())
	compute_shader.stage = dependant_stage
