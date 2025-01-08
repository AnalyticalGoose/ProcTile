class_name Exporter
extends RefCounted

var compute_shader : ComputeShader
var export_window : ExportWindow

var rd: RenderingDevice
var basetextures: Array[RID]
var texture_name: String = "brick_wall"

var threads: Array = []
var export_progress : int = 0:
	set(val):
		export_progress += val
		export_window.progress_update(export_progress)


@warning_ignore("return_value_discarded")
func export(path: String) -> void:
	basetextures = compute_shader._base_textures_rds
	rd = compute_shader.rd

	var export_tasks : Array = [
		[0, 4096, Image.FORMAT_RGBAF, path + "/" + texture_name + "_baseColor.png"],
		[1, 4096, Image.FORMAT_RGBAF, path + "/" + texture_name + "_occlusion.png"],
		[2, 4096, Image.FORMAT_RGBAF, path + "/" + texture_name + "_roughness.png"],
		[3, 4096, Image.FORMAT_RH, path + "/" + texture_name + "_metallic.png"],
		[4, 4096, Image.FORMAT_RGBAH, path + "/" + texture_name + "_normal.png"]
	]

	for task : Array in export_tasks:
		var thread : Thread = Thread.new()
		threads.append(thread)
		thread.start(_threaded_export.bind(task[0], task[1], task[2], task[3], thread))


func _threaded_export(texture_index: int, size: int, format: Image.Format, path_name: String, thread : Thread) -> void:
	var texture_data: PackedByteArray = rd.texture_get_data(basetextures[texture_index], 0)
	var texture: Image = Image.create_from_data(size, size, false, format, texture_data)
	if !texture.save_png(path_name):
		call_deferred("_on_thread_completed", thread)


func _on_thread_completed(thread : Thread) -> void:
	thread.wait_to_finish()
	export_progress += 20
