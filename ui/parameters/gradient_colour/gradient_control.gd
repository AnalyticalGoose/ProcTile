class_name ParamGradientControl
extends Control
## Gradient Control class for the gradient shader parameter
##
## Handles its colour, UI drag and drop user interaction, 
## and signals up to the parent gradient.

signal selected(index : int, node : ParamGradientControl)
signal deleted(index : int, node: ParamGradientControl)
signal offset_changed(index : int, pos : float)
signal bounds_changed(index : int)

@export var colour_indicator : Panel
@export var border : ColorRect
@export var position_indicator : ColorRect

var index : int
var gradient_controls_container : Control
var is_selected : bool = false
var is_dragging : bool = false
var bounds : Array[float]
var last_pos : float
var undo_redo_pos : float


func _ready() -> void:
	set_process(false)
	undo_redo_pos = position.x


# Kinda cracked, but gives much nicer sliding behaviour than my implemenation with 
# the in-built drag and drop, as the expense of running in _process.
# Likely worth a revisit in the future to 'do properly'.
func _process(_delta: float) -> void:
	position.x = clamp((get_global_mouse_position() - gradient_controls_container.global_position).x, bounds[0], bounds[1])
	
	if position.x != last_pos:
		last_pos = position.x
		offset_changed.emit(index, position.x)
	
	# Reliably ends the drag, regardless of where the user has taken the mouse.
	# Other methods started to break when the mouse left the window or entered other
	# control nodes.
	if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		is_dragging = false
		set_process(false)
		# bounds only need to be recalculated at the last position after the node has been dragged.
		bounds_changed.emit(index)
		
		var gradient_col_instance : ParamGradient = gradient_controls_container.get_parent().get_parent()
		ActionsManager.new_undo_action = [4, gradient_col_instance, index, undo_redo_pos, position.x]
		undo_redo_pos = last_pos


func set_pos(pos : float) -> void:
	position.x = pos
	last_pos = position.x
	offset_changed.emit(index, position.x)
	bounds_changed.emit(index)


func set_selected(emit_selected_signal : bool = true) -> void:
	border.color = Color.LIGHT_GRAY
	position_indicator.color = Color.LIGHT_GRAY
	
	if emit_selected_signal: # Signal not wanted for undo / redo operations
		selected.emit(index)
	
	is_selected = true


func set_deselected() -> void:
	border.color = Color(0.25, 0.25, 0.25)
	position_indicator.color = Color(0.25, 0.25, 0.25)
	is_selected = false


func set_colour_indicator(col : Color) -> void:
	colour_indicator.modulate = col


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	elif (event as InputEventMouseButton).button_index == 1:
		if event.is_pressed():
			if not is_selected:
				set_selected()
			grab_click_focus()
	elif (event as InputEventMouseButton).button_index == 2:
		if event.is_released():
			deleted.emit(index)


# Reliable way to trigger drag over using the in-built virtual _input methods.
func _get_drag_data(_at_position: Vector2) -> Variant:
	is_dragging = true
	set_process(true)
	return null
