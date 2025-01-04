extends RefCounted
class_name ComputeShader

var renderer : Renderer

var albedo : Texture2DRD
var roughness : Texture2DRD
var normal : Texture2DRD
var occlusion : Texture2DRD

## where is this set? And how will it be sent / retrieved on init?
## user settings perhaps?
var texture : Texture2DRD
var texture_size : Vector2i
var next_texture : int = 0

var rd : RenderingDevice
var shader : RID
var pipepline : RID
var push_constant : PackedFloat32Array
var texture_rds : Array[RID] = [RID(), RID(), RID()]
var texture_sets : Array[RID] = [RID(), RID(), RID()]

## generated textures for lookup / buffers
#var base_textures_rds : Array[RID] = [RID(), RID(), RID(), RID()]
#var base_texture_sets : Array[RID] = [RID(), RID(), RID(), RID()]
#
## testing a smaller data format r16f for memory performance
#var test_small_rds : Array[RID] = [RID()]
#var test_small_sets : Array[RID] = [RID()]

# Albedo, roughness, normal, occlusion textures
var base_textures_rds : Array[RID] = [RID(), RID(), RID(), RID()]
var base_texture_sets : Array[RID] = [RID(), RID(), RID(), RID()]

# other buffers
var buffer_rds : Array[RID] = [RID(), RID(), RID(), RID(), RID()]
var buffer_sets : Array[RID] = [RID(), RID(), RID(), RID(), RID()]

# uniform storage buffer
var uniform_rds : Array[RID] = [RID(), RID(), RID(), RID()]
var uniform_sets : Array[RID] = [RID(), RID(), RID(), RID()]

## temp - grunge params
var tone_value : float = 0.80
var tone_width : float = 0.48

var brick_colour_seed : float = 0.064537466

var perlin_seed_1 : float = 0.612547636
var perlin_seed_2 : float = 0.587890089
var perlin_seed_3 : float = 0.509320438
var perlin_seed_4 : float = 0.941759408
var perlin_seed_5 : float = 0.459213525

var perlin_seed_6 : float = 0.762268782
var b_noise_seed : float = 0.00

var seeds_array : Array[float] = [
		brick_colour_seed, perlin_seed_1, perlin_seed_2, perlin_seed_3, 
		perlin_seed_4, perlin_seed_5, perlin_seed_6, b_noise_seed,
]

var seeds : PackedByteArray = PackedFloat32Array(seeds_array).to_byte_array()

		
var mortar_col : PackedByteArray = PackedVector4Array([Vector4(1.00, 0.93, 0.81, 1.00)]).to_byte_array()
	
var gradient_offset_array : Array[float] = [0.00, 0.15, 0.34, 0.48, 0.61, 0.82, 1.00]
var gradient_offsets : PackedByteArray = PackedFloat32Array(gradient_offset_array).to_byte_array()

var gradient_colour_array : Array[Vector4] = [
		Vector4(0.78, 0.36, 0.18, 1.0),
		Vector4(0.76, 0.34, 0.17, 1.0),
		Vector4(0.82, 0.40, 0.24, 1.0),
		Vector4(0.76, 0.36, 0.21, 1.0),
		Vector4(0.80, 0.40, 0.24, 1.0),
		Vector4(0.82, 0.41, 0.19, 1.0),
		Vector4(0.89, 0.49, 0.24, 1.0),
	]
var gradient_colours : PackedByteArray = PackedVector4Array(gradient_colour_array).to_byte_array()


#var scale : Vector2 = Vector2(6.0, 6.0)
#var scale : float = 6.0

#var iterations : int = 10
#var persistance : float = 0.61
#var offset : float = 0.00
#var mingle_opaticy : float = 1.0
#var mingle_step : float = 0.5
var mingle_smooth : float = 0.5
#var mingle_warp_x : float = 0.5
#var mingle_warp_y : float = 0.5
var mingle_warp_strength : float = 2.0

