class_name ExportWindow
extends Window

@export var file_dialog : FileDialog
@export var directory_btn : Button
@export var template_options : OptionButton
@export var resolution_btn : OptionButton
@export var interp_label : Label
@export var interp_btn : OptionButton
@export var filename_labels_container : VBoxContainer
@export var button_container : HBoxContainer
@export var progress_bar : ProgressBar

var renderer : Renderer
var compute_shader : ComputeShader
var exporter : Exporter

var output_resolution : int:
	set(resolution):
		output_resolution = resolution
		if resolution != renderer.texture_size:
			interp_label.self_modulate = Color(Color.WHITE)
			interp_btn.disabled = false
		else:
			interp_label.self_modulate = Color(Color.GRAY)
			interp_btn.disabled = true
var output_template : int = 1 # ORM packed, split, glb etc
var output_filetype : int = 0 # png / jpg etc
var output_directory : String:
	set(directory):
		output_directory = directory
		directory_btn.set_text(directory)
var interpolation_type : int = Image.INTERPOLATE_LANCZOS

var filetype_string : String = ".png"
var material_name : String = "brick_wall"

var export_template_data : Array[Array]
var filename_maps : Array[String] = []
var filename_labels : Array[Node]





# called from exporter instance to update progress bar and cleaup at 100%
func progress_update(progress : int) -> void:
	progress_bar.set_value_no_signal(progress)
	if progress >= 100:
		# Stupid but feels better to have the progress reach 100 before closing
		await get_tree().create_timer(0.5).timeout
		button_container.show()
		progress_bar.hide()
		progress_bar.set_value_no_signal(0.0)
		exporter = null
		renderer.set_process(true)


func _ready() -> void:
	renderer = $/root/ProcTile/Renderer as Renderer
	compute_shader = renderer.compute_shader
	var template_menu : PopupMenu = template_options.get_popup()
	for i : int in template_menu.get_item_count():
		template_menu.set_item_as_radio_checkable(i, false)
		
	output_directory = "C:/Users/Harry/Desktop/Painter/ProcTileTest"
	
	output_resolution = DataManager.settings_data[1].export_resolution
	
	# If it works it ain't stupid, ffs...
	resolution_btn.select(resolution_btn.get_item_index(output_resolution / 512.0 as int))
	
	export_template_data = ExportTemplate.get_export_template_data(output_template)
	
	for dataline : Array in export_template_data:
		filename_maps.append(dataline[2])
	filename_labels = filename_labels_container.get_children()


func _on_close_requested() -> void:
	if exporter:
		exporter = null
	queue_free()


func _on_directory_btn_pressed() -> void:
	file_dialog.show()


func _on_file_dialog_close_requested() -> void:
	file_dialog.hide()


func _on_template_button_item_selected(template_index: int) -> void:
	output_template = template_index
	
	export_template_data = ExportTemplate.get_export_template_data(template_index)
	filename_maps.clear()
	for dataline : Array in export_template_data:
		filename_maps.append(dataline[2])
		
	for i : int in filename_labels.size():
		if i < filename_maps.size():
			(filename_labels[i] as Label).set_text(material_name + filename_maps[i] + filetype_string)
			(filename_labels[i] as Label).show()
		else:
			(filename_labels[i] as Label).hide()


func _on_file_dialog_dir_selected(dir: String) -> void:
	output_directory = dir


func _on_export_button_pressed() -> void:
	# Stop rendering (just in case)
	renderer.set_process(false)
	
	button_container.hide()
	progress_bar.show()
	
	exporter = Exporter.new()
	exporter.compute_shader = compute_shader
	exporter.export_window = self
	exporter.export_resolution = output_resolution
	exporter.shader_resolution = renderer.texture_size
	exporter.interpolation_type = interpolation_type
	exporter.export(export_template_data, output_filetype, output_directory)


func _on_resolution_btn_item_selected(index : int) -> void:
	match index:
		0:
			output_resolution = 512
		1:
			output_resolution = 1024
		2:
			output_resolution = 2048
		3:
			output_resolution = 4096


func _on_interpolation_btn_item_selected(index: int) -> void:
	interpolation_type = index


func _on_format_btn_item_selected(index: int) -> void:
	output_filetype = index
	
	match output_filetype:
		0:
			filetype_string = ".png"
		1:
			filetype_string = ".jpg"
	
	_set_filename_labels_text()


func _on_line_edit_text_changed(new_text: String) -> void:
	material_name = new_text
	_set_filename_labels_text()



func _set_filename_labels_text() -> void:
	for i : int in filename_labels.size():
		if i < filename_maps.size():
			(filename_labels[i] as Label).set_text(material_name + filename_maps[i] + filetype_string)
