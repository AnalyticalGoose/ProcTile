extends Node

enum DatabaseType {
	SETTINGS,
	MATERIAL,
	MESH,
}

var material_data : Array[Dictionary]
var material_offets : Array[int] = [0]
var settings_data : Array[Dictionary]
var shader_paths : Dictionary = {}

var current_material_name : String
var current_material_id : int
var current_material_type : int = 0
var current_save_path : String = ""

const SETTINGS_PATH : String = "user://settings.cfg"
const MATERIAL_DIRS : Array[String] = ["res://materials/3D/realistic/", "res://materials/2D/pixel/"]

func _ready() -> void:
	_load_settings()
	
	var material_database : Database = Database.new()
	_init_schema(DatabaseType.MATERIAL, material_database)
	
	var i : int = 0
	
	for path : String in MATERIAL_DIRS:
		var material_dir : DirAccess = DirAccess.open(path)
		var dir_array : PackedStringArray = material_dir.get_directories()
		material_offets.append(dir_array.size())
		
		for dir : String in dir_array:
			var base_path : String = path + dir + "/" + dir
			material_database.load_from_path(base_path + "_data.cfg")
			shader_paths[i] = [
					base_path + "_compute.glsl",
					base_path + "_data.cfg"
			]
			i += 1

	material_data = material_database.get_array()


func get_material_index_from_id(material_id : int) -> int:
	for i : int in material_data.size():
		if material_data[i].id == material_id:
			return i
	return 0


func save_material(path : String, serialised_data : Array[Array]) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	
	cfg_file.set_value("compatibility", "material_id", current_material_id)
	cfg_file.set_value("compatibility", "material_type", current_material_type)
	cfg_file.set_value("compatibility", "version", ProjectSettings.get_setting("application/config/version"))
	cfg_file.set_value("material_settings", "data", serialised_data)
	
	if cfg_file.save(path):
		Logger.puts_error("Cannot save material to " + path)
	
	current_save_path = path
	Logger.show_snackbar_popup("Save successful!")


func load_material_settings(cfg_file : ConfigFile) -> Array[Array]:
	var material_settings : Array[Array] = cfg_file.get_value("material_settings", "data")
	return material_settings


func save_export_settings(
		dir : String, template_3D : int, template_2D : int, res_3D : int, res_2D : int, 
		format : int, interp : int, normals : int, mesh_export : int, mesh : int
	) -> void:
	var cfg_file : ConfigFile = ConfigFile.new()
	
	if cfg_file.load(SETTINGS_PATH):
		Logger.puts_error("Cannot find user settings at" + SETTINGS_PATH)
	
	cfg_file.set_value("export_settings", "export_directory", dir)
	cfg_file.set_value("export_settings", "export_template_3D", template_3D)
	cfg_file.set_value("export_settings", "export_template_2D", template_2D)
	cfg_file.set_value("export_settings", "export_resolution_3D", res_3D)
	cfg_file.set_value("export_settings", "export_resolution_2D", res_2D)
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
			database.add_valid_property("export_template_3D")
			database.add_valid_property("export_template_2D")
			database.add_valid_property("export_resolution_3D")
			database.add_valid_property("export_resolution_2D")
			database.add_valid_property("export_format")
			database.add_valid_property("export_interpolation")
			database.add_valid_property("export_normals")
			database.add_valid_property("export_mesh")
			database.add_valid_property("mesh_format")
		
		DatabaseType.MATERIAL:
			database.add_mandatory_property("meta", TYPE_ARRAY)
			database.add_mandatory_property("ui_elements", TYPE_ARRAY)
			database.add_mandatory_property("shader_data", TYPE_ARRAY)
			database.add_valid_property("presets", TYPE_ARRAY)
			
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
		cfg_file.set_value("export_settings", "export_template_3D", 1)
		cfg_file.set_value("export_settings", "export_template_2D", 2)
		cfg_file.set_value("export_settings", "export_resolution_3D", 1024)
		cfg_file.set_value("export_settings", "export_resolution_2D", 64)
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
