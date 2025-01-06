class_name ComputeShader
extends RefCounted

enum tf_size {
	R16F,
	RGBA32F,
}

enum storage_types {
	SEEDS,
	FLOAT32,
	VEC4,
}

var renderer : Renderer
var init_data : Array
var push_constant_stage_index : int
var texture_size : int:
	set(size):
		texture_size = size
		group_size = (texture_size - 1) / 8.0 + 1 as int
var group_size : int

var albedo : Texture2DRD
var occlusion : Texture2DRD
var roughness : Texture2DRD
var metallic : Texture2DRD
var normal : Texture2DRD

# Albedo, occlusion, roughness, metallic and normal textures
var base_textures_rds : Array[RID] = [RID(), RID(), RID(), RID(), RID()]
var base_texture_sets : Array[RID] = [RID(), RID(), RID(), RID(), RID()]


var base_texture_uniform_set : RID
var image_buffer_uniform_set : RID
#var storage_buffer_uniform_set
## where is this set? And how will it be sent / retrieved on init?
## user settings perhaps?
#var texture : Texture2DRD

#var next_texture : int = 0

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var push_constant : PackedFloat32Array



#var texture_rds : Array[RID] = [RID(), RID(), RID()]
#var texture_sets : Array[RID] = [RID(), RID(), RID()]

# other buffers
var buffer_rds : Array[RID]
var buffer_sets : Array[RID]

# uniform storage buffer
var uniform_rds : Array[RID] 
var uniform_sets : Array[RID] 

### temp - grunge params
#var tone_value : float = 0.80
#var tone_width : float = 0.48
#
#var brick_colour_seed : float = 0.064537466
#
#var perlin_seed_1 : float = 0.612547636
#var perlin_seed_2 : float = 0.587890089
#var perlin_seed_3 : float = 0.509320438
#var perlin_seed_4 : float = 0.941759408
#var perlin_seed_5 : float = 0.459213525
#
#var perlin_seed_6 : float = 0.762268782
#var b_noise_seed : float = 0.00
##
#var seeds_array : Array[float] = [
		#brick_colour_seed, perlin_seed_1, perlin_seed_2, perlin_seed_3, 
		#perlin_seed_4, perlin_seed_5, perlin_seed_6, b_noise_seed,
#]

var seeds_array : Array

#
#var seeds : PackedByteArray = PackedFloat32Array(seeds_array).to_byte_array()
#
		#
#var mortar_col : PackedByteArray = PackedVector4Array([Vector4(1.00, 0.93, 0.81, 1.00)]).to_byte_array()
	#
#var gradient_offset_array : Array[float] = [0.00, 0.15, 0.34, 0.48, 0.61, 0.82, 1.00]
#var gradient_offsets : PackedByteArray = PackedFloat32Array(gradient_offset_array).to_byte_array()
#
#var gradient_colour_array : Array[Vector4] = [
		#Vector4(0.78, 0.36, 0.18, 1.0),
		#Vector4(0.76, 0.34, 0.17, 1.0),
		#Vector4(0.82, 0.40, 0.24, 1.0),
		#Vector4(0.76, 0.36, 0.21, 1.0),
		#Vector4(0.80, 0.40, 0.24, 1.0),
		#Vector4(0.82, 0.41, 0.19, 1.0),
		#Vector4(0.89, 0.49, 0.24, 1.0),
	#]
#var gradient_colours : PackedByteArray = PackedVector4Array(gradient_colour_array).to_byte_array()
#
#
#var mingle_smooth : float = 0.5
#var mingle_warp_strength : float = 2.0
#var b_noise_contrast : float = 0.50
#var pattern : float = 0.0
#var repeat : float = 1.0
#var rows : float = 10.0
#var columns : float = 5.0
#var row_offset : float = 0.5
#var mortar : float = 3.0
#var bevel : float = 5.0
#var rounding : float = 0.0
#var damage_scale_x : float = 10.00
#var damage_scale_y : float = 15.00
#var damage_iterations : float = 3.0
#var damage_persistence : float = 0.50;
var stage : float = 0.0
var max_stage : float = 4.0