# temp - b-noise params
#var b_noise_rs : float = 6.0
#var b_noise_control_x : float = 0.29
#var b_noise_control_y : float = 0.71

#var b_noise_brightness : float = 0.22
var b_noise_contrast : float = 0.50

# temp - will need to be bound to the call....
var pattern : float = 0.0
var repeat : float = 1.0
var rows : float = 10.0
var columns : float = 5.0
var row_offset : float = 0.5
var mortar : float = 3.0
var bevel : float = 5.0
var rounding : float = 0.0

var damage_scale_x : float = 10.00
var damage_scale_y : float = 15.00
var damage_iterations : float = 3.0
var damage_persistence : float = 0.50;

var stage : float = 0.0
var max_stage : float = 3.0

var stage_1 : bool = false


@warning_ignore("return_value_discarded")
func _render_process() -> void:
	push_constant.set(18, stage)
	
	if stage != max_stage:
			stage += 1
	#else:
		#renderer.set_process(false)
		
	var packed_byte_array : PackedByteArray = push_constant.to_byte_array()

	if packed_byte_array.size() % 16 == 0:
		pass
	else:
		Logger.stop_renderer("Push constant size is invalid - Renderer paused")

	next_texture = (next_texture + 1) % 3
	if texture:
		texture.texture_rd_rid = texture_rds[next_texture]
	
	var x_groups : int = (texture_size.x - 1) / 8.0 + 1 as int
	var y_groups : int = (texture_size.y - 1) / 8.0 + 1 as int
	
	var next_set : RID = texture_sets[next_texture]
	var current_set : RID = texture_sets[(next_texture - 1) % 3]
	var previous_set : RID = texture_sets[(next_texture - 2) % 3]
	
	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipepline)
	rd.compute_list_bind_uniform_set(compute_list, current_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, previous_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, next_set, 2)
	
	rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[0], 3)
	rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[1], 4)
	rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[2], 5)
	rd.compute_list_bind_uniform_set(compute_list, base_texture_sets[3], 6)
	
	rd.compute_list_bind_uniform_set(compute_list, buffer_sets[0], 7)
	rd.compute_list_bind_uniform_set(compute_list, buffer_sets[1], 8)
	rd.compute_list_bind_uniform_set(compute_list, buffer_sets[2], 9)
	rd.compute_list_bind_uniform_set(compute_list, buffer_sets[3], 10)
	rd.compute_list_bind_uniform_set(compute_list, buffer_sets[4], 11)
	
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[0], 12)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[1], 13)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[2], 14)
	rd.compute_list_bind_uniform_set(compute_list, uniform_sets[3], 15)
	
	rd.compute_list_set_push_constant(compute_list, packed_byte_array, packed_byte_array.size())
	
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	


