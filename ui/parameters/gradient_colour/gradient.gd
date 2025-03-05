class_name ParamGradient
extends VBoxContainer
## Gradient class for a compute shader parameter
##
## Initialises colour data from the database, creates interactable ui elements,
## and handles updates to the shader and buffers.

@export_category("Child Nodes")
@export var label : Label
@export var hide_btn : TextureButton
@export var colour_preview : ColorRect
@export var gradient_texture_rect: TextureRect
@export var gradient_controls_container : Control
@export_category("Packed Scenes")
@export var _gradient_control_scene : PackedScene
@export var _colour_picker_scene : PackedScene

const PADDING : int = 8 # padding to prevent controls from overlapping

var compute_shader : ComputeShader
var buffer_indexes : Array[int] # offset idx, colour idx
var buffer_sets : Array[int] # offset set, colour set
var dependant_stage : int
var colour_picker : ParamColourPicker
var selected_control : ParamGradientControl
var selected_index : int = -1
var controls_created : bool = false
var gradient_expanded : bool = false
var preview_colour : Color:
	set(col):
		preview_colour = col
		colour_preview.color = col
		if colour_picker:
			colour_picker.set_colour(col)
var colour_data : Array[Color] = []
var undo_redo_colour : Color
var control_nodes : Array[ParamGradientControl]

var _position_data : PackedFloat32Array
var _gradient : Gradient = Gradient.new()
var _gradient_texture : GradientTexture2D

@onready var container_width : float = (
		$/root/ProcTile/UI/ParamsWindow/MarginContainer/ScrollContainer/MarginContainer/ParamsContainer 
		as ParamSection).size.x


func setup_properties(data : Array) -> void:
	label.text = str(data[1])
	_position_data = data[2][0]
	dependant_stage = data[4]
	buffer_indexes = [data[5], data[6]]
	buffer_sets = [data[7], data[8]]

	# Colour data is not stored in a usable format in the CFG and must be converted
	var raw_colour_data : Array = data[3]
	colour_data = _convert_to_colours(raw_colour_data)
	
	_setup_gradient()


# Alternative to setup_properties, for loading save data
func load_properties(save_data : Array) -> void:
	_position_data = save_data[0]
	colour_data = save_data[1]
	
	_setup_gradient()
	
	compute_shader.rebuild_storage_buffer(buffer_indexes[0], buffer_sets[0], _position_data.to_byte_array())
	compute_shader.rebuild_storage_buffer(buffer_indexes[1], buffer_sets[1], PackedColorArray(colour_data).to_byte_array())


func get_gradient_data() -> Array[Array]:
	return [_position_data, colour_data]


func show_gradient_texture() -> void:
	_gradient_texture.height = 40
	hide_btn.show()
	
	if controls_created:
		for control : ParamGradientControl in control_nodes:
			control.show()
	else:
		_create_controls()
		
	gradient_expanded = true


func hide_gradient_texture() -> void:
	_gradient_texture.height = 20
	hide_btn.hide()
	colour_preview.hide()
	
	for control : ParamGradientControl in control_nodes:
		control.hide()
	
	if selected_control:
		selected_control.set_deselected()
		selected_control = null
		
		if colour_picker:
			colour_picker.hide()
	
	gradient_expanded = false


func change_colour(col : Color) -> void:
	colour_preview.color = col
	selected_control.set_colour_indicator(col)
	colour_data[selected_index] = col
	
	_gradient.set_colors(colour_data)
	
	# Update shader storage buffer for colours
	compute_shader.update_storage_buffer(buffer_indexes[1], PackedColorArray(colour_data).to_byte_array())
	compute_shader.stage = dependant_stage


