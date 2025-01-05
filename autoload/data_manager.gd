extends Node

var material_data : Array[Dictionary]

func _ready() -> void:
	var material_database : Database = Database.new()
	_init_schema(material_database)
	
	material_database.load_from_path("res://materials/brick_wall/brick_wall_data.cfg")
	material_database.load_from_path("res://materials/test_tile/test_tile_data.cfg")
	material_data = material_database.get_array()


func _init_schema(database : Database) -> void:
	database.add_mandatory_property("ui_elements", TYPE_ARRAY)
	database.add_mandatory_property("shader_data", TYPE_ARRAY)
