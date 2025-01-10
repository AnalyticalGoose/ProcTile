class_name ComputeShader
extends RefCounted
## Compute shader constructor class.
## 
## Handles the loading and compilation of the shader, creation and management of 
## the push constant and required image / data storage buffers, and can be called
## from the renderer to update and dispatch the shader each frame.

enum tf_size {
	R16F,
	RGBA32F,
	RGB32F,
}

enum storage_types {
	SEEDS,
	FLOAT32,
	VEC4,
}

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var push_constant : PackedFloat32Array
var albedo : Texture2DRD
var occlusion : Texture2DRD
var roughness : Texture2DRD
var metallic : Texture2DRD
var normal : Texture2DRD
var seeds_array : Array
var stage : float = 0.0
# Albedo, occlusion, roughness, metallic, normal and packed orm
var base_textures_rds : Array[RID] = [RID(), RID(), RID(), RID(), RID(), RID()] 

var _uniform_rds : Array[RID] 
var _uniform_sets : Array[RID] 
var _buffer_rds : Array[RID]
var _base_texture_uniform_set : RID
var _image_buffer_uniform_set : RID
var _push_constant_stage_index : int # idx of 'stage' var in pc, changes per shader
var _group_size : int # x & y local_size groups of shader
var _max_stage : float

#var _base_texture_sets : Array[RID] = [RID(), RID(), RID(), RID(), RID()]
#var buffer_sets : Array[RID]


@warning_ignore("return_value_discarded")
func init_compute(init_data : Array, texture_size : int, shader_path : String) -> void:
	rd = RenderingServer.get_rendering_device()
	_max_stage = init_data[0][0]
	_group_size = (texture_size - 1) / 8.0 + 1 as int
	
	# Create shader, pipeline & push_constant
	var shader_file : RDShaderFile = load(shader_path) as RDShaderFile
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var push_constant_data : Array = init_data[1]
	push_constant = _create_push_constant(push_constant_data, texture_size)
	
	# Create texture formats
	var r16f_tf : RDTextureFormat = TextureFormat.get_r16f(texture_size)
	var rgba16f_tf : RDTextureFormat = TextureFormat.get_rgba16f(texture_size)
	var rgba32f_tf : RDTextureFormat = TextureFormat.get_rgba32f(texture_size)

	base_textures_rds[0] = rd.texture_create(rgba16f_tf, RDTextureView.new(), [])
	base_textures_rds[1] = rd.texture_create(rgba16f_tf, RDTextureView.new(), [])
	base_textures_rds[2] = rd.texture_create(rgba16f_tf, RDTextureView.new(), [])
	base_textures_rds[3] = rd.texture_create(r16f_tf, RDTextureView.new(), [])
	base_textures_rds[4] = rd.texture_create(rgba16f_tf, RDTextureView.new(), [])
	base_textures_rds[5] = rd.texture_create(rgba16f_tf, RDTextureView.new(), [])

	var base_texture_uniforms : Array[RDUniform] = []
	for i : int in range(6):
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = i
		uniform.add_id(base_textures_rds[i])
		base_texture_uniforms.append(uniform)
	_base_texture_uniform_set = rd.uniform_set_create(base_texture_uniforms, shader, 0)
	
	var image_buffer_textures : Array = init_data[2]
	var num_image_buffers : int = image_buffer_textures.size() 
	
	_buffer_rds.resize(num_image_buffers)
	#buffer_sets.resize(num_image_buffers)
	_buffer_rds.fill(RID())
	#buffer_sets.fill(RID())
	
	for i : int in num_image_buffers:
		var buffer_tf : RDTextureFormat
		match image_buffer_textures[i]:
			tf_size.R16F:
				buffer_tf = r16f_tf
			tf_size.RGBA32F:
				buffer_tf = rgba32f_tf
		_buffer_rds[i] = rd.texture_create(buffer_tf, RDTextureView.new(), [])

	var image_buffer_uniforms : Array[RDUniform] = []
	for i : int in num_image_buffers:
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = i
		uniform.add_id(_buffer_rds[i])
		image_buffer_uniforms.append(uniform)
	_image_buffer_uniform_set = rd.uniform_set_create(image_buffer_uniforms, shader, 1)
	
	var storage_buffer_types : Array = init_data[3]
	var storage_buffer_data : Array = init_data[4]
	var num_storage_buffers : int = storage_buffer_data.size()
	
	_uniform_rds.resize(num_storage_buffers)
	_uniform_sets.resize(num_storage_buffers)
	_uniform_rds.fill(RID())
	_uniform_sets.fill(RID())
	
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
		
		_uniform_rds[i] = rd.storage_buffer_create(packed_data.size(), packed_data)
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = 0
		uniform.add_id(_uniform_rds[i])
		_uniform_sets[i] = rd.uniform_set_create([uniform], shader, i + 2)


func set_texture_rids() -> void:
	albedo.texture_rd_rid = base_textures_rds[0]
	occlusion.texture_rd_rid = base_textures_rds[1]
	roughness.texture_rd_rid = base_textures_rds[2]
	metallic.texture_rd_rid = base_textures_rds[3]
	normal.texture_rd_rid = base_textures_rds[4]


# Update storage buffer where data has been updated, but the buffer size has not been changed.
func update_storage_buffer(index : int, data : Array) -> void:
	var error : Error = rd.buffer_update(_uniform_rds[index], 0, data.size(), data)
	if error:
		Logger.puts_error("Failed to update storage buffer", error)


# Rebuild storage buffer when data has been updated such that the size of the buffer has changed and will overflow.
func rebuild_storage_buffer(index : int, u_set : int, data : Array) -> void:
	_uniform_rds[index] = rd.storage_buffer_create(data.size(), data)
	var uniform_block : RDUniform = RDUniform.new()
	uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_block.binding = 0
	uniform_block.add_id(_uniform_rds[index])
	_uniform_sets[index] = rd.uniform_set_create([uniform_block], shader, u_set)


@warning_ignore("return_value_discarded")
func _create_push_constant(push_constant_data : Array, texture_size : int) -> PackedFloat32Array:
	var _push_constant : PackedFloat32Array = PackedFloat32Array(push_constant_data)
	_push_constant.push_back(texture_size)
	_push_constant.push_back(stage)
	
	var push_constant_size : int = _push_constant.size()
	_push_constant_stage_index = push_constant_size - 1
	
	if (push_constant_size * 4) % 16 != 0:
		var bytes_needed : int = (16 - (push_constant_size * 4 % 16))
		for i : int in (bytes_needed / 4.0):
			_push_constant.push_back(0.0)
			
	return _push_constant


@warning_ignore("return_value_discarded")
func _render_process() -> void:
	push_constant.set(_push_constant_stage_index, stage)
	
	if stage != _max_stage:
			stage += 1
		
	var packed_byte_array : PackedByteArray = push_constant.to_byte_array()

	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, _base_texture_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, _image_buffer_uniform_set, 1)
	
	for i : int in _uniform_sets.size():
		rd.compute_list_bind_uniform_set(compute_list, _uniform_sets[i], i + 2)
	
	rd.compute_list_set_push_constant(compute_list, packed_byte_array, packed_byte_array.size())

	rd.compute_list_dispatch(compute_list, _group_size, _group_size, 1)
	rd.compute_list_end()
