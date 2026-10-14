extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Bridge=preload("res://scripts/world3d/bridge_mesh.gd")
const Structure=preload("res://scripts/world3d/structure_prefab.gd")
const Audit=preload("res://tools/audit_axel_bridge_assets.gd")
const MAP="D:/code/rmmo_runtime/cache/world3d/axel_town_roads_20261014/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_roads_20261014/bridge_tangent_regression.json"
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func basis_contract()->void:
	# Compare the derivative recovery with Godot's own healthy tangent basis,
	# including a mirrored UV island; do not assume the sign convention.
	for mirror in [1.0,-1.0]:
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points:=[Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]
		var uvs:=[Vector2.ZERO,Vector2(mirror,0),Vector2(0,1)]
		for i in 3:
			st.set_normal(Vector3.UP);st.set_uv(uvs[i]);st.add_vertex(points[i])
		st.generate_tangents();var arrays:=st.commit_to_arrays()
		var expected:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT].duplicate()
		var blank:=PackedFloat32Array();blank.resize(12);arrays[Mesh.ARRAY_TANGENT]=blank
		var recovered:=Bridge.repair_zero_tangents(arrays)
		var matches:bool=recovered.ok
		for i in expected.size():matches=matches and is_equal_approx(arrays[Mesh.ARRAY_TANGENT][i],expected[i])
		if not matches:print("basis expected=",expected," recovered=",arrays[Mesh.ARRAY_TANGENT])
		check(matches,"Godot tangent and mirrored-UV handedness contract "+str(mirror))
		blank=PackedFloat32Array();blank.resize(12);arrays[Mesh.ARRAY_TANGENT]=blank;arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
		check(not Bridge.repair_zero_tangents(arrays).ok,"degenerate UV is rejected, never given arbitrary tangent")
func run()->void:
	basis_contract()
	if "--basis-only" in OS.get_cmdline_user_args():quit(0 if failures==0 else 1);return
	var before:=FileAccess.get_sha256(MAP);var doc=Doc.open_file(MAP);var report:={"map_sha256":before,"bridges":[]}
	for record:Dictionary in doc.records:
		if not record.has("bridge_mesh"):continue
		var data:=Frozen.decode(record.house_prefab);var row:={"id":record.uuid,"surfaces":[]}
		for entry:Array in data.entries:
			var mesh:Dictionary=data.meshes[entry[1][0]]
			for si in mesh.surfaces.size():
				var original:Array=mesh.surfaces[si];var arrays:Array=original.duplicate(true)
				var result:=Bridge.repair_zero_tangents(arrays)
				check(result.ok,str(record.uuid)+" repair surface "+str(si))
				for channel in Mesh.ARRAY_MAX:
					if channel==Mesh.ARRAY_TANGENT:continue
					check(arrays[channel]==original[channel],"unchanged geometry/normal/UV channel "+str(channel))
				var valid_kept:=true;var ortho:=true;var old:PackedFloat32Array=original[Mesh.ARRAY_TANGENT];var now:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
				for i in arrays[Mesh.ARRAY_VERTEX].size():
					var t:=Vector3(now[i*4],now[i*4+1],now[i*4+2]);var n:Vector3=arrays[Mesh.ARRAY_NORMAL][i]
					var previous:=Vector3(old[i*4],old[i*4+1],old[i*4+2])
					if previous.length_squared()>=.1:
						for j in 4:valid_kept=valid_kept and old[i*4+j]==now[i*4+j]
					else:ortho=ortho and absf(t.length()-1)<.0001 and absf(t.dot(n))<.0001 and absf(now[i*4+3])==1
				check(valid_kept and ortho,"existing bases preserved; recovered bases unit/orthogonal/handed")
				check(Audit.surface_audit(arrays,true,si==0,record.bridge_mesh.width).attribute_check_passed,"strict attribute audit passes")
				var repeat:=Bridge.repair_zero_tangents(arrays);check(repeat.repaired==0,"repair idempotent")
				row.surfaces.append({"surface":si,"repaired":result.repaired})
		var source:=record.duplicate(true);source.erase("house_prefab");source.erase("prefab_locked");source.erase("prefab_materials")
		var baked:=Structure.bridge(source);check(baked.ok,"actual shared generator/freeze "+str(record.uuid))
		if baked.ok:
			var cooked:=Frozen.decode(baked.record.house_prefab);var generated:Dictionary=cooked.meshes[cooked.entries[0][1][0]]
			var old_collision:Dictionary=data.meshes[data.entries[0][1][1]]
			var next_collision:Dictionary=cooked.meshes[cooked.entries[0][1][1]]
			var same_collision:bool=old_collision.surfaces.size()==next_collision.surfaces.size()
			for si in generated.surfaces.size():
				var result:=Audit.surface_audit(generated.surfaces[si],true,si==0,record.bridge_mesh.width)
				check(result.attribute_check_passed and result.white_rim_bad_vertices_or_normals==0,"new frozen strict audit "+str([record.uuid,si]))
				same_collision=same_collision and old_collision.surfaces[si][Mesh.ARRAY_VERTEX]==next_collision.surfaces[si][Mesh.ARRAY_VERTEX] and old_collision.surfaces[si][Mesh.ARRAY_INDEX]==next_collision.surfaces[si][Mesh.ARRAY_INDEX]
			check(same_collision,"collision vertices/indices unchanged")
			check(generated.get("lods",[]).size()==3 and not generated.lods[1].is_empty() and not generated.lods[2].is_empty(),"frozen masonry/detail LOD retained")
			row.new_frozen_sha256=baked.record.house_prefab.sha256
		report.bridges.append(row)
	check(FileAccess.get_sha256(MAP)==before,"candidate remains unchanged")
	report.failures=failures;report.scope="CPU targeted derivative recovery and actual shared generator/freeze; GPU visual and native map integration remain pending"
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BRIDGE_TANGENT_REGRESSION failures=",failures);quit(0 if failures==0 else 1)
