class_name ParamSeedSingle
extends HBoxContainer
## Single Seed class for a compute shader parameter
## 
## Handles displaying and generating seed values for individual seeds.
## Can also be instanced as a child of ParamSeedMultiple for shader parameters
## with multiple seeds.

@export var seed_value : LineEdit

var compute_shader : ComputeShader
var dependant_stage : int
var rng : RandomNumberGenerator = RandomNumberGenerator.new()
var seed_index : int  # idx of the seed in the shader storage array
var buffer_index : int # idx of the shader buffer, used when updating shader


func _on_randomise_button_pressed() -> void:
	var random_float : float = snappedf(rng.randf(), 0.000000001)
	seed_value.set_text(str(random_float))
	compute_shader.seeds_array[seed_index] = random_float
	
	compute_shader.update_storage_buffer(buffer_index, PackedFloat32Array(compute_shader.seeds_array).to_byte_array())
	compute_shader.stage = dependant_stage
