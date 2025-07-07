class_name LightingSettings
extends PanelContainer

## Lighting settings class for the Renderer
##
## Initialises user settings from the database, or falls back to a default if not set.
## Handles changing / loading / saving HDRI & tonemap. 

signal close_menu(idx: int)

@export var hdri: Array[CompressedTexture2D]
@export_group("UI Elements")
@export var hdri_options: OptionButton
@export var hdri_background_btn: CheckBox
@export var tonemap_options: OptionButton
@export var close_btn: Button

var hdri_index: int = 2
var hdri_visible: bool = false
var tonemap_index: int = 0

@onready var environment_instance : WorldEnvironment = $/root/ProcTile/Renderer/Environment/WorldEnvironment as WorldEnvironment


func _ready() -> void:
	_load_lighting_settings()
	_setup_lighting()
	_setup_settings_ui()


func _load_lighting_settings() -> void:
	if not DataManager.settings_data[3].name == "lighting_settings":
		return
		
	var lighting_data : Dictionary = DataManager.settings_data[3]
	hdri_index = lighting_data.hdri
	hdri_visible = lighting_data.hdri_visible
	tonemap_index = lighting_data.tonemap


func _setup_lighting() -> void:
	_set_hdri()
	_set_background(Environment.BG_SKY if hdri_visible else Environment.BG_CLEAR_COLOR)
	_set_tonemap(tonemap_index as Environment.ToneMapper)


func _setup_settings_ui() -> void:
	hdri_options.select(hdri_index)
	hdri_background_btn.set_pressed_no_signal(hdri_visible)
	tonemap_options.select(tonemap_index)


func _on_hdri_option_button_item_selected(index: int) -> void:
	hdri_index = index
	_set_hdri()


func _set_hdri() -> void:
	(environment_instance.environment.sky.sky_material as PanoramaSkyMaterial).set_panorama(hdri[hdri_index])
	

func _on_hdri_background_button_toggled(toggled_on: bool) -> void:
	hdri_visible = toggled_on
	
	if toggled_on:
		_set_background(Environment.BG_SKY)
	else:
		_set_background(Environment.BG_CLEAR_COLOR)


func _set_background(bg: Environment.BGMode) -> void:
	environment_instance.environment.background_mode = bg


func _on_tonemap_option_button_item_selected(index: int) -> void:
	_set_tonemap(index as Environment.ToneMapper)


func _set_tonemap(tonemap: Environment.ToneMapper) -> void:
	tonemap_index = tonemap as int
	environment_instance.environment.tonemap_mode = tonemap


func _on_save_settings_btn_pressed() -> void:
	DataManager.save_lighting_settings(hdri_index, hdri_visible, tonemap_index)


func _on_close_btn_pressed() -> void:
	close_menu.emit(0)
	hide()
