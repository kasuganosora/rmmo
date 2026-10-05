extends RefCounted
const Envelope=preload("res://scripts/world3d/map_metadata_cache.gd")
const DIR:="user://world3d_navigation"
static func path(key:String)->String:return DIR.path_join(key.sha256_text()+".bin")
static func restore(key:String,mesh:NavigationMesh)->bool:
	if key.is_empty():return false
	var file:=FileAccess.open(path(key),FileAccess.READ)
	if file==null or file.get_length()<32 or file.get_length()>268435456:return false
	var hash:=file.get_buffer(32);var bytes:=file.get_buffer(file.get_length()-32)
	if Envelope.checksum(bytes)!=hash:return false
	var data:Variant=bytes_to_var(bytes)
	if not data is Dictionary or not data.get("vertices") is PackedVector3Array or not data.get("polygons") is Array:return false
	if data.polygons.is_empty():return false
	for vertex:Vector3 in data.vertices:
		if not vertex.is_finite():return false
	for polygon in data.polygons:
		if not polygon is PackedInt32Array or polygon.size()<3:return false
		for index in polygon:
			if index<0 or index>=data.vertices.size():return false
	mesh.set_vertices(data.vertices)
	for polygon:PackedInt32Array in data.polygons:mesh.add_polygon(polygon)
	return true

static func store_mesh(key:String,mesh:NavigationMesh)->void:
	if mesh.get_polygon_count()==0:return
	if key.is_empty() or DirAccess.make_dir_recursive_absolute(DIR)!=OK:return
	var polygons:Array=[]
	for i in mesh.get_polygon_count():polygons.append(mesh.get_polygon(i))
	var bytes:=var_to_bytes({"vertices":mesh.get_vertices(),"polygons":polygons})
	var target:=path(key);var temporary:=target+".%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return
	file.store_buffer(Envelope.checksum(bytes));file.store_buffer(bytes);file.close()
	if DirAccess.rename_absolute(temporary,target)!=OK:DirAccess.remove_absolute(temporary)