@warning_ignore_start("return_value_discarded")
func create_control(px_position : float, create_with_col : bool = false, col : Color = Color(0.0, 0.0, 0.0)) -> void:
	var new_control : ParamGradientControl = _gradient_control_scene.instantiate() as ParamGradientControl
	var normalised_position : float = px_position / container_width

	# Check the clicked position against current control indexes to find where it should be indexed
	var index : int
	for i : int in _position_data.size():
		if normalised_position < _position_data[i]:
			index = i
			break
	
	var sampled_col : Color
	if create_with_col:
		sampled_col = col
	else:
		# Sample the gradient at the click location to get the interpolated colour for the new node.
		sampled_col = _gradient.sample(normalised_position)
	
	# Insert the new data into the storage arrays
	_gradient.add_point(normalised_position, sampled_col)
	colour_data.insert(index, sampled_col)
	_position_data.insert(index, normalised_position)
	control_nodes.insert(index, new_control)
	
	_recalculate_control_indexes()
	
	# Create bounds for the new node, and update the existing bounds for the nodes before and after.
	new_control.bounds = [
		(_position_data[index - 1] * container_width) + PADDING, 
		(_position_data[index + 1] * container_width) - PADDING
		]
	control_nodes[index - 1].bounds[1] = px_position - PADDING
	control_nodes[index + 1].bounds[0] = px_position + PADDING
	
	# Set the control node variables
	new_control.set_colour_indicator(sampled_col)
	new_control.position += Vector2(px_position, 0)
	new_control.gradient_controls_container = gradient_controls_container
	_connect_control_signals(new_control)
	
	gradient_controls_container.add_child(new_control)
	
	# rebuild buffers
	compute_shader.rebuild_storage_buffer(buffer_indexes[0], buffer_sets[0], _position_data.to_byte_array())
	compute_shader.rebuild_storage_buffer(buffer_indexes[1], buffer_sets[1], PackedColorArray(colour_data).to_byte_array())
	compute_shader.stage = dependant_stage


func delete_control(index : int, node_to_delete : ParamGradientControl) -> void:
	# recalculate bounds +1 and -1
	if index == 0:
		control_nodes[1].bounds[0] = 0.0
	elif index == control_nodes.size() - 1:
		control_nodes[index - 1].bounds[1] = container_width
	else:
		var bound_1 : float = (_position_data[index - 1] * container_width) + PADDING
		var bound_2 : float = (_position_data[index + 1] * container_width) - PADDING
		control_nodes[index + 1].bounds[0] = bound_1
		control_nodes[index - 1].bounds[1] = bound_2
		
	# Delete node from GradientControl array, and data from colour and pos
	control_nodes.remove_at(index)
	colour_data.remove_at(index)
	_position_data.remove_at(index)

	if node_to_delete == selected_control:
		selected_control = null
		colour_preview.hide()
		if colour_picker:
			colour_picker.hide()
	node_to_delete.queue_free()
	
	_recalculate_control_indexes()
	
	# recalculate gradient texture
	_gradient.set_offsets(_position_data)
	_gradient.set_colors(colour_data)
	
	# rebuild buffers
	compute_shader.rebuild_storage_buffer(buffer_indexes[0], buffer_sets[0], _position_data.to_byte_array())
	compute_shader.rebuild_storage_buffer(buffer_indexes[1], buffer_sets[1], PackedColorArray(colour_data).to_byte_array())
	compute_shader.stage = dependant_stage


func select_control(index : int, new_selected_node : ParamGradientControl) -> void:
	if selected_control:
		selected_control.set_deselected()
	else: # if no control is selected, the preview will also be hidden
		colour_preview.show()
	
	selected_control = new_selected_node
	selected_index = index
	preview_colour = colour_data[index]
	undo_redo_colour = preview_colour


#region UI input handling
func _on_controls_container_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	elif (event as InputEventMouseButton).button_index == 1 and event.is_pressed():
		if gradient_expanded:
			var mouse_pos_x : float = (get_global_mouse_position() - gradient_controls_container.global_position).x
			create_control(mouse_pos_x)
			#var created_control_index : int = 
			ActionsManager.new_undo_action = [3, self, 6, (gradient_controls_container.get_child(-1) as ParamGradientControl).index, mouse_pos_x]
		else:
			show_gradient_texture()
			ActionsManager.new_undo_action = [3, self, 0]


func _on_colour_preview_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton: # Early return for non-click
		return
	elif (event as InputEventMouseButton).button_index == 1 and event.is_pressed():
		if colour_picker:
			if colour_picker.visible:
				colour_picker.hide()
			else:
				colour_picker.show()
		else:
			_create_colour_picker()
			
		ActionsManager.new_undo_action = [3, self, 3, colour_picker.visible]


func _on_gui_input(_event: InputEvent) -> void:
	if not colour_picker or not colour_picker.visible or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	else:
		if undo_redo_colour != colour_data[selected_index]:
			ActionsManager.new_undo_action = [3, self, 4, undo_redo_colour]
			undo_redo_colour = colour_preview.color


func _on_hide_button_pressed() -> void:
	hide_gradient_texture()
	ActionsManager.new_undo_action = [3, self, 1]
#endregion


