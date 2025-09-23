class_name PasteMatPropsWindow 
extends Window

@export var paste_box: TextEdit


var material_props: Array[Array]
var material_meta: Dictionary[String, int] = {
	"id" = 0,
	"type" = 0,
	#"ver" = 0
}


func _ready() -> void:
	if DisplayServer.clipboard_has():
		var compact_str : String = DisplayServer.clipboard_get()
		paste_box.text = compact_str
		_parse_str(compact_str)


func _parse_str(compact_str: String) -> void:
	var raw : PackedByteArray = Marshalls.base64_to_raw(compact_str)
	var decompressed_bytes : PackedByteArray = raw.decompress(2000, FileAccess.COMPRESSION_DEFLATE)
	var data : Variant = bytes_to_var(decompressed_bytes)
	
	if data is Array:
		material_props = data
		var temp_metadata: Array = material_props.pop_back()
		
		if temp_metadata[0] is int:
			material_meta.id = temp_metadata[0]
		if temp_metadata[1] is int:
			material_meta.type = temp_metadata[1]
		## TODO - version check too
		#if temp_metadata[2] is int:
			#print(temp_metadata[2])


func _on_load_btn_pressed() -> void:
	MaterialDataLoader.load_material_from_data(material_meta.id, material_meta.type, "0", material_props)
	for i : int in 2:
		await get_tree().process_frame
	MaterialDataLoader.load_serialised_material_props()
	queue_free()


func _on_close_requested() -> void:
	queue_free()
