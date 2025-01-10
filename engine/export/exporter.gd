class_name Exporter
extends RefCounted
## Exporter shader constructor class.
## 
## Handles the image processing and saving on export request, thread management,
## cleanup and sending progress data back to the ExportWindow.

enum Filetype {
	PNG,
	JPG
}

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
var filetype : Filetype
var texture_name: String

var progress_tick_val : int
var export_progress : int = 0:
	set(val):
		export_progress += val
		export_window.progress_update(export_progress)


func setup_properties(
		_compute_shader : ComputeShader, _export_window : ExportWindow, _material_name : String, 
		_export_resolution : int, _shader_resolution : int, _interpolation_type : int
) -> void:
	compute_shader = _compute_shader
	export_window = _export_window
	texture_name = _material_name
	export_resolution = _export_resolution
	shader_resolution = _shader_resolution
	interpolation_type = _interpolation_type


@warning_ignore("return_value_discarded")
func export(export_template_data : Array[Array], type : Filetype, path: String) -> void:
	basetextures = compute_shader.base_textures_rds
	rd = compute_shader.rd
	interpolate_export = export_resolution != shader_resolution
	filetype = type

	progress_tick_val = ceili(100 / float(export_template_data.size()))
	
	for task : Array in export_template_data:
		var thread : Thread = Thread.new()
		thread.start(_threaded_export.bind(
				task[0], task[1], path + "/" + texture_name + task[2], thread))


func _threaded_export(texture_index: int, format: Image.Format, path_name: String, thread : Thread) -> void:
	var texture_data: PackedByteArray = rd.texture_get_data(basetextures[texture_index], 0)
	var texture: Image = Image.create_from_data(shader_resolution, shader_resolution, false, format, texture_data)
	
	if interpolate_export:
		texture.resize(export_resolution, export_resolution, interpolation_type)
	
	match filetype:
		Filetype.PNG:
			if !texture.save_png(path_name + ".png"):
				call_deferred("_on_thread_completed", thread)
			else:
				Logger.puts_error("Export to " + path_name + " failed")
		Filetype.JPG:
			if !texture.save_jpg(path_name + ".jpg", 1.0):
				call_deferred("_on_thread_completed", thread)
			else:
				Logger.puts_error("Export to " + path_name + " failed")



func _on_thread_completed(thread : Thread) -> void:
	thread.wait_to_finish()
	export_progress += progress_tick_val
