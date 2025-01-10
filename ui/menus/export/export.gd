class_name ExportWindow
extends Window
## Export window constructor and management class.
## 
## Handles the instantiation and setup of the export window, loading the
## default export formats from user settings, user gui inputs and the creation
## of the Exporter class.

@export var file_dialog : FileDialog
@export var directory_btn : Button
@export var template_options : OptionButton
@export var resolution_btn : OptionButton
@export var format_btn : OptionButton
@export var interp_label : Label
@export var interp_btn : OptionButton
@export var filename_line_edit : LineEdit
@export var filename_labels_container : VBoxContainer
@export var button_container : HBoxContainer
@export var progress_bar : ProgressBar

var renderer : Renderer
var compute_shader : ComputeShader
var exporter : Exporter

var output_resolution : int:
	set(value):
		output_resolution = value
		# update interpolation state
		var is_interpolation_enabled : bool = output_resolution != renderer.texture_size
		interp_label.self_modulate = Color(Color.WHITE if is_interpolation_enabled else Color.GRAY)
		interp_btn.disabled = not is_interpolation_enabled

var output_template : int
var output_filetype : int
var output_directory : String:
	set(directory):
		output_directory = directory
		directory_btn.text = directory

var interpolation_type : int
var filetype_string : String
var material_name : String

var export_template_data : Array[Array] = []
var filename_maps : Array[String] = []
var filename_labels : Array[Node] = []

const RESOLUTIONS : Array[int] = [512, 1024, 2048, 4096]
const FILE_TYPES_STRINGS : Array[String] = [".png", ".jpg"]


func _ready() -> void:
	_init_dependancies()
	_load_export_settings()
	_setup_export_ui()
	_set_radio_buttons()


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


func _init_dependancies() -> void:
	renderer = $/root/ProcTile/Renderer as Renderer
	compute_shader = renderer.compute_shader


func _set_radio_buttons() -> void:
	var template_menu : PopupMenu = template_options.get_popup()
	for i : int in template_menu.get_item_count():
		template_menu.set_item_as_radio_checkable(i, false)


func _load_export_settings() -> void:
	var settings_data : Dictionary = DataManager.settings_data[1]
	output_directory = settings_data.get("export_directory", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	output_template = settings_data.export_template
	output_resolution = settings_data.export_resolution
	output_filetype = settings_data.export_format
	filetype_string = FILE_TYPES_STRINGS[output_filetype]
	interpolation_type = settings_data.export_interpolation


func _setup_export_ui() -> void:
	# get template data
	export_template_data = ExportTemplate.get_export_template_data(output_template)
	for dataline : Array in export_template_data:
		filename_maps.append(dataline[2])

	# set filename labels
	filename_labels = filename_labels_container.get_children()
	for i : int in filename_labels.size():
		if i >= filename_maps.size():
			(filename_labels[i] as Label).hide()

	# update ui from settings
	template_options.select(output_template)
	resolution_btn.select(resolution_btn.get_item_index(output_resolution / 512.0 as int))
	format_btn.select(output_filetype)
	interp_btn.select(interpolation_type)
	filename_line_edit.text = renderer.asset_name
	_on_line_edit_text_changed(renderer.asset_name)


func _set_filename_labels_text() -> void:
	for i : int in filename_labels.size():
		if i < filename_maps.size():
			(filename_labels[i] as Label).set_text(material_name + filename_maps[i] + filetype_string)


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


func _on_resolution_btn_item_selected(index : int) -> void:
	output_resolution = RESOLUTIONS[index]


func _on_interpolation_btn_item_selected(index: int) -> void:
	interpolation_type = index


func _on_format_btn_item_selected(index: int) -> void:
	output_filetype = index
	filetype_string = FILE_TYPES_STRINGS[index]
	_set_filename_labels_text()


func _on_line_edit_text_changed(new_text: String) -> void:
	material_name = new_text
	_set_filename_labels_text()


func _on_close_requested() -> void:
	if exporter:
		exporter = null
	queue_free()


func _on_save_btn_pressed() -> void:
	DataManager.save_export_settings(
		output_directory, output_template, output_resolution, output_filetype, interpolation_type)


func _on_export_button_pressed() -> void:
	renderer.set_process(false)
	button_container.hide()
	progress_bar.show()
	
	exporter = Exporter.new()
	exporter.setup_properties(
			compute_shader, self, material_name, output_resolution, 
			renderer.texture_size, interpolation_type
	)
	
	exporter.export(export_template_data, output_filetype, output_directory)
