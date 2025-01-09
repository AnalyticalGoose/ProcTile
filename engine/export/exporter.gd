class_name Exporter
extends RefCounted

enum Filetype {
	PNG,
	JPG
}


var compute_shader : ComputeShader
var export_window : ExportWindow

var rd: RenderingDevice
var basetextures: Array[RID]
var export_resolution : int
var shader_resolution : int
var interpolate_export : bool
var interpolation_type : int
var filetype : Filetype
var texture_name: String = "brick_wall"

var export_progress : int = 0:
	set(val):
		export_progress += val
		export_window.progress_update(export_progress)


@warning_ignore("return_value_discarded")
func export(export_template_data : Array[Array], type : Filetype, path: String) -> void:
	basetextures = compute_shader._base_textures_rds
	rd = compute_shader.rd
	interpolate_export = export_resolution != shader_resolution
	filetype = type

	var export_data : Array[Array] = export_template_data
	
	for task : Array in export_data:
		var thread : Thread = Thread.new()
		thread.start(_threaded_export.bind(
				shader_resolution, task[0], task[1], path + "/" + texture_name + task[2], thread))


func _threaded_export(size: int, texture_index: int, format: Image.Format, path_name: String, thread : Thread) -> void:
	var texture_data: PackedByteArray = rd.texture_get_data(basetextures[texture_index], 0)
	var texture: Image = Image.create_from_data(size, size, false, format, texture_data)
	
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
	export_progress += 20
