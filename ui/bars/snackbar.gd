class_name SnackbarPopup
extends PanelContainer

@export var label : Label


@warning_ignore("return_value_discarded")
func _on_tree_entered() -> void:
	await get_tree().create_timer(1).timeout
	var tween : Tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 0), 0.5)
	tween.tween_callback(self.queue_free)


func _on_texture_button_pressed() -> void:
	queue_free()
