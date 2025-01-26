class_name ActionsManager
extends RefCounted

enum ActionType {
	SECTION,
	SLIDER,
	DROPDOWN,
	GRADIENT_COL,
	GRADIENT_CONTROL,
	UNIFORM_COL,
	SEED_SINGLE,
	SEEDS_MULTIPLE,
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
			else:
				var visibility : bool = action[3]
				uniform_col_instance.colour_picker.visible = visibility
				_add_redo_action([ActionType.UNIFORM_COL, uniform_col_instance, colour_changed, !visibility])

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
