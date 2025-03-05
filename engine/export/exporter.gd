class_name Exporter
extends RefCounted
## Exporter shader constructor class.
## 
## Handles the image / mesh processing and saving on export request, thread management,
## cleanup and sending progress data back to the ExportWindow.

enum TextureType { PNG, JPG }
enum MeshType { OBJ }

# Dependancies
var compute_shader : ComputeShader
var export_window : ExportWindow
var rd: RenderingDevice
var basetextures: Array[RID]

# Export settings
var export_resolution : int
var shader_resolution : int
var interpolate_export : bool
var interpolation_type : int
var mesh_format : int # file format: obj
var export_mesh : int
var mesh_settings_instance : MeshSettings
var texture_type : TextureType
var texture_name: String

var progress_tick_val : int
var export_progress : int = 0:
	set(val):
		export_progress = val
		export_window.progress_update(export_progress)

var texture_data : Array[PackedByteArray] = [
												PackedByteArray([]), 
												PackedByteArray([]), 
												PackedByteArray([]), 
												PackedByteArray([]), 
												PackedByteArray([]), 
												PackedByteArray([])
											]


func setup_properties(
		_compute_shader : ComputeShader, 
		_export_window : ExportWindow, 
		_material_name : String, 
		_export_resolution : int, 
		_shader_resolution : int, 
		_interpolation_type : int, 
		_export_mesh : int, 
		_mesh_format : int,
		_mesh_settings_instance : MeshSettings,
) -> void:
	
	compute_shader = _compute_shader
	export_window = _export_window
	texture_name = _material_name
	export_resolution = _export_resolution
	shader_resolution = _shader_resolution
	interpolation_type = _interpolation_type
	export_mesh = _export_mesh
	if export_mesh:
		mesh_format = _mesh_format
		mesh_settings_instance = _mesh_settings_instance


func export(export_template_data : Array[Array], type : TextureType, path: String) -> void:
	basetextures = compute_shader.base_textures_rds
	rd = compute_shader.rd
	interpolate_export = export_resolution != shader_resolution
	texture_type = type
	
	progress_tick_val = ceili(100 / float(export_template_data.size() + export_mesh))

	for task : Array in export_template_data:
		var thread : Thread = Thread.new()
		@warning_ignore("return_value_discarded")
		thread.start(_threaded_texture_export.bind(
				task[0], task[1], path + "/" + texture_name + task[2], thread))
	
	if export_mesh:
		var thread : Thread = Thread.new()
		@warning_ignore("return_value_discarded")
		thread.start(_threaded_mesh_export.bind(path + "/" + texture_name, thread))


func _threaded_texture_export(texture_index: int, format: Image.Format, path_name: String, thread : Thread) -> void:
	RenderingServer.call_on_render_thread(_get_texture_data.bind(basetextures[texture_index], texture_index))
	
	while texture_data[texture_index].size() != 134217728:
		pass
	
	var texture: Image = Image.create_from_data(shader_resolution, shader_resolution, false, format, texture_data[texture_index])
	
	if interpolate_export:
		texture.resize(export_resolution, export_resolution, interpolation_type)
	
	match texture_type:
		TextureType.PNG:
			if !texture.save_png(path_name + ".png"):
				call_deferred("_on_thread_completed", thread)
			else:
				Logger.puts_error("Export to " + path_name + " failed")
		TextureType.JPG:
			if !texture.save_jpg(path_name + ".jpg", 1.0):
				call_deferred("_on_thread_completed", thread)
			else:
				Logger.puts_error("Export to " + path_name + " failed")


func _threaded_mesh_export(path_name: String, thread : Thread) -> void:
	match mesh_format:
		MeshType.OBJ:
			OBJExporter.export_obj(mesh_settings_instance.surface_array, path_name + "_mesh.obj")
			call_deferred("_on_thread_completed", thread)


func _on_thread_completed(thread : Thread) -> void:
	thread.wait_to_finish()
	export_progress += progress_tick_val


func _get_texture_data(texture : RID, index : int) -> void:
	texture_data[index] = rd.texture_get_data(texture, 0)
