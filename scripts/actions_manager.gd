class_name ActionsManager
extends RefCounted

enum ActionType {
	SECTION,
	SLIDER,
	DROPDOWN,
	GRADIENT_COL,
	GRADIENT_CONTROL,
	UNIFORM_COL,
	SEED,
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
			pass
		
		ActionType.GRADIENT_CONTROL:
			pass
		
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
				3:
					var seed_value : float = action[3]
					var index : int = action[4]
					var shader_index : int = action[5]
					_add_redo_action(
							[ActionType.SEED, seeds_instance, 3, seeds_instance.seed_values[index],
							index, shader_index]
					)
					seeds_instance.set_seed_value(seed_value, index, shader_index)


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
			pass
		
		ActionType.GRADIENT_CONTROL:
			pass
		
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