func _init_compute(_texture_size : Vector2i, shader_path : String) -> void:
	rd = RenderingServer.get_rendering_device()
	texture_size = _texture_size
	
	# Create shader, pipeline & push_constant
	var shader_file : RDShaderFile = load(shader_path) as RDShaderFile
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipepline = rd.compute_pipeline_create(shader)
	push_constant = _create_push_constant()
	
	## This will change - probably need to store in enum and reference?
	# Create texture format
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size.x
	tf.height = texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		#RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		#RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	
	for i : int in range(3):
		texture_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])
		var err : Error = rd.texture_clear(texture_rds[i], Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
		if err:
			Logger.puts_error("Failed to clear RDTexture", err)
		texture_sets[i] = _create_uniform_set(texture_rds[i])
		
	for i : int in range(base_textures_rds.size()):
		base_textures_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])
		var err : Error = rd.texture_clear(base_textures_rds[i], Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
		if err:
			Logger.puts_error("Failed to clear RDTexture", err)
		base_texture_sets[i] = _create_uniform_set(base_textures_rds[i])
	
	for i : int in range(buffer_rds.size()):
		if i == 1 or i == 4:
			_create_image_buffer(i)
		else:
			buffer_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])
			var err : Error = rd.texture_clear(buffer_rds[i], Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
			if err:
				Logger.puts_error("Failed to clear RDTexture", err)
			buffer_sets[i] = _create_uniform_set(buffer_rds[i])
	
	
	# test uniform storage buffer - this should really be a uniform buffer, not storage as we know the size.
	uniform_rds[0] = rd.storage_buffer_create(seeds.size(), seeds)
	var uniform_block : RDUniform = RDUniform.new()
	uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_block.binding = 0
	uniform_block.add_id(uniform_rds[0])
	uniform_sets[0] = rd.uniform_set_create([uniform_block], shader, 12)
	
	uniform_rds[1] = rd.storage_buffer_create(gradient_offsets.size(), gradient_offsets)
	var uniform_block_ : RDUniform = RDUniform.new()
	uniform_block_.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_block_.binding = 0
	uniform_block_.add_id(uniform_rds[1])
	uniform_sets[1] = rd.uniform_set_create([uniform_block_], shader, 13)
	
	uniform_rds[2] = rd.storage_buffer_create(gradient_colours.size(), gradient_colours)
	var _uniform_block : RDUniform = RDUniform.new()
	_uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	_uniform_block.binding = 0
	_uniform_block.add_id(uniform_rds[2])
	uniform_sets[2] = rd.uniform_set_create([_uniform_block], shader, 14)
	
	# mortar colour
	uniform_rds[3] = rd.storage_buffer_create(mortar_col.size(), mortar_col)
	var __uniform_block : RDUniform = RDUniform.new()
	__uniform_block.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	__uniform_block.binding = 0
	__uniform_block.add_id(uniform_rds[3])
	uniform_sets[3] = rd.uniform_set_create([__uniform_block], shader, 15)
	
	
	Logger.puts_success("init compute shader success")


@warning_ignore("return_value_discarded")
func _create_push_constant() -> PackedFloat32Array:
	var pc : PackedFloat32Array = PackedFloat32Array()

	pc.push_back(pattern)
	pc.push_back(rows)
	pc.push_back(columns)
	pc.push_back(row_offset)
	pc.push_back(mortar)
	pc.push_back(bevel)
	pc.push_back(rounding)
	pc.push_back(repeat)

	#pc.push_back(scale)
	pc.push_back(mingle_warp_strength)
	pc.push_back(tone_value)
	pc.push_back(mingle_smooth)
	pc.push_back(tone_width)
	
	#pc.push_back(b_noise_rs)
	#pc.push_back(b_noise_control_x)
	#pc.push_back(b_noise_control_y)
	#pc.push_back(b_noise_brightness)
	pc.push_back(b_noise_contrast)
	
	pc.push_back(damage_scale_x)
	pc.push_back(damage_scale_y)
	pc.push_back(damage_iterations)
	pc.push_back(damage_persistence)

	pc.push_back(texture_size.x)
	pc.push_back(stage)
	
	pc.push_back(0.0)
	return pc



func _create_uniform_set(texture_rd : RID) -> RID:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	
	return rd.uniform_set_create([uniform], shader, 0)
	

func _create_image_buffer(i : int) -> void:
	var tf : RDTextureFormat = TextureFormat.get_r16f(texture_size)
	
	buffer_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])
	var err : Error = rd.texture_clear(buffer_rds[i], Color(0.0, 0.0, 0.0, 0.0), 0, 1, 0, 1)
	if err:
		Logger.puts_error("Failed to clear RDTexture", err)
	buffer_sets[i] = _create_uniform_set(buffer_rds[i])


func _set_texture_rids() -> void:
	albedo.texture_rd_rid = base_textures_rds[0]
	roughness.texture_rd_rid = base_textures_rds[1]
	normal.texture_rd_rid = base_textures_rds[2]
	occlusion.texture_rd_rid = base_textures_rds[3]


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
