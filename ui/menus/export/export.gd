class_name ExportWindow
extends Window

enum Template {
	GLTF_PBR_PACKED,
	GLTF_PBR_SPLIT,
}

@export var file_dialog : FileDialog
@export var directory_btn : Button
@export var template_options : OptionButton
@export var button_container : HBoxContainer
@export var progress_bar : ProgressBar

var exporter : Exporter

var current_template : int = Template.GLTF_PBR_PACKED

var output_directory : String:
	set(directory):
		output_directory = directory
		directory_btn.set_text(directory)
		

func _ready() -> void:
	var template_menu : PopupMenu = template_options.get_popup()
	for i : int in template_menu.get_item_count():
		template_menu.set_item_as_radio_checkable(i, false)
		
	output_directory = "C:/Users/Harry/Desktop/Painter/ProcTileTest"


func _on_close_requested() -> void:
	if exporter:
		exporter = null
	queue_free()


func _on_directory_btn_pressed() -> void:
	file_dialog.show()


func _on_file_dialog_close_requested() -> void:
	file_dialog.hide()


func _on_template_button_item_selected(template_index: int) -> void:
	current_template = template_index
	match template_index:
		Template.GLTF_PBR_PACKED:
			print("glTF PBR Packed")
		Template.GLTF_PBR_SPLIT:
			print("glTF PBR Split")


func _on_file_dialog_dir_selected(dir: String) -> void:
	output_directory = dir


func _on_export_button_pressed() -> void:
	button_container.hide()
	progress_bar.show()
	
	exporter = Exporter.new()
	exporter.compute_shader = ($/root/ProcTile/Renderer as Renderer).compute_shader
	exporter.export_window = self
	exporter.export(output_directory)


func progress_update(progress : int) -> void:
	progress_bar.set_value_no_signal(progress)
	if progress >= 100:
		# Stupid but feels better to have the progress reach 100 before closing
		await get_tree().create_timer(0.5).timeout
		button_container.show()
		progress_bar.hide()
		exporter = null