@warning_ignore("return_value_discarded")
func _render_process() -> void:
	push_constant.set(push_constant_stage_index, stage)
	if stage != max_stage:
			stage += 1
		
	var packed_byte_array : PackedByteArray = push_constant.to_byte_array()

	#next_texture = (next_texture + 1) % 3
	#if texture:
		#texture.texture_rd_rid = texture_rds[next_texture]
	
	#var x_groups : int = (texture_size - 1) / 8.0 + 1 as int
	#var y_groups : int = (texture_size - 1) / 8.0 + 1 as int
	
	#var next_set : RID = texture_sets[next_texture]
	#var current_set : RID = texture_sets[(next_texture - 1) % 3]
	#var previous_set : RID = texture_sets[(next_texture - 2) % 3]
	
	#var compute_list : int = rd.compute_list_begin()
	#rd.compute_list_bind_compute_pipeline(compute_list, pipepline)
	#
	#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[0], 0)
	#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[1], 0)
	#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[2], 0)
	#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[3], 0)
	#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[4], 0)
	#
	#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[0], 1)
	#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[1], 1)
	#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[2], 1)
	#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[3], 1)
	#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[4], 1)
	#
	#rd.compute_list_bind_uniform_set(compute_list, uniform_sets[0], 2)
	#rd.compute_list_bind_uniform_set(compute_list, uniform_sets[1], 2)
	#rd.compute_list_bind_uniform_set(compute_list, uniform_sets[2], 2)
	#rd.compute_list_bind_uniform_set(compute_list, uniform_sets[3], 2)
	#
	#rd.compute_list_set_push_constant(compute_list, packed_byte_array, packed_byte_array.size())
	#
	#rd.compute_list_dispatch(compute_list, group_size, group_size, 1)
	#rd.compute_list_end()
	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, base_texture_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, image_buffer_uniform_set, 1)
	#rd.compute_list_bind_uniform_set(compute_list, storage_buffer_uniform_set, 2)

	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[0], 2)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[1], 3)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[2], 4)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[3], 5)
	## Bind the base texture sets
	#for i in range(base_texture_sets.size()):
		#rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[i], 0)
#
	## Bind the buffer sets
	#for i in range(buffer_sets.size()):
		#rd.compute_list_bind_uniform_set(compute_list, buffer_sets[i], 1)
#
	## Bind the additional uniform sets
	#for i in range(uniform_sets.size()):
		#rd.compute_list_bind_uniform_set(compute_list, uniform_sets[i], 2)

	# Set push constants
	rd.compute_list_set_push_constant(compute_list, packed_byte_array, packed_byte_array.size())

	# Dispatch the compute shader
	rd.compute_list_dispatch(compute_list, group_size, group_size, 1)
	rd.compute_list_end()

	#rd.submit()
	#rd.sync()
	

