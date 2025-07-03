extends TextureRect

@export var gizmo_viewport: SubViewport

func _on_gui_input(event: InputEvent) -> void:
	gizmo_viewport.notification(NOTIFICATION_VP_MOUSE_ENTER)
	gizmo_viewport.push_input(event)
