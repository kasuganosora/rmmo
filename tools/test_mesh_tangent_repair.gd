extends SceneTree
const Repair=preload("res://scripts/world3d/mesh_tangent_repair.gd")
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Probe=preload("res://tools/probe_axel_fortification_tangents.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var proof:Dictionary={"checks":[],"failures":0,"scope":"read-only CPU arrays; no candidate mutation"}
func _init()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	proof.checks.append({"check":label_,"passed":ok})
	if not ok:proof.failures+=1
	print("PASS " if ok else "FAIL ",label_)
func fixture(mirror:bool)->Array:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points:=[Vector3(0,0,0),Vector3(2,.3,0),Vector3(.2,.4,3)];var n:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
	var uvs:=[Vector2.ZERO,Vector2(-1 if mirror else 1,.1),Vector2(.2,1)]
	for i in 3:st.set_normal(n);st.set_uv(uvs[i]);st.add_vertex(points[i])
	st.generate_tangents();st.index();return st.commit_to_arrays()
func unchanged_channels(a:Array,b:Array)->bool:
	for i in Mesh.ARRAY_MAX:
		if i!=Mesh.ARRAY_TANGENT and var_to_bytes(a[i])!=var_to_bytes(b[i]):return false
	return true
func validate(a:Array,b:Array)->Dictionary:
	var t:PackedFloat32Array=a[Mesh.ARRAY_TANGENT];var r:PackedFloat32Array=b[Mesh.ARRAY_TANGENT];var n:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	var repaired:=0;var stable:=true;var basis:=true
	for i in n.size():
		var original:=Vector3(t[4*i],t[4*i+1],t[4*i+2]);var current:=Vector3(r[4*i],r[4*i+1],r[4*i+2])
		if not Repair.invalid(original,t[i*4+3],n[i]):
			for k in 4:stable=stable and t[4*i+k]==r[4*i+k]
		else:
			repaired+=1;basis=basis and current.is_finite() and absf(current.length()-1.)<.00001 and absf(current.dot(n[i].normalized()))<.00001 and absf(r[i*4+3])==1.
	return {"repaired":repaired,"stable":stable,"basis":basis,"channels":unchanged_channels(a,b)}
func run()->void:
	for mirror:bool in [false,true]:
		var a:=fixture(mirror);var original:=var_to_bytes(a);var bad:=a.duplicate(true)
		for k in 3:bad[Mesh.ARRAY_TANGENT][k]=0.
		var fixed:=Repair.repair(bad);var result:=validate(bad,fixed)
		check(result.repaired==1 and result.stable and result.basis and result.channels,"selective orthonormal repair, mirror="+str(mirror))
		var t:PackedFloat32Array=fixed[Mesh.ARRAY_TANGENT];var reference:PackedFloat32Array=a[Mesh.ARRAY_TANGENT]
		print("BASIS ",mirror," new=",t.slice(0,4)," native=",reference.slice(0,4))
		check(Vector3(t[0],t[1],t[2]).dot(Vector3(reference[0],reference[1],reference[2]))>.9999 and t[3]==reference[3],"handedness agrees with native MikkTSpace, mirror="+str(mirror))
		check(var_to_bytes(a)==original and var_to_bytes(Repair.repair(a))==original,"valid source remains byte exact")
		var broken:=a.duplicate(true);broken[Mesh.ARRAY_TANGENT][0]=NAN;broken[Mesh.ARRAY_TANGENT][3]=NAN
		var repaired:=Repair.repair(broken);check(validate(broken,repaired).basis and unchanged_channels(broken,repaired),"non-finite tangent repaired without geometry edit")
		var singular:=a.duplicate(true);singular[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]);singular[Mesh.ARRAY_TANGENT]=PackedFloat32Array([0,0,0,-1,0,0,0,1,0,0,0,1])
		var fallback:=Repair.repair(singular);var fallback_check:=validate(singular,fallback)
		check(fallback_check.repaired==3 and fallback_check.channels and fallback_check.basis and fallback[Mesh.ARRAY_TANGENT][3]==-1.,"singular UV deterministic basis retains sign and all channels")
	var pin:=FileAccess.get_sha256(Probe.MAP);var doc=Doc.open_file(Probe.MAP);var total:=0;var surfaces:=0;var failures:=0
	for record:Dictionary in doc.records:
		if not record.has("fortification") or not record.has("house_prefab"):continue
		var data:=Frozen.decode(record.house_prefab);var seen:Dictionary={}
		for entry:Array in data.entries:seen[entry[1][0]]=true
		for mi:int in seen:
			for si in data.meshes[mi].surfaces.size():
				if str(data.materials[data.meshes[mi].materials[si]].get("paint",{}).get("normal_path","")).is_empty():continue
				var arrays:Array=data.meshes[mi].surfaces[si]
				if arrays[Mesh.ARRAY_TANGENT]==null:continue
				if not proof.has("extra_invalid_samples"):proof.extra_invalid_samples=[]
				for i in arrays[Mesh.ARRAY_VERTEX].size():
					var ts:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT];var n:Vector3=arrays[Mesh.ARRAY_NORMAL][i];var tv:=Vector3(ts[4*i],ts[4*i+1],ts[4*i+2])
					if proof.extra_invalid_samples.size()<8 and tv.length_squared()>=.1 and Repair.invalid(tv,ts[4*i+3],n):proof.extra_invalid_samples.append({"record":record.uuid,"normal":Probe.v3(n),"tangent":Probe.v3(tv)+[ts[4*i+3]],"dot":n.normalized().dot(tv.normalized())})
				var before:=var_to_bytes(arrays);var fixed:=Repair.repair(arrays);var result:=validate(arrays,fixed)
				if result.repaired>0:surfaces+=1;total+=result.repaired
				if not result.stable or not result.basis or not result.channels or before!=var_to_bytes(arrays):failures+=1
	check(total==1904 and surfaces==39,"actual frozen failure set reproduces 39 surfaces / 184 zero and 1720 non-orthogonal points")
	check(failures==0,"all 1904 invalid bases fixed; every good tangent and other channel byte exact")
	check(pin==FileAccess.get_sha256(Probe.MAP),"candidate map remains unchanged")
	proof.actual={"surfaces":surfaces,"repaired":total,"map_sha256":pin};proof.passed=proof.failures==0
	FileAccess.open(OUT+"/mesh_tangent_repair_test.json",FileAccess.WRITE).store_string(JSON.stringify(proof,"\t"));quit(proof.failures)