@warning_ignore("return_value_discarded")
func _init_compute(size : int, shader_path : String) -> void:
	rd = RenderingServer.get_rendering_device()
	texture_size = size
	
	# Create shader, pipeline & push_constant
	var shader_file : RDShaderFile = load(shader_path) as RDShaderFile
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	push_constant = _create_push_constant()
	
	# Create texture formats
	var r16f_tf : RDTextureFormat = TextureFormat.get_r16f(texture_size)
	var rgba32f_tf : RDTextureFormat = TextureFormat.get_rgba32f(texture_size)

	base_textures_rds[0] = rd.texture_create(rgba32f_tf, RDTextureView.new(), [])
	base_textures_rds[1] = rd.texture_create(rgba32f_tf, RDTextureView.new(), [])
	base_textures_rds[2] = rd.texture_create(rgba32f_tf, RDTextureView.new(), [])
	base_textures_rds[3] = rd.texture_create(r16f_tf, RDTextureView.new(), [])
	base_textures_rds[4] = rd.texture_create(rgba32f_tf, RDTextureView.new(), [])

	var base_texture_uniforms : Array[RDUniform] = []
	for i : int in range(5):
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = i
		uniform.add_id(base_textures_rds[i])
		base_texture_uniforms.append(uniform)
	base_texture_uniform_set = rd.uniform_set_create(base_texture_uniforms, shader, 0)


	#_create_image_uniform_set(base_textures_rds, base_texture_sets, 0)
	#for i : int in range(5):
		#base_texture_sets[i] = _create_uniform_set(base_textures_rds[i])
	
	var image_buffer_textures : Array = init_data[1]
	var num_image_buffers : int = image_buffer_textures.size() 
	
	buffer_rds.resize(num_image_buffers)
	buffer_sets.resize(num_image_buffers)
	buffer_rds.fill(RID())
	buffer_sets.fill(RID())
	
	for i : int in num_image_buffers:
		var buffer_tf : RDTextureFormat
		match image_buffer_textures[i]:
			tf_size.R16F:
				buffer_tf = r16f_tf
			tf_size.RGBA32F:
				buffer_tf = rgba32f_tf
		buffer_rds[i] = rd.texture_create(buffer_tf, RDTextureView.new(), [])

	var image_buffer_uniforms : Array[RDUniform] = []
	for i : int in num_image_buffers:
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = i
		uniform.add_id(buffer_rds[i])
		image_buffer_uniforms.append(uniform)
	image_buffer_uniform_set = rd.uniform_set_create(image_buffer_uniforms, shader, 1)

	
	#_create_image_uniform_set(buffer_rds, buffer_sets, 1)
	#buffer_sets[i] = _create_uniform_set(buffer_rds[i])
	
	var storage_buffer_types : Array = init_data[2]
	var storage_buffer_data : Array = init_data[3]
	var num_storage_buffers : int = storage_buffer_data.size()
	
	uniform_rds.resize(num_storage_buffers)
	uniform_sets.resize(num_storage_buffers)
	uniform_rds.fill(RID())
	uniform_sets.fill(RID())
	

	for i : int in num_storage_buffers:
		var buffer_data : Array = storage_buffer_data[i]
		var packed_data : PackedByteArray
		match storage_buffer_types[i]:
			storage_types.SEEDS:
				seeds_array = buffer_data
				packed_data = PackedFloat32Array(buffer_data).to_byte_array()
			storage_types.FLOAT32:
				packed_data = PackedFloat32Array(buffer_data).to_byte_array()
			storage_types.VEC4:
				var colour_data : Array = []
				for rgb : Array in buffer_data:
					@warning_ignore("unsafe_call_argument", "return_value_discarded")
					var colour : Color = Color(rgb[0], rgb[1], rgb[2])
					colour_data.append(colour)
				packed_data = PackedColorArray(colour_data).to_byte_array()
		
		uniform_rds[i] = rd.storage_buffer_create(packed_data.size(), packed_data)
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = 0
		uniform.add_id(uniform_rds[i])
		uniform_sets[i] = rd.uniform_set_create([uniform], shader, i + 2)
	
	### test uniform storage buffer - this should really be a uniform buffer, not storage as we know the size.
	#uniform_rds[0] = rd.storage_buffer_create(seeds.size(), seeds)
	#var uniform_block : RDUniform = RDUniform.new()
	#uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	#uniform_block.binding = 0
	#uniform_block.add_id(uniform_rds[0])
	#uniform_sets[0] = rd.uniform_set_create([uniform_block], shader, 2)
	#
	#uniform_rds[1] = rd.storage_buffer_create(gradient_offsets.size(), gradient_offsets)
	#var uniform_block_ : RDUniform = RDUniform.new()
	#uniform_block_.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	#uniform_block_.binding = 0
	#uniform_block_.add_id(uniform_rds[1])
	#uniform_sets[1] = rd.uniform_set_create([uniform_block_], shader, 3)
	#
	#uniform_rds[2] = rd.storage_buffer_create(gradient_colours.size(), gradient_colours)
	#var _uniform_block : RDUniform = RDUniform.new()
	#_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	#_uniform_block.binding = 0
	#_uniform_block.add_id(uniform_rds[2])
	#uniform_sets[2] = rd.uniform_set_create([_uniform_block], shader, 4)
	#
	## mortar colour
	#uniform_rds[3] = rd.storage_buffer_create(mortar_col.size(), mortar_col)
	#var __uniform_block : RDUniform = RDUniform.new()
	#__uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	#__uniform_block.binding = 0
	#__uniform_block.add_id(uniform_rds[3])
	#uniform_sets[3] = rd.uniform_set_create([__uniform_block], shader, 5)
	
	
	Logger.puts_success("init compute shader success")


