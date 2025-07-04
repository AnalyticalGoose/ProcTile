extends TextureRect

@export var orientation_gizmo_viewport: SubViewport

func _on_gui_input(event: InputEvent) -> void:
	orientation_gizmo_viewport.notification(NOTIFICATION_VP_MOUSE_ENTER)
	orientation_gizmo_viewport.push_input(event)
