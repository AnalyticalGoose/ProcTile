extends RefCounted
class_name Database

var id_name : String = "id"
var entry_name : String = "name"

var is_typed : bool
var is_strict : bool
var is_validated : bool


func add_valid_property(property: String, type: int = TYPE_MAX) -> void:
	assert(not __property_exists(property), "Property '%s' already exists." % property)
	__valid_properties.append([property, type])


func add_mandatory_property(property: String, type: int = TYPE_MAX) -> void:
	assert(not __property_exists(property), "Property '%s' already exists." % property)
	__mandatory_properties.append([property, type])
	__valid_properties.append([property, type])


@warning_ignore("untyped_declaration")
func add_default_property(property: String, default, typed: bool = true) -> void:
	add_valid_property(property, typeof(default) if typed else TYPE_MAX)
	__default_values[property] = default

 
func get_array() -> Array[Dictionary]:
	return __data


func get_dictionary(skip_unnamed: bool = false) -> Dictionary:
	if entry_name.is_empty():
		push_error("Can't create Dictionary if data is unnamed.")
		return {}

	if __data_dirty:
		__dict.clear()
		for entry: Dictionary in __data:
			var lookup_key: String = entry[entry_name]
			
			if not entry_name in entry:
				assert(not skip_unnamed, "Entry has no name, can't create Dictionary key.")
				continue
			
			# Check for duplicate entry names
			assert(not lookup_key in __dict, "Duplicate entry name: %s" % entry[entry_name])
			
			# Format entry name from lookup key to be suitable for in-game use
			entry["name"] = lookup_key.replace("_", " ").capitalize()
			
			__dict[lookup_key] = entry
		__data_dirty = false
	
	return __dict


@warning_ignore("untyped_declaration")
func is_property_valid(entry: Dictionary, property: String, value = null) -> bool:
	if value == null:
		value = entry[property]
		
	var valid: bool = property == entry_name or property == id_name
	if not valid:
		for prop: Array in __valid_properties:
			if prop[0] == property:
				@warning_ignore("unsafe_call_argument")
				assert(not is_typed or __match_type(typeof(value), prop[1]), \
				"Invalid type of property '%s' in entry '%s'." % [property, entry.get(entry_name)])
				valid = true
				break

	return valid


func load_from_path(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir:
		var file_list : Array[String]
		
		var error: Error = dir.list_dir_begin()
		if error:
			push_error("failed to init directory stream: %d" % error)
		
		var file: String = dir.get_next()
		while not file.is_empty():
			if not dir.current_is_dir():
				file_list.append(dir.get_current_dir().path_join(file))
			file = dir.get_next()
		
		dir.list_dir_end()
		file_list.sort()
		for file_path: String in file_list:
			load_from_path(file_path)
		
		return
		
	if not __did_setup:
		__setup()
		__did_setup = true

	var data: Array

	match path.get_extension():
		"cfg":
			var file: ConfigFile = ConfigFile.new()
			var error: Error = file.load(path)
			assert(error == OK, "Parse failed, invalid ConfigFile \"%s\". Error code: %s" % [path, error])
	
			data = __config_file_to_array(file)
		
		_:
			push_error("Unrecognised extension '.%s', can't extract data." % path.get_extension())
			return
	
	for entry: Dictionary in data:
		for property: String in __default_values:
			if not property in entry:
				@warning_ignore("untyped_declaration")
				var default = __default_values[property]
				if default is Array or default is Dictionary:
					@warning_ignore("unsafe_method_access")
					entry[property] = default.duplicate()
				else:
					entry[property] = default

		if not entry_name.is_empty() and not entry_name in entry:
			push_warning("Entry has no name key (%s): %s" % [entry_name, entry])

		for property: Array in __mandatory_properties:
			var property_name: String = property[0]
			if property_name in entry:
				if is_typed:
					@warning_ignore("unsafe_call_argument")
					assert(__match_type(typeof(entry[property_name]), property[1]), \
					"Invalid type of property '%s' in entry '%s'." % [property_name, entry.get(entry_name)])
			else:
				assert(false, "Missing mandatory property '%s' in entry '%s'." % [property_name, entry.get(entry_name)])

		if is_validated and OS.is_debug_build():
			for property: String in entry:
				assert(is_property_valid(entry, property), \
				"Invalid property '%s' in entry '%s'." % [property, entry[entry_name]])
			
	__data.append_array(data)
	__data_dirty = true


var __data: Array[Dictionary]
var __data_dirty: bool
var __dict: Dictionary

var __did_setup: bool

var __last_id : int
var __default_values: Dictionary
var __mandatory_properties: Array[Array]
var __valid_properties: Array[Array]


func __setup() -> void:
	if not OS.is_debug_build():
		return
		
	assert(not id_name.is_empty(), "'id_name' can't be empty String.")
	
	for property: Array in __valid_properties:
		if property[1] != TYPE_MAX:
			is_typed = true
	
	if not __valid_properties.is_empty():
		is_validated = true


func __match_type(type1: int, type2: int) -> bool:
	if type1 == TYPE_MAX or type2 == TYPE_MAX:
		return true
	
	if is_strict:
		return type1 == type2
	else:
		return type1 == type2 or (type1 == TYPE_INT and type2 == TYPE_FLOAT)


func __property_exists(property: String) -> bool:
	for p: Array in __valid_properties:
		if p[0] == property:
			return true
			
	return false


func __config_file_to_array(data : ConfigFile) -> Array[Dictionary]:
	var array : Array[Dictionary]
	
	for section: String in data.get_sections():
		var entry : Dictionary = {id_name: __last_id}
		
		if not entry_name.is_empty():
			entry[entry_name] = section
			
		__last_id += 1
		
		for value: String in data.get_section_keys(section):
			entry[value] = data.get_value(section, value)
			
		array.append(entry)
		
	return array