#region GradientControl creation, deletion and selection
func _create_controls() -> void:
	# Positions scaled from a normalised 0-1 value to pixel positions.
	var px_positions : Array[float] = []
	for x : int in _position_data.size():
		px_positions.append(round(_position_data[x] * container_width))
	
	for i : int in _position_data.size():
		var gradient_control : ParamGradientControl = _gradient_control_scene.instantiate() as ParamGradientControl
		
		gradient_control.set_colour_indicator(colour_data[i])
		gradient_control.position += Vector2(px_positions[i], 0)
		gradient_control.index = i
		gradient_control.gradient_controls_container = gradient_controls_container
		_connect_control_signals(gradient_control)
		
		if i == 0: # first control lower bound is always 0.0
			gradient_control.bounds = [0.0, px_positions[1] - PADDING]
		elif i == _position_data.size() - 1: # last control upper bound always max container width
			gradient_control.bounds = [px_positions[i - 1] + PADDING, container_width]
		else:
			gradient_control.bounds = [px_positions[i - 1] + PADDING, px_positions[i + 1] - PADDING]
		
		gradient_controls_container.add_child(gradient_control)
		control_nodes.append(gradient_control)

	controls_created = true


func _on_control_deleted(index : int, node_to_delete : ParamGradientControl) -> void:
	if control_nodes.size() <= 2:
		return
	ActionsManager.new_undo_action = [
			3, self, 5, index, node_to_delete.undo_redo_pos, colour_data[index], node_to_delete.is_selected
	]
	delete_control(index, node_to_delete)


func _on_control_selected(index : int, new_selected_node : ParamGradientControl) -> void:
	ActionsManager.new_undo_action = [3, self, 2, selected_index, index, selected_control]
	select_control(index, new_selected_node)
#endregion


#region Functions to handle parameter changes and signal callbacks
func _on_colour_picked(col : Color) -> void:
	change_colour(col)


func _on_bounds_changed(index : int) -> void:
	var lower_control : ParamGradientControl
	var upper_control : ParamGradientControl
	
	if index != 0:
		lower_control = control_nodes[index - 1]
		lower_control.bounds[1] = (_position_data[index] * container_width) - PADDING
	if index + 1 != control_nodes.size():
		upper_control = control_nodes[index + 1]
		upper_control.bounds[0] = (_position_data[index] * container_width) + PADDING


func _on_offset_changed(index : int, pos : float) -> void:
	_position_data[index] = pos / container_width
	_gradient.set_offsets(_position_data)

	# Update shader storage buffer for offsets
	compute_shader.update_storage_buffer(buffer_indexes[0], _position_data.to_byte_array())
	compute_shader.stage = dependant_stage
#endregion


#region util / helper functions
func _create_colour_picker() -> void:
	colour_picker = _colour_picker_scene.instantiate() as ParamColourPicker
	colour_picker.set_colour(preview_colour)
	colour_picker.col_picked.connect(_on_colour_picked)
	colour_preview.add_sibling(colour_picker) # add node between preview & spacer
	_unblock_hue_slider_filter()

# By default, the native ColorPicker node's inbuilt hue slider has its mouse filter set to block
func _unblock_hue_slider_filter() -> void:
	var node : Control = colour_picker
	for i : int in range(4):
		node = node.get_child(0, true)
	(node.get_child(2, true) as Control).mouse_filter = MOUSE_FILTER_PASS


func _connect_control_signals(control : ParamGradientControl) -> void:
	control.selected.connect(_on_control_selected.bind(control))
	control.deleted.connect(_on_control_deleted.bind(control))
	control.offset_changed.connect(_on_offset_changed)
	control.bounds_changed.connect(_on_bounds_changed)


func _setup_gradient() -> void:
	# Prevent multiple instances from sharing texture
	var gradient_texture : GradientTexture2D = GradientTexture2D.new()
	gradient_texture.set_width(250)
	gradient_texture.set_height(20)
	gradient_texture_rect.set_texture(gradient_texture)
	
	_gradient.set_offsets(_position_data)
	_gradient.set_colors(colour_data)
	_gradient_texture = gradient_texture_rect.texture
	_gradient_texture.gradient = _gradient


# Called when a control node is created or freed and their indexes are no longer valid.
func _recalculate_control_indexes() -> void:
	for i : int in control_nodes.size():
		control_nodes[i].index = i
	if selected_control:
		selected_index = selected_control.index


func _convert_to_colours(raw_colour_data : Array) -> Array:
	for rgb : Array in raw_colour_data:
		@warning_ignore("unsafe_call_argument")
		var colour : Color = Color(rgb[0], rgb[1], rgb[2])
		colour_data.append(colour)
	return colour_data
#endregion

@warning_ignore_restore("return_value_discarded")
