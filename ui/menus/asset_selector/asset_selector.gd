class_name AssetSelector
extends GridContainer

signal asset_selected(index : int, button : Button)

@export var asset_preview_scene : PackedScene
@export var preview_images : Array[CompressedTexture2D]

var asset_btns : Array[Node]
var hover_timer : Timer
var hover_index : int
var close_preview_timer : Timer
var asset_preview : AssetPreview
var preview_open : bool = false


func _ready() -> void:
	asset_btns = get_children()
	for i : int in asset_btns.size():
		var button : Button = asset_btns[i]
		@warning_ignore_start("return_value_discarded")
		button.pressed.connect(_on_asset_selected.bind(i, button))
		button.mouse_entered.connect(_on_mouse_entered.bind(i))
		button.mouse_exited.connect(_on_mouse_exited)
	
	hover_timer = Timer.new()
	hover_timer.wait_time = 1.0
	hover_timer.set_one_shot(true)
	hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(hover_timer)
	
	close_preview_timer = Timer.new()
	close_preview_timer.wait_time = 0.3
	close_preview_timer.set_one_shot(true)
	close_preview_timer.timeout.connect(_on_close_preview_timer_timeout)
	@warning_ignore_restore("return_value_discarded")
	add_child(close_preview_timer)
	
	asset_preview = asset_preview_scene.instantiate()


func _on_asset_selected(index : int, button : Button) -> void:
	asset_selected.emit(index, button)


func _on_mouse_entered(index : int) -> void:
	if preview_open:
		close_preview_timer.stop()
		asset_btns[hover_index].remove_child(asset_preview)
		asset_preview.set_properties(preview_images[index], (asset_btns[index] as Button).text)
		asset_btns[index].add_child(asset_preview)
	else:
		hover_timer.start()
	hover_index = index


func _on_mouse_exited() -> void:
	if preview_open:
		close_preview_timer.start()
	else:
		hover_timer.stop()


func _on_hover_timer_timeout() -> void:
	preview_open = true
	asset_preview.set_properties(preview_images[hover_index], (asset_btns[hover_index] as Button).text)
	asset_btns[hover_index].add_child(asset_preview)


func _on_close_preview_timer_timeout() -> void:
	preview_open = false
	asset_btns[hover_index].remove_child(asset_preview)
