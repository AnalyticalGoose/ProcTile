extends Node

enum DatabaseType {
	SETTINGS,
	MATERIAL,
	MESH,
}

var material_data : Array[Dictionary]
var settings_data : Array[Dictionary]
var shader_paths : Dictionary = {}

const SETTINGS_PATH : String = "user://settings.cfg"


func _ready() -> void:
	_load_settings()
	
	var material_database : Database = Database.new()
	_init_schema(DatabaseType.MATERIAL, material_database)
	
	var material_dir : DirAccess = DirAccess.open("res://materials/3d_realistic/")
	var dir_array : PackedStringArray = material_dir.get_directories()
	
	for i : int in dir_array.size():
		var dir : String = dir_array[i]
		var base_path : String = "res://materials/3d_realistic/" + dir + "/" + dir
		material_database.load_from_path(base_path + "_data.cfg")
		shader_paths[i] = [
				base_path + "_compute.glsl",
				base_path + "_data.cfg"
		]

	material_data = material_database.get_array()


func save_export_settings(
		dir : String, template : int, res : int, format : int, interp : int, 
		normals : int, mesh_export : int, mesh : int
	) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	
	if cfg_file.load(SETTINGS_PATH):
		Logger.puts_error("Cannot find user settings at" + SETTINGS_PATH)
	
	cfg_file.set_value("export_settings", "export_directory", dir)
	cfg_file.set_value("export_settings", "export_template", template)
	cfg_file.set_value("export_settings", "export_resolution", res)
	cfg_file.set_value("export_settings", "export_format", format)
	cfg_file.set_value("export_settings", "export_interpolation", interp)
	cfg_file.set_value("export_settings", "export_normals", normals)
	cfg_file.set_value("export_settings", "export_mesh", mesh_export)
	cfg_file.set_value("export_settings", "mesh_format", mesh)
	
	if cfg_file.save(SETTINGS_PATH):
		Logger.puts_error("Cannot save user settings to " + SETTINGS_PATH)
	
	_load_settings() # refresh settings data


func save_mesh_settings(mesh : int, remove_back : bool, remove_bottom : bool, shrink_back : bool, shrink_sides : bool) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	
	if cfg_file.load(SETTINGS_PATH):
		Logger.puts_error("Cannot find user settings at" + SETTINGS_PATH)

	cfg_file.set_value("mesh_settings", "mesh_type", mesh)
	cfg_file.set_value("mesh_settings", "remove_back_face", remove_back)
	cfg_file.set_value("mesh_settings", "remove_bottom_face", remove_bottom)
	cfg_file.set_value("mesh_settings", "shrink_back_UVs", shrink_back)
	cfg_file.set_value("mesh_settings", "shrink_sides_UVs", shrink_sides)
	
	if cfg_file.save(SETTINGS_PATH):
		Logger.puts_error("Cannot save mesh settings to " + SETTINGS_PATH)
	
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
			database.add_valid_property("export_normals")
			database.add_valid_property("export_mesh")
			database.add_valid_property("mesh_format")
		
		DatabaseType.MATERIAL:
			database.add_mandatory_property("ui_elements", TYPE_ARRAY)
			database.add_mandatory_property("shader_data", TYPE_ARRAY)
			
		DatabaseType.MESH:
			database.add_valid_property("mesh_type")
			database.add_valid_property("remove_back_face")
			database.add_valid_property("remove_bottom_face")
			database.add_valid_property("shrink_back_UVs")
			database.add_valid_property("shrink_sides_UVs")


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		var cfg_file : ConfigFile = ConfigFile.new()
		
		cfg_file.set_value("shader_settings", "shader_resolution", 4096)
		cfg_file.set_value("export_settings", "export_template", 1)
		cfg_file.set_value("export_settings", "export_resolution", 1024)
		cfg_file.set_value("export_settings", "export_format", 0)
		cfg_file.set_value("export_settings", "export_interpolation", 4)
		cfg_file.set_value("export_settings", "export_normals", 0)
		cfg_file.set_value("export_settings", "export_mesh", 1)
		cfg_file.set_value("export_settings", "mesh_format", 0)

		if cfg_file.save(SETTINGS_PATH):
			Logger.call_deferred("puts_error", "Cannot save user settings to " + SETTINGS_PATH)
	
	var settings_database : Database = Database.new()
	_init_schema(DatabaseType.SETTINGS, settings_database)
	_init_schema(DatabaseType.MESH, settings_database)
	settings_database.load_from_path(SETTINGS_PATH)
	settings_data = settings_database.get_array()
