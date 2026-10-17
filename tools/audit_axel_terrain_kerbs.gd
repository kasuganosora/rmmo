extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const T=preload("res://scripts/world3d/terrain_surface.gd")
const K=preload("res://scripts/world3d/road_kerb.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
var terrains:Array=[]
func height(at:Vector3)->float:
	var y:float=-INF
	for ground:Dictionary in terrains:
		if absf(at.x-ground.position[0])>ground.size[0]*.5+.01 or absf(at.z-ground.position[2])>ground.size[2]*.5+.01:continue
		var pose:=T.transform(ground);var local:=pose.affine_inverse()*at;var h:=T.sample(ground,local)
		if is_finite(h):y=maxf(y,(pose*Vector3(local.x,h,local.z)).y)
	return y
func inspect(rows:Array)->Dictionary:
	var out:={"roads":0,"kerb_strips":0,"kerb_triangles":0,"material_descriptors":{},"records":[],"sampled_rails":0,"worst_error_m":0.,"worst":{},"nonfinite_vertices":0}
	terrains=rows.filter(func(r):return r.has("terrain_mesh"))
	for row:Dictionary in rows:
		if not row.has("road_mesh"):continue
		out.roads+=1
		var parts:Array=row.road_mesh.get("kerbs",[]);out.kerb_strips+=parts.size()
		var triangles:=0
		if not parts.is_empty():
			var mesh:Array=K.arrays(row);triangles=mesh[Mesh.ARRAY_VERTEX].size()/3
			for p:Vector3 in mesh[Mesh.ARRAY_VERTEX]:
				if not p.is_finite():out.nonfinite_vertices+=1
		out.kerb_triangles+=triangles
		out.records.append({"id":row.uuid,"source_record_sha256":City.token(row),"strips":parts.size(),"triangles":triangles})
		if row.has("road_kerb_material"):out.material_descriptors[City.token(row.road_kerb_material)]=row.road_kerb_material
		var origin:=K.vec(row.position)
		if origin.x<320 or origin.x>370 or origin.z<140 or origin.z>195:continue
		for part:Dictionary in parts:
			for rail:int in [2,3]:
				var a:=origin+K.vec(part.a[rail]);var b:=origin+K.vec(part.b[rail])
				for t:float in [.125,.25,.5,.75,.875]:
					var at:=a.lerp(b,t);var error:float=absf(at.y-height(at)-.025-.035);out.sampled_rails+=1
					if error>out.worst_error_m:out.worst_error_m=error;out.worst={"id":row.uuid,"at":K.xyz(at)}
	return out
func _initialize()->void:run.call_deferred()
func run()->void:
	var base:="";var candidate:="";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-records="):base=arg.trim_prefix("--baseline-records=")
		elif arg.begins_with("--map="):candidate=arg.trim_prefix("--map=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	var prior:Array=JSON.parse_string(FileAccess.get_file_as_string(base));var doc=Doc.open_file(candidate)
	if doc==null:quit(1);return
	var report:={"candidate":candidate,"candidate_sha256":FileAccess.get_sha256(candidate),"baseline_records_sha256":FileAccess.get_sha256(base),"baseline":inspect(prior),"candidate_geometry":inspect(doc.records)}
	report.passed=report.candidate_geometry.worst_error_m<.001 and report.candidate_geometry.nonfinite_vertices==0
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("KERB_AUDIT ",JSON.stringify({"passed":report.passed,"before_error":report.baseline.worst_error_m,"after_error":report.candidate_geometry.worst_error_m,"before_triangles":report.baseline.kerb_triangles,"after_triangles":report.candidate_geometry.kerb_triangles}));quit(0 if report.passed else 1)
