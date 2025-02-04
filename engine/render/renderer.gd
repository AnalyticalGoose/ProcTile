extends Node3D
class_name Renderer

var compute_shader : ComputeShader
var asset_name : String
var texture_size : int
var paused : bool = false

@onready var shader_material : ShaderMaterial = (
		$/root/ProcTile/Renderer/MeshPivot/Mesh as MeshInstance3D
		).material_override as ShaderMaterial


func free_compute_resources() -> void:
	set_process(false)
		
	for rid : RID in compute_shader._buffer_rds:
		compute_shader.rd.free_rid(rid)
	for rid : RID in compute_shader.base_textures_rds:
		compute_shader.rd.free_rid(rid)
		
	shader_material.set_shader_parameter("albedo_input", Texture2DRD.new())
	shader_material.set_shader_parameter("occlusion_input", Texture2DRD.new())
	shader_material.set_shader_parameter("roughness_input", Texture2DRD.new())
	shader_material.set_shader_parameter("metallic_input", Texture2DRD.new())
	shader_material.set_shader_parameter("normal_input", Texture2DRD.new())


func _ready() -> void:
	set_process(false)
	texture_size = DataManager.settings_data[0].shader_resolution


func _process(_delta: float) -> void: # does this need to be in process?
	RenderingServer.call_on_render_thread(compute_shader._render_process)


func create_compute_shader() -> ComputeShader:
	compute_shader = ComputeShader.new()
	return compute_shader


func set_shader_material(shader_data : Array, shader_path : String) -> void:
	RenderingServer.call_on_render_thread(compute_shader.init_compute.bind(shader_data, texture_size, shader_path))

	# Linking compute and material shader
	compute_shader.albedo = shader_material.get_shader_parameter("albedo_input")
	compute_shader.occlusion = shader_material.get_shader_parameter("occlusion_input")
	compute_shader.roughness = shader_material.get_shader_parameter("roughness_input")
	compute_shader.metallic = shader_material.get_shader_parameter("metallic_input")
	compute_shader.normal = shader_material.get_shader_parameter("normal_input")
	RenderingServer.call_on_render_thread(compute_shader.set_texture_rids)
	
	set_process(true)
