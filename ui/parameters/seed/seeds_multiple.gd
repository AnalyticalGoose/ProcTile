class_name ParamSeedMultiple
extends VBoxContainer

@export var seed_single_scene : PackedScene
@export var label : Label
@export var hide_btn : TextureButton
@export var buttons_container : HBoxContainer
@export var spacer : MarginContainer

var compute_shader : ComputeShader
var dependant_stage : int
var seed_values : Array
var seed_indexes : Array # idx of the seed in the storage array for all seeds.
var buffer_index : int # idx of the buffer, used when updating shader

var single_seeds_created : bool

var rng : RandomNumberGenerator = RandomNumberGenerator.new()

var _seed_nodes : Array[ParamSeedSingle]


func setup_properties(data : Array) -> void:
	label.text = data[1]
	seed_values = data[2]
	seed_indexes = data[3]
	dependant_stage = data[4]
	buffer_index = data[5]


func _on_randomise_all_btn_pressed() -> void:
	for i : int in seed_values.size():
		var random_float : float = snappedf(rng.randf(), 0.000000001)
		seed_values[i] = random_float
		compute_shader.seeds_array[seed_indexes[i]] = random_float
		
		if single_seeds_created:
			_seed_nodes[i].seed_value.set_text(str(random_float))

	compute_shader.update_storage_buffer(buffer_index, PackedFloat32Array(compute_shader.seeds_array).to_byte_array())
	compute_shader.stage = dependant_stage


func _on_show_all_btn_pressed() -> void:
	hide_btn.show()
	buttons_container.hide()
	
	if single_seeds_created:
		for i : int in _seed_nodes.size():
			_seed_nodes[i].show()
	else:
		for i : int in seed_values.size():
			var single_seed : ParamSeedSingle = seed_single_scene.instantiate() as ParamSeedSingle
			single_seed.seed_value.set_text(str(seed_values[i]))
			# ParamSeedSingle needs extra data as it's designed to work independantly 
			# of the ParamSeedMultiple class and sends data to the shader directly.
			single_seed.compute_shader = compute_shader
			single_seed.dependant_stage = dependant_stage
			single_seed.seed_index = seed_indexes[i]
			single_seed.buffer_index = buffer_index
			_seed_nodes.append(single_seed)
			add_child(single_seed)
			move_child(spacer, -1) # move spacer to the bottom
		
		single_seeds_created = true


func _on_hide_button_pressed() -> void:
	hide_btn.hide()
	buttons_container.show()

	for i : int in _seed_nodes.size():
		_seed_nodes[i].hide()