@warning_ignore("return_value_discarded")
func _create_push_constant() -> PackedFloat32Array:
	var push_constant_data : Array = init_data[0]
	var _push_constant : PackedFloat32Array = PackedFloat32Array(push_constant_data)
	_push_constant.push_back(texture_size)
	_push_constant.push_back(stage)
	
	var push_constant_size : int = _push_constant.size()
	push_constant_stage_index = push_constant_size - 1
	
	if (push_constant_size * 4) % 16 != 0:
		var bytes_needed : int = (16 - (push_constant_size * 4 % 16))
		for i : int in (bytes_needed / 4.0):
			_push_constant.push_back(0.0)
			
	return _push_constant



#func _create_uniform_set(texture_rd : RID) -> RID:
	#var uniform : RDUniform = RDUniform.new()
	#uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	#uniform.binding = 0
	#uniform.add_id(texture_rd)
	#
	#return rd.uniform_set_create([uniform], shader, 0)
#
#
#func _create_image_uniform_set(rds : Array, sets : Array, set_index : int) -> void:
	#var uniforms : Array = []
	#for i : int in rds.size():
		#var uniform : RDUniform = RDUniform.new()
		#uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		#uniform.binding = i
		#@warning_ignore("unsafe_call_argument")
		#uniform.add_id(rds[i])
		#uniforms.append(uniform)
	#sets[set_index] = rd.uniform_set_create(uniforms, shader, set_index)

#
#func _create_storage_uniform_set() -> void:
	#pass


#func _create_image_buffer(i : int) -> void:
	#var tf : RDTextureFormat = TextureFormat.get_r16f(texture_size)
	#
	#buffer_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])
	#var err : Error = rd.texture_clear(buffer_rds[i], Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	#if err:
		#Logger.puts_error("Failed to clear RDTexture", err)
	#buffer_sets[i] = _create_uniform_set(buffer_rds[i])


func _set_texture_rids() -> void:
	albedo.texture_rd_rid = base_textures_rds[0]
	occlusion.texture_rd_rid = base_textures_rds[1]
	roughness.texture_rd_rid = base_textures_rds[2]
	metallic.texture_rd_rid = base_textures_rds[3]
	normal.texture_rd_rid = base_textures_rds[4]



# Update storage buffer where data has been updated, but the buffer size has not been changed.
func update_storage_buffer(index : int, data : Array) -> void:
	var error : Error = rd.buffer_update(uniform_rds[index], 0, data.size(), data)
	if error:
		Logger.puts_error("Failed to update storage buffer", error)


# Rebuild storage buffer when data has been updated such that the size of the buffer has changed and will overflow.
func rebuild_storage_buffer(index : int, u_set : int, data : Array) -> void:
	uniform_rds[index] = rd.storage_buffer_create(data.size(), data)
	var uniform_block : RDUniform = RDUniform.new()
	uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_block.binding = 0
	uniform_block.add_id(uniform_rds[index])
	uniform_sets[index] = rd.uniform_set_create([uniform_block], shader, u_set)
