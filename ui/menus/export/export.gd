class_name ExportWindow
extends Window
## Export window constructor and management class.
## 
## Handles the instantiation and setup of the export window, loading the
## default export formats from user settings, user gui inputs and the creation
## of the Exporter class.

signal normals_recalculated

@export var file_dialog : FileDialog
@export var directory_btn : Button
@export var template_options_3D : OptionButton
@export var template_options_2D : OptionButton
@export var resolution_btn_3D : OptionButton
@export var resolution_btn_2D : OptionButton
@export var format_btn : OptionButton
@export var interp_label : Label
@export var interp_btn : OptionButton
@export var normals_btn : OptionButton
@export var export_mesh_btn : OptionButton
@export var mesh_format_btn : OptionButton
@export var filename_line_edit : LineEdit
@export var filename_labels_container : VBoxContainer
@export var mesh_label : Label
@export var button_container : HBoxContainer
@export var progress_bar : ProgressBar

var renderer : Renderer
var compute_shader : ComputeShader
var exporter : Exporter

var output_resolution_3D : int:
	set(value):
		output_resolution_3D = value
		if compute_shader.is_3D_material:
			_set_interpolate_ui(output_resolution_3D)

var output_resolution_2D : int:
	set(value):
		output_resolution_2D = value
		if not compute_shader.is_3D_material:
			_set_interpolate_ui(output_resolution_2D)
		

var output_template_3D : int
var output_template_2D : int
var output_filetype : int
var output_directory : String:
	set(directory):
		output_directory = directory
		directory_btn.text = directory

var interpolation_type : int
var normals_type : int
var export_mesh : int
var mesh_format : int
var filetype_string : String
var mesh_format_string : String
var material_name : String

var export_template_data : Array[Array] = []
var filename_maps : Array[String] = []
var filename_labels : Array[Node] = []

@onready var mesh_settings_instance : MeshSettings = $/root/ProcTile/UI/RendererToolbar/RightRendererToolbar/MeshSettingsButton/MeshSettings

const RESOLUTIONS_3D : Array[int] = [512, 1024, 2048, 4096]
const RESOLUTIONS_2D : Array[int] = [32, 64, 128, 256, 512]
const FILE_TYPES_STRINGS : Array[String] = [".png", ".jpg"]
const MESH_FORMATS_STRINGS : Array[String] = [".obj"]


func _ready() -> void:
	_init_dependancies()
	_load_export_settings()
	_setup_export_ui()
	_set_radio_buttons()


# called from Exporter instance to update progress bar 
# hands off control back here at 100% and nodes are cleaned up
func progress_update(progress : int) -> void:
	progress_bar.set_value_no_signal(progress)
	if progress >= 100:
		# Stupid but feels better to have the progress reach 100 before closing
		await get_tree().create_timer(0.5).timeout
		button_container.show()
		progress_bar.hide()
		progress_bar.set_value_no_signal(0.0)
		exporter = null
		
		# if exporting Directx normals, change back to OpenGL so the shader renders correctly.
		if normals_type != 0.0: 
			compute_shader.push_constant.set(
				compute_shader.push_constant.size() - (3 + compute_shader.push_constant_padding), 0.0
				)
			compute_shader.stage = 0
		
		renderer.set_process(true)


func _init_dependancies() -> void:
	renderer = $/root/ProcTile/Renderer as Renderer
	compute_shader = renderer.compute_shader


func _set_radio_buttons() -> void:
	var template_menu : PopupMenu = template_options_3D.get_popup()
	for i : int in template_menu.get_item_count():
		template_menu.set_item_as_radio_checkable(i, false)


