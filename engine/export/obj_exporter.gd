class_name OBJExporter
extends RefCounted
## Class to export to obj format.
##
## Parses the given surface array from the mesh, and saves a minified output
## by filtering out non-unique data and rounding / snapping floating point errors
## Produces obj files around 3-4x smaller than other open-source Godot implementations

static func export_obj(surface_array: Array, file_path: String) -> void:
	# Buffers to store unique data and mappings
	var unique_vertices : Dictionary = {}
	var unique_normals : Dictionary = {}
	var unique_uvs : Dictionary = {}
	var index_map : Dictionary = {}
	
	# Incremental counters for unique indices
	var vertex_count : int = 1
	var normal_count : int = 1
	var uv_count : int = 1
	
	# Buffers for organized output
	var vertex_buffer : String = ""
	var normal_buffer : String = ""
	var uv_buffer : String = ""
	var face_buffer : String = ""
	
	# Get arrays from the surface array
	var vertices : PackedVector3Array = surface_array[Mesh.ARRAY_VERTEX]
	var normals : PackedVector3Array = surface_array[Mesh.ARRAY_NORMAL]
	var uvs : PackedVector2Array = surface_array[Mesh.ARRAY_TEX_UV]
	var indices : PackedInt32Array = surface_array[Mesh.ARRAY_INDEX]
	
	# Add vertices, normals, and UVs
	for idx: int in vertices.size():
		var vertex_vec : Vector3 = vertices[idx]
		var normal_vec : Vector3 = normals[idx]
		var vertex_key : String = "{0},{1},{2}".format([vertex_vec.x, vertex_vec.y, vertex_vec.z])
		var normal_key : String = "{0},{1},{2}".format([normal_vec.x, normal_vec.y, normal_vec.z])
		var uv_key : String = ""
		
		uv_key = "{0},{1}".format([uvs[idx].x, uvs[idx].y])
		
		if not unique_vertices.has(vertex_key):
			unique_vertices[vertex_key] = vertex_count
			vertex_buffer += "v {0} {1} {2}\n".format([snapped(vertex_vec.x, 0.1), snapped(vertex_vec.y, 0.1), snapped(vertex_vec.z, 0.1)])
			vertex_count += 1
		
		if not unique_normals.has(normal_key):
			unique_normals[normal_key] = normal_count
			normal_buffer += "vn {0} {1} {2}\n".format([round(normal_vec.x), round(normal_vec.y), round(normal_vec.z)])
			normal_count += 1
		
		if not unique_uvs.has(uv_key):
			unique_uvs[uv_key] = uv_count
			uv_buffer += "vt {0} {1}\n".format([snapped(uvs[idx].x, 0.1), snapped(uvs[idx].y, 0.1)])
			uv_count += 1
		
		# Map the index for faces
		index_map[idx] = [
				unique_vertices[vertex_key],
				unique_uvs.get(uv_key, -1),
				unique_normals[normal_key]
		]
	
	# Add faces
	for idx : int in range(0, indices.size(), 3):
		var v1 : PackedInt32Array = index_map[indices[idx + 0]]
		var v2 : PackedInt32Array = index_map[indices[idx + 1]]
		var v3 : PackedInt32Array = index_map[indices[idx + 2]]
		
		# Face format: "f v1/t1/n1 v2/t2/n2 v3/t3/n3"
		if v1[1] != -1:
			face_buffer += "f {0}/{1}/{2} {3}/{4}/{5} {6}/{7}/{8}\n".format(
				[v3[0], v3[1], v3[2], v2[0], v2[1], v2[2], v1[0], v1[1], v1[2]]
			)
		else:
			face_buffer += "f {0}//{1} {2}//{3} {4}//{5}\n".format(
				[v3[0], v3[2], v2[0], v2[2], v1[0], v1[2]]
			)
	
	var output : String = vertex_buffer + normal_buffer + uv_buffer + face_buffer
	
	var dest_path : String = ProjectSettings.globalize_path(file_path)
	var dest_file : FileAccess = FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest_file:
		Logger.call_deferred("puts_error", "Failed to create destination file: %s" % dest_path)
		return
	@warning_ignore("return_value_discarded")
	dest_file.store_string(output)
	dest_file.close()
