extends Node

## This could be a single function but is seperated just for ease of use.
## It is more user-friendly to just call the type of logging by function name.
## Prevents needing to remember args for colour, and if an Error is being pushed.

static var output_instance : Label
static var ui_manager_instance : UIManager

var current_colour : int = 0

@onready var snackbar_scene : PackedScene = load("res://ui/bars/snackbar.tscn")


func puts(output : String) -> void:
	if not output_instance:
		await get_tree().process_frame
	
	if current_colour != 0:
		_set_output_colour(0)
	output_instance.text = output


func puts_warning(output: String) -> void:
	if not output_instance:
		await get_tree().process_frame
	
	if current_colour != 1:
		_set_output_colour(1)
	output_instance.text = output


func puts_error(output: String, err : Variant = null) -> void:
	if not output_instance:
		await get_tree().process_frame
	
	if current_colour != 2:
		_set_output_colour(2)
	
	var error_message : String = output + ": " + str(err)
	output_instance.text = error_message
	push_error(error_message)


func puts_success(output: String) -> void:
	if not output_instance:
		await get_tree().process_frame
	
	if current_colour != 3:
		_set_output_colour(3)
	output_instance.text = output


func stop_renderer(output: String) -> void:
	var renderer : Renderer = $/root/ProcTile/Renderer as Renderer
	renderer.set_process(false)
	
	if current_colour != 2:
		_set_output_colour(2)
	output_instance.text = output


func show_snackbar_popup(text : String) -> void:
	var snackbar : SnackbarPopup = snackbar_scene.instantiate()
	snackbar.label.text = text
	ui_manager_instance.add_child(snackbar)


func _set_output_colour(colour_idx : int) -> void:
	match colour_idx:
		0: # White info
			output_instance.set_modulate(Color(1.0, 1.0, 1.0, 1.0))
		1: # Yellow warning
			output_instance.set_modulate(Color(1.0, 1.0, 0.0, 1.0))
		2: # Red error
			output_instance.set_modulate(Color(1.0, 0.0, 0.0, 1.0))
		3: # Green success
			output_instance.set_modulate(Color(0.0, 1.0, 0.0, 1.0))
			
	current_colour = colour_idx
