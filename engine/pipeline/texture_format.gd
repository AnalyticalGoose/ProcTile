extends RefCounted
class_name TextureFormat


static func get_r16f(texture_size : int) -> RDTextureFormat:
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		#RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		#RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	return tf


static func get_rgba16f(texture_size : int) -> RDTextureFormat:
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		#RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		#RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	return tf


static func get_rgba32f(texture_size : int) -> RDTextureFormat:
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		#RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		#RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	return tf
