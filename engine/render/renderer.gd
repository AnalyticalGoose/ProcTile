extends Node3D
class_name Renderer

var compute_shader : ComputeShader


# TODO: programme is almost entirely memory bandwidth limited, seek ways to lower throughput requirements:
## - Explore using smaller textures where possible r16 instead of rgba32 for example?


# TODO: refactor these out to database etc
var texture_size : int = 1024 * 4
var shader_path : String = "res://materials/brick_wall/brick_wall_compute.glsl"


# TODO: functions for cleaning up compute resources:
# _free_compute_resources()
# Review bindings to render thread calls, static are not likely to be needed


func _ready() -> void:
	set_process(false)


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
