class_name ParamSeedLine
extends HBoxContainer
## Single Seed class for a compute shader parameter
## 
## Instanced as a child of ParamSeedMultiple for shader parameters and signals
## back when the 'randomise' button is pressed

signal randomised(index : int, seed_array_index : int)

@export var seed_value : LineEdit


func _on_randomise_button_pressed() -> void:
	randomised.emit()
