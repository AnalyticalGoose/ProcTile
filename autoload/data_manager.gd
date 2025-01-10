extends Node

enum DatabaseType {
	SETTINGS,
	MATERIAL,
}

var material_data : Array[Dictionary]
var settings_data : Array[Dictionary]
var settings_path : String = "user://settings.cfg"


func _ready() -> void:
	_load_settings()
	
	var material_database : Database = Database.new()
	_init_schema(DatabaseType.MATERIAL, material_database)
	
	material_database.load_from_path("res://materials/brick_wall/brick_wall_data.cfg")
	material_database.load_from_path("res://materials/test_tile/test_tile_data.cfg")
	material_data = material_database.get_array()


func save_export_settings(dir : String, template : int, res : int, format : int, interp : int) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	
	if cfg_file.load(settings_path):
		Logger.puts_error("Cannot find user settings at" + settings_path)
	
	cfg_file.set_value("export_settings", "export_directory", dir)
	cfg_file.set_value("export_settings", "export_template", template)
	cfg_file.set_value("export_settings", "export_resolution", res)
	cfg_file.set_value("export_settings", "export_format", format)
	cfg_file.set_value("export_settings", "export_interpolation", interp)
	
	if cfg_file.save(settings_path):
		Logger.puts_error("Cannot save user settings to " + settings_path)
	
	_load_settings() # refresh settings data


func _init_schema(database_type: DatabaseType, database : Database) -> void:
	match database_type:
		DatabaseType.SETTINGS:
			database.add_valid_property("shader_resolution")
			database.add_valid_property("export_directory")
			database.add_valid_property("export_template")
			database.add_valid_property("export_resolution")
			database.add_valid_property("export_format")
			database.add_valid_property("export_interpolation")
		
		DatabaseType.MATERIAL:
			database.add_mandatory_property("ui_elements", TYPE_ARRAY)
			database.add_mandatory_property("shader_data", TYPE_ARRAY)


func _load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		var cfg_file : ConfigFile = ConfigFile.new()
		
		cfg_file.set_value("shader_settings", "shader_resolution", 4096)
		cfg_file.set_value("export_settings", "export_template", 1)
		cfg_file.set_value("export_settings", "export_resolution", 1024)
		cfg_file.set_value("export_settings", "export_format", 0)
		cfg_file.set_value("export_settings", "export_interpolation", 4)
		
		if cfg_file.save(settings_path):
			Logger.call_deferred("puts_error", "Cannot save user settings to " + settings_path)
	
	var settings_database : Database = Database.new()
	_init_schema(DatabaseType.SETTINGS, settings_database)
	settings_database.load_from_path(settings_path)
	settings_data = settings_database.get_array()
