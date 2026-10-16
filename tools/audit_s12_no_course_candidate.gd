extends SceneTree
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/s12_no_course_candidate"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/house_templates.json"))
	var rows:Array=[];var failures:=0
	for item:Dictionary in index.templates:
		var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(item.loaded_path))
		var Doc=load("res://scripts/world3d/world_document.gd")
		var doc=Doc.new();doc.records=loaded.records;doc.map_meta.building_instances=loaded.building_instances;doc._next=990000
		var map_path:=OUT+"/native_reopen/map.gltf"
		DirAccess.make_dir_recursive_absolute(map_path.get_base_dir())
		var saved:Error=doc.save(map_path)
		var reopened=Doc.open_file(map_path) if saved==OK else null
		if reopened==null:failures+=1
		elif not equivalent(doc.records,reopened.records) or not equivalent(doc.map_meta,reopened.map_meta):failures+=1
		print("S12_CANDIDATE_SAVE_REOPEN failures=",failures)
		var row:Dictionary={"id":item.id,"payloads":[],"render_triangles":0,"render_surfaces":0,"collision_triangles":0,"native_materials":[],"lights":[],"errors":[]}
		for r:Dictionary in loaded.records:
			if r.get("building",{}).get("role")=="light_sconce":row.lights.append({"part":r.building.part,"position":r.position,"scope":"interior_room"})
			if not r.has("house_prefab"):continue
			var data:Dictionary=Prefab.decode(r.house_prefab)
			if data.is_empty():row.errors.append("decode failed: "+str(r.uuid));continue
			var slots:Array=data.entries[0][1]
			var counts:Dictionary={"sha256":r.house_prefab.sha256,"compressed_bytes":Marshalls.base64_to_raw(r.house_prefab.data).size(),"decoded_bytes":r.house_prefab.length,"render_triangles":0,"render_surfaces":0,"collision_triangles":0}
			for pair:Array in [[int(slots[0]),"render_triangles"],[int(slots[1]),"collision_triangles"]]:
				var mesh:Dictionary=data.meshes[pair[0]]
				for surface:Array in mesh.surfaces:
					var inds:Variant=surface[Mesh.ARRAY_INDEX];var verts:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
					counts[pair[1]]+=int((inds.size() if inds!=null and not inds.is_empty() else verts.size())/3)
				if pair[1]=="render_triangles":counts.render_surfaces=mesh.surfaces.size()
			for k in ["render_triangles","render_surfaces","collision_triangles"]:row[k]+=counts[k]
			row.payloads.append(counts)
			for material:Dictionary in data.materials:
				if material not in row.native_materials:row.native_materials.append(material)
		failures+=row.errors.size();rows.append(row)
	FileAccess.open(OUT+"/house_template_native_audit.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"templates":rows,"note":"Decoded actual frozen payloads. Surface counts are authored mesh surfaces, not runtime draw calls."},"\t"))
	print("HOUSE_NATIVE_AUDIT ",rows.size()," failures ",failures);quit(failures)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not equivalent(a[index], b[index]): return false
		return true
	return a == b