func _load_export_settings() -> void:
	var settings_data : Dictionary = DataManager.settings_data[1]
	output_directory = settings_data.get("export_directory", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	output_template_3D = settings_data.export_template_3D
	output_template_2D = settings_data.export_template_2D
	output_resolution_3D = settings_data.export_resolution_3D
	output_resolution_2D = settings_data.export_resolution_2D
	output_filetype = settings_data.export_format
	filetype_string = FILE_TYPES_STRINGS[output_filetype]
	interpolation_type = settings_data.export_interpolation
	normals_type = settings_data.export_normals
	export_mesh = settings_data.export_mesh
	mesh_format = settings_data.mesh_format
	mesh_format_string = MESH_FORMATS_STRINGS[mesh_format]


func _setup_export_ui() -> void:
	file_dialog.set_current_dir(output_directory)
	
	# get template data
	var template : int = output_template_3D if compute_shader.is_3D_material else output_template_2D
	export_template_data = ExportTemplate.get_export_template_data(template)
	for dataline : Array in export_template_data:
		filename_maps.append(dataline[2])

	# set filename labels
	filename_labels = filename_labels_container.get_children()
	filename_labels.pop_back() # pop mesh label
	for i : int in filename_labels.size():
		if i >= filename_maps.size():
			(filename_labels[i] as Label).hide()
	if export_mesh == 0:
		mesh_label.hide()

	# update ui from settings
	if compute_shader.is_3D_material:
		resolution_btn_3D.show()
		resolution_btn_3D.select(resolution_btn_3D.get_item_index(output_resolution_3D / 512.0 as int))
		template_options_3D.show()
		template_options_3D.select(output_template_3D)
	else:
		resolution_btn_2D.show()
		resolution_btn_2D.select(resolution_btn_2D.get_item_index(output_resolution_2D / 32.0 as int))
		template_options_2D.show()
		template_options_2D.select(template_options_2D.get_item_index(output_template_2D))
	
	format_btn.select(output_filetype)
	interp_btn.select(interpolation_type)
	normals_btn.select(normals_type)
	export_mesh_btn.select(export_mesh)
	mesh_format_btn.select(mesh_format)
	filename_line_edit.text = renderer.asset_name
	_on_line_edit_text_changed(renderer.asset_name)


func _set_filename_labels_text() -> void:
	for i : int in filename_labels.size():
		if i < filename_maps.size():
			(filename_labels[i] as Label).set_text(material_name + filename_maps[i] + filetype_string)


func _set_meshname_label_text() -> void:
	mesh_label.set_text(material_name + "_mesh" + mesh_format_string)


func _set_interpolate_ui(resolution : int) -> void:
	var is_interpolation_enabled : bool = resolution != renderer.texture_size
	interp_label.self_modulate = Color(Color.WHITE if is_interpolation_enabled else Color.GRAY)
	interp_btn.disabled = not is_interpolation_enabled


func _on_directory_btn_pressed() -> void:
	file_dialog.show()


func _on_file_dialog_close_requested() -> void:
	file_dialog.hide()


func _on_template_btn_3d_item_selected(template_index: int) -> void:
	output_template_3D = template_index
	_set_template_data(template_index)


func _on_template_btn_2d_item_selected(template_index: int) -> void:
	template_index = template_options_2D.get_item_id(template_index)
	output_template_2D = template_index
	_set_template_data(template_index)


func _set_template_data(template_index: int) -> void:
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


func _on_resolution_btn_3d_item_selected(index: int) -> void:
	output_resolution_3D = RESOLUTIONS_3D[index]


func _on_resolution_btn_2d_item_selected(index: int) -> void:
	output_resolution_2D = RESOLUTIONS_2D[index]


func _on_interpolation_btn_item_selected(index: int) -> void:
	interpolation_type = index


func _on_normals_button_item_selected(index: int) -> void:
	normals_type = index


func _on_format_btn_item_selected(index: int) -> void:
	output_filetype = index
	filetype_string = FILE_TYPES_STRINGS[index]
	_set_filename_labels_text()


func _on_export_mesh_btn_item_selected(index: int) -> void:
	export_mesh = index

	if not export_mesh:
		mesh_label.hide()
		mesh_format_btn.disabled = true
		return
	
	mesh_label.show()
	mesh_format_btn.disabled = false


func _on_mesh_format_btn_item_selected(index: int) -> void:
	mesh_format = index
	mesh_format_string = MESH_FORMATS_STRINGS[index]
	_set_meshname_label_text()


func _on_line_edit_text_changed(new_text: String) -> void:
	material_name = new_text
	_set_filename_labels_text()
	_set_meshname_label_text()


func _on_close_requested() -> void:
	if exporter:
		exporter = null
	queue_free()


func _on_save_btn_pressed() -> void:
	DataManager.save_export_settings(
			output_directory, 
			output_template_3D,
			output_template_2D,
			output_resolution_3D,
			output_resolution_2D,
			output_filetype, 
			interpolation_type, 
			normals_type, 
			export_mesh, 
			mesh_format,
	)


func _on_export_button_pressed() -> void:
	button_container.hide()
	progress_bar.show()
	
	if normals_type != 0.0: # Block execution until normals are recalculated
		if !normals_recalculated.connect(_init_export, ConnectFlags.CONNECT_ONE_SHOT):
			_recalculate_normals()
	else:
		_init_export()


func _recalculate_normals() -> void:
	compute_shader.push_constant.set(
		compute_shader.push_constant.size() - (3 + compute_shader.push_constant_padding), normals_type
		)
	compute_shader.stage = 0
	
	while compute_shader.stage != compute_shader._max_stage:
		await get_tree().process_frame
	
	normals_recalculated.emit()


func _init_export() -> void:
	renderer.set_process(false)
	
	var res : int = output_resolution_3D if compute_shader.is_3D_material else output_resolution_2D
	
	exporter = Exporter.new()
	exporter.setup_properties(
			compute_shader, 
			self, 
			material_name, 
			res,
			renderer.texture_size, 
			interpolation_type, 
			export_mesh,
			mesh_format,
			mesh_settings_instance,
	)
	
	exporter.export(export_template_data, output_filetype, output_directory)
