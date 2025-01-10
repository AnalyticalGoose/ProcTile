extends Node3D
class_name Renderer

var compute_shader : ComputeShader



# TODO: refactor these out to database etc
var texture_size : int
var shader_path : String = "res://materials/brick_wall/brick_wall_compute.glsl"
var asset_name : String

# TODO: functions for cleaning up compute resources:
func free_compute_resources() -> void:
	set_process(false)
	compute_shader = null



func _ready() -> void:
	set_process(false)
	texture_size = DataManager.settings_data[0].shader_resolution


func _process(_delta: float) -> void:
	RenderingServer.call_on_render_thread(compute_shader._render_process)


func create_compute_shader() -> ComputeShader:
	compute_shader = ComputeShader.new()
	#compute_shader.renderer = self
	return compute_shader


func set_shader_material(shader_data : Array) -> void:
	RenderingServer.call_on_render_thread(compute_shader.init_compute.bind(shader_data, texture_size, shader_path))

	# Linking compute and material shader
	var material : ShaderMaterial = ($Mesh as MeshInstance3D).material_override as ShaderMaterial
	compute_shader.albedo = material.get_shader_parameter("albedo_input")
	compute_shader.occlusion = material.get_shader_parameter("occlusion_input")
	compute_shader.roughness = material.get_shader_parameter("roughness_input")
	compute_shader.metallic = material.get_shader_parameter("metallic_input")
	compute_shader.normal = material.get_shader_parameter("normal_input")
	RenderingServer.call_on_render_thread(compute_shader.set_texture_rids)
	
	set_process(true)
