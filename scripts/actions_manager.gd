class_name ActionsManager
extends RefCounted

## TODO - check if manually typing in values (seed, slider etc) triggers undo redo

enum ActionType {
	# Shader Params
	SECTION,
	SLIDER,
	DROPDOWN,
	GRADIENT_COL,
	GRADIENT_CONTROL,
	UNIFORM_COL,
	SEED,
	
	# Mesh Settings
	SCALE_UV,
	DELETE_FACE,
}

const MAX_ACTIONS : int = 20

static var undo_btn : Button
static var redo_btn : Button
static var _undo_actions : Array[Array] = []
static var _redo_actions : Array[Array] = []
static var new_undo_action : Array:
	set(action):
		_add_undo_action(action)
		_redo_actions.clear()
		redo_btn.disabled = true


static func undo_action() -> void:
	var action : Array = _undo_actions.pop_back()
	match action[0]:
		ActionType.SECTION:
			var section_instance : ParamSection = action[1]
			var visible : bool = action[2]
			_add_redo_action([ActionType.SECTION, section_instance, !visible])
			section_instance.set_section_visibility(visible)
			section_instance.show_hide_btn.set_pressed_no_signal(!visible)
			
		ActionType.SLIDER:
			var slider_instance : ParamSlider = action[1]
			_add_redo_action([ActionType.SLIDER, slider_instance, slider_instance.slider_val])
			var val : float = action[2]
			slider_instance.slider.set_value(val)
			slider_instance.slider_val = val
			
		ActionType.DROPDOWN:
			var dropdown_instance : ParamDropdown = action[1]
			_add_redo_action([ActionType.DROPDOWN, dropdown_instance, dropdown_instance.option_index])
			var option_index : int = action[2]
			dropdown_instance.set_dropdown_option(option_index)
			dropdown_instance.option_button.select(option_index)
		
		ActionType.GRADIENT_COL:
			var gradient_col_instance : ParamGradient = action[1]
			match action[2]:
				0: # Show gradient
					gradient_col_instance.hide_gradient_texture()
					_add_redo_action([3, gradient_col_instance, 0])
				
				1: # Hide gradient
					gradient_col_instance.show_gradient_texture()
					_add_redo_action([3, gradient_col_instance, 1])
				
				2: # Control selected
					var previous_index : int = action[3]
					var selected_index : int = action[4]
					var selected_control : ParamGradientControl = gradient_col_instance.control_nodes[selected_index]
					
					var previous_control : ParamGradientControl 
					if previous_index != -1: # default null / nothing selected
						previous_control = gradient_col_instance.control_nodes[previous_index]
					
					_add_redo_action(
							[3, gradient_col_instance, 2, previous_index, selected_index, previous_control]
					)
					
					selected_control.set_deselected()
					if previous_control:
						previous_control.set_selected(false)
					else:
						gradient_col_instance.colour_preview.hide()
					gradient_col_instance.selected_control = previous_control
					gradient_col_instance.selected_index = previous_index
					gradient_col_instance.preview_colour = gradient_col_instance.colour_data[previous_index]
				
				3: # Colour preview clicked
					var visibility : bool = action[3]
					gradient_col_instance.colour_picker.visible = !visibility
					_add_redo_action([ActionType.GRADIENT_COL, gradient_col_instance, 3, visibility])
					
				4: # Colour changed
					var col : Color = action[3]
					_add_redo_action(
						[ActionType.GRADIENT_COL, gradient_col_instance, 4, 
						gradient_col_instance.colour_preview.color]
					)
					gradient_col_instance.change_colour(col)
					gradient_col_instance.colour_picker.set_colour(col)
				
				5: # Control deleted
					var index : int = action[3]
					var new_control_pos : float = action[4]
					var col : Color = action[5]
					var selected : bool = action[6]
					
					gradient_col_instance.create_control(new_control_pos, true, col)
					
					if selected:
						gradient_col_instance.control_nodes[index].set_selected(false)
						gradient_col_instance.select_control(index, gradient_col_instance.control_nodes[index])
				
					_add_redo_action(
							[3, gradient_col_instance, 5, index, new_control_pos, col, selected]
					)
				
				6: # Control created
					#var control : ParamGradientControl = action[3]
					var control : ParamGradientControl = gradient_col_instance.control_nodes[action[3]]
					gradient_col_instance.delete_control(control.index, control)
					
					_add_redo_action([3, gradient_col_instance, 6, control, action[4]])
					
		ActionType.GRADIENT_CONTROL:
			var gradient_col_instance : ParamGradient = action[1]
			var gradient_control : ParamGradientControl = gradient_col_instance.control_nodes[action[2]]
			var last_pos : float = action[3]
			var new_pos : float = action[4]
			gradient_control.set_pos(last_pos)
			_add_redo_action([ActionType.GRADIENT_CONTROL, gradient_control, last_pos, new_pos])
		
		ActionType.UNIFORM_COL:
			var uniform_col_instance : ParamColour = action[1]
			var colour_changed : bool = action[2]
			
			if colour_changed:
				var col : Color = action[3]
				_add_redo_action(
					[ActionType.UNIFORM_COL, uniform_col_instance, colour_changed, 
					uniform_col_instance.colour_preview.color]
				)
				uniform_col_instance.change_colour(col)
				uniform_col_instance.colour_picker.set_colour(col)
				uniform_col_instance.undo_redo_colour = col
			
			else: # if colour hasn't been changed the action must be a visibility change
				var visibility : bool = action[3]
				uniform_col_instance.colour_picker.visible = visibility
				_add_redo_action([ActionType.UNIFORM_COL, uniform_col_instance, colour_changed, !visibility])
				
		ActionType.SEED:
			var seeds_instance : ParamSeeds = action[1]
			match action[2]:
				0: # Show all or edit button pressed (both use same signal)
					seeds_instance.hide_individual_seeds()
					_add_redo_action([ActionType.SEED, seeds_instance, 0])
				
				1: # Hide all button pressed
					seeds_instance.show_individual_seeds()
					_add_redo_action([ActionType.SEED, seeds_instance, 1])
				
				2: # Randomise or Randomise all button pressed
					_add_redo_action([ActionType.SEED, seeds_instance, 2, seeds_instance.seed_values.duplicate()])
					var seeds_values : Array = action[3]
					seeds_instance.set_seeds_values(seeds_values)
				
				3: # Randomise single seed value
					var seed_value : float = action[3]
					var index : int = action[4]
					var shader_index : int = action[5]
					_add_redo_action(
							[ActionType.SEED, seeds_instance, 3, seeds_instance.seed_values[index],
							index, shader_index]
					)
					seeds_instance.set_seed_value(seed_value, index, shader_index)
					
		ActionType.SCALE_UV:
			var mesh_settings : MeshSettings = action[1]
			var face : int = action[2]
			var toggled_on : bool = action[3]
			var checkbox : CheckBox = mesh_settings.back_uvs_checkbox if face == 0 else mesh_settings.sides_uvs_checkbox
			
			mesh_settings.scale_uvs(face, !toggled_on)
			mesh_settings.update_checkbox(checkbox, !toggled_on)
			_add_redo_action([ActionType.SCALE_UV, mesh_settings, face, toggled_on])

		ActionType.DELETE_FACE:
			var mesh_settings : MeshSettings = action[1]
			var face : int = action[2]
			var toggled_on : bool = action[3]
			var checkbox : CheckBox
			
			if face == 0:
				mesh_settings.cull_back_face = !toggled_on
				checkbox = mesh_settings.back_face_checkbox
			elif face == 1:
				mesh_settings.cull_bottom_face = !toggled_on
				checkbox = mesh_settings.bottom_face_checkbox
			
			mesh_settings.rebuild_mesh()
			mesh_settings.update_checkbox(checkbox, !toggled_on)
			_add_redo_action([ActionType.DELETE_FACE, mesh_settings, face, toggled_on])

	if _undo_actions.is_empty():
		undo_btn.disabled = true


