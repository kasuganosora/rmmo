extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const F=preload("res://scripts/world3d/house_prefab.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
func _init()->void:call_deferred("run")
func run()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/wall_candidate_records.json"));var rows:Array=[]
	for r:Dictionary in source.records:
		if not r.has("fortification") or not r.has("house_prefab"):continue
		var data:=F.decode(r.house_prefab);var seen:Dictionary={}
		for entry:Array in data.entries:seen[entry[1][0]]=true
		for mi:int in seen:
			var mesh:Dictionary=data.meshes[mi]
			for si in mesh.surfaces.size():
				var a:Array=mesh.surfaces[si];var ts:Variant=a[Mesh.ARRAY_TANGENT]
				if ts==null:continue
				var mat:Dictionary=data.materials[mesh.materials[si]];var normalmap:=not str(mat.get("paint",{}).get("normal_path","")).is_empty()
				var ids:PackedInt32Array=a[Mesh.ARRAY_INDEX];var used:Dictionary={}
				if ids.is_empty():ids=PackedInt32Array(range(a[Mesh.ARRAY_VERTEX].size()))
				for k in range(0,ids.size(),3):
					if (a[Mesh.ARRAY_VERTEX][ids[k+1]]-a[Mesh.ARRAY_VERTEX][ids[k]]).cross(a[Mesh.ARRAY_VERTEX][ids[k+2]]-a[Mesh.ARRAY_VERTEX][ids[k]]).length_squared()>0.:
						for j in 3:used[ids[k+j]]=true
				var row:={"record":r.uuid,"surface":si,"normalmap":normalmap,"zero":0,"off_axis":0,"max_dot":0.,"samples":[]}
				for i:int in used:
					var t:=Vector3(ts[4*i],ts[4*i+1],ts[4*i+2]);var n:Vector3=a[Mesh.ARRAY_NORMAL][i];var dot_:float=absf(t.normalized().dot(n.normalized()))
					if t.length_squared()<.1:row.zero+=1
					elif dot_>.001:
						row.off_axis+=1;row.max_dot=maxf(row.max_dot,dot_)
						if row.samples.size()<3:row.samples.append({"vertex":i,"normal":F.arr(n),"tangent":F.arr(t)+[ts[4*i+3]],"dot":dot_,"local":F.arr(a[Mesh.ARRAY_VERTEX][i])})
				if row.zero+row.off_axis>0:rows.append(row)
	var report:={"map_sha256":source.map_sha256,"rows":rows}
	FileAccess.open(OUT+"/fortification_tangent_orthogonality.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(rows.filter(func(r):return r.record.ends_with("baked_0"))));quit(0)
