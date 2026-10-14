extends SceneTree
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var index:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/house_templates.json"))
	var rows:Array=[];var failures:=0
	for item:Dictionary in index.templates:
		var loaded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(item.loaded_path))
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