static func redo_action() -> void:
	var action : Array = _redo_actions.pop_back()
	
	match action[0]:
		ActionType.SECTION:
			var section_instance : ParamSection = action[1]
			var visible : bool = action[2]
			_add_undo_action([ActionType.SECTION, section_instance, !visible])
			section_instance.set_section_visibility(visible)
			section_instance.show_hide_btn.set_pressed_no_signal(!visible)
		
		ActionType.SLIDER:
			var slider_instance : ParamSlider = action[1]
			var val : float = action[2]
			_add_undo_action([ActionType.SLIDER, slider_instance, slider_instance.slider_val])
			slider_instance.slider.set_value(val)
			slider_instance.slider_val = val
		
		ActionType.DROPDOWN:
			var dropdown_instance : ParamDropdown = action[1]
			_add_undo_action([ActionType.DROPDOWN, dropdown_instance, dropdown_instance.option_index])
			var option_index : int = action[2]
			dropdown_instance.set_dropdown_option(option_index)
			dropdown_instance.option_button.select(option_index)
			
		ActionType.GRADIENT_COL:
			var gradient_col_instance : ParamGradient = action[1]
			match action[2]:
				0:
					gradient_col_instance.show_gradient_texture()
					_add_undo_action([3, gradient_col_instance, 0])
				
				1:
					gradient_col_instance.hide_gradient_texture()
					_add_undo_action([3, gradient_col_instance, 1])
				
				2:
					var previous_index : int = action[3]
					var selected_index : int = action[4]
					var selected_control : ParamGradientControl = gradient_col_instance.control_nodes[selected_index]
					
					var previous_control : ParamGradientControl = action[5]
					if previous_control:
						previous_control = gradient_col_instance.control_nodes[previous_index]
					
					_add_undo_action(
							[3, gradient_col_instance, 2, previous_index, selected_index, previous_control]
					)
					
					selected_control.set_selected(false)
					if previous_control:
						previous_control.set_deselected()
					else: # if no control is selected, the preview will also be hidden
						gradient_col_instance.colour_preview.show()
					
					gradient_col_instance.selected_control = selected_control
					gradient_col_instance.selected_index = selected_index
					gradient_col_instance.preview_colour = gradient_col_instance.colour_data[selected_index]
					
				3: 
					var visibility : bool = action[3]
					gradient_col_instance.colour_picker.visible = visibility
					_add_undo_action([ActionType.GRADIENT_COL, gradient_col_instance, 3, visibility])
					
				4:
					var col : Color = action[3]
					_add_undo_action(
						[ActionType.GRADIENT_COL, gradient_col_instance, 4, 
						gradient_col_instance.colour_preview.color]
					)
					gradient_col_instance.change_colour(col)
					gradient_col_instance.colour_picker.set_colour(col)
				
				5:
					var index : int = action[3]
					var node : ParamGradientControl = gradient_col_instance.control_nodes[index]
					gradient_col_instance.delete_control(index, node)
					_add_undo_action(
							[3, gradient_col_instance, 5, index, action[4], action[5], action[6]]
					)
				
				6:
					var pos : float = action[4]
					gradient_col_instance.create_control(pos)
					var control : ParamGradientControl = gradient_col_instance.gradient_controls_container.get_child(-1)
					_add_undo_action([3, gradient_col_instance, 6, control, pos])
		
		ActionType.GRADIENT_CONTROL:
			var gradient_control : ParamGradientControl = action[1]
			var last_pos : float = action[2]
			var new_pos : float = action[3]
			gradient_control.set_pos(new_pos)
			_add_undo_action([ActionType.GRADIENT_CONTROL, gradient_control, last_pos, new_pos])
		
		ActionType.UNIFORM_COL:
			var uniform_col_instance : ParamColour = action[1]
			var colour_changed : bool = action[2]
			if colour_changed:
				var col : Color = action[3]
				_add_undo_action(
						[ActionType.UNIFORM_COL, uniform_col_instance, colour_changed, 
						uniform_col_instance.colour_preview.color]
				)
				uniform_col_instance.change_colour(col)
				uniform_col_instance.colour_picker.set_colour(col)
			else:
				var visibility : bool = action[3]
				uniform_col_instance.colour_picker.visible = visibility
				_add_undo_action([ActionType.UNIFORM_COL, uniform_col_instance, colour_changed, !visibility])
		
		ActionType.SEED:
			var seeds_instance : ParamSeeds = action[1]
			match action[2]:
				0:
					seeds_instance.show_individual_seeds()
					_add_undo_action([ActionType.SEED, seeds_instance, 0])
				
				1:
					seeds_instance.hide_individual_seeds()
					_add_undo_action([ActionType.SEED, seeds_instance, 1])
				
				2:
					_add_undo_action([ActionType.SEED, seeds_instance, 2, seeds_instance.seed_values.duplicate()])
					var seeds_values : Array = action[3]
					seeds_instance.set_seeds_values(seeds_values)
				
				3:
					var seed_value : float = action[3]
					var index : int = action[4]
					var shader_index : int = action[5]
					_add_undo_action(
							[ActionType.SEED, seeds_instance, 3, seeds_instance.seed_values[index],
							index, shader_index]
					)
					seeds_instance.set_seed_value(seed_value, index, shader_index)
					
		ActionType.SCALE_UV:
			var mesh_settings : MeshSettings = action[1]
			var face : int = action[2]
			var toggled_on : bool = action[3]
			var checkbox : CheckBox = mesh_settings.back_uvs_checkbox if face == 0 else mesh_settings.sides_uvs_checkbox
			
			mesh_settings.scale_uvs(face, toggled_on)
			mesh_settings.update_checkbox(checkbox, toggled_on)
			_add_undo_action([ActionType.SCALE_UV, mesh_settings, face, toggled_on])
			
		ActionType.DELETE_FACE:
			var mesh_settings : MeshSettings = action[1]
			var face : int = action[2]
			var toggled_on : bool = action[3]
			var checkbox : CheckBox
			
			if face == 0:
				mesh_settings.cull_back_face = toggled_on
				checkbox = mesh_settings.back_face_checkbox
			elif face == 1:
				mesh_settings.cull_bottom_face = toggled_on
				checkbox = mesh_settings.bottom_face_checkbox
			
			mesh_settings.rebuild_mesh()
			mesh_settings.update_checkbox(checkbox, toggled_on)
			_add_undo_action([ActionType.DELETE_FACE, mesh_settings, face, toggled_on])


	if _redo_actions.is_empty():
		redo_btn.disabled = true


static func _add_undo_action(action : Array) -> void:
	if _undo_actions.size() >= MAX_ACTIONS:
		_undo_actions = _undo_actions.slice(1)
	_undo_actions.append(action)
	if undo_btn.disabled:
		undo_btn.disabled = false


static func _add_redo_action(action : Array) -> void:
	_redo_actions.append(action)
	if redo_btn.disabled:
		redo_btn.disabled = false
