extends SceneTree
## Read-only saved mesh/material/bed sampling. Never edits or saves the map.
const Doc=preload("res://scripts/world3d/world_document.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Profile=preload("res://scripts/world3d/terrain_river_profile.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var terrains:Array=[]
var triangles:Array=[]
func _init()->void:call_deferred("run")
func xyz(p:Vector3)->Array:return [p.x,p.y,p.z]
func ground(point:Vector2)->float:
	for record:Dictionary in terrains:
		var pose:=Terrain.transform(record);var local:Vector3=pose.affine_inverse()*Vector3(point.x,0,point.y)
		var height:=Terrain.sample(record,local)
		if is_finite(height):return (pose*Vector3(local.x,height,local.z)).y
	return NAN
func water_at(point:Vector2)->Dictionary:
	for row:Dictionary in triangles:
		var p:Array=row.points
		var a:=Vector2(p[0].x,p[0].z);var b:=Vector2(p[1].x,p[1].z);var c:=Vector2(p[2].x,p[2].z)
		var area:float=(b-a).cross(c-a)
		if absf(area)<.00000001:continue
		var v:float=(point-a).cross(c-a)/area;var w:float=(b-a).cross(point-a)/area
		if v<-.00001 or w<-.00001 or v+w>1.00001:continue
		return {"id":row.id,"y":p[0].y*(1-v-w)+p[1].y*v+p[2].y*w,"visible_material":row.visible,"normal_y":row.normal_y}
	return {}
func run()->void:
	var path:="D:/code/rmmo_runtime/cache/world3d/axel_town_houses_20261014/map.gltf";var tag:="before"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg.begins_with("--tag="):tag=arg.trim_prefix("--tag=")
	var before_sha:=FileAccess.get_sha256(path);var doc=Doc.open_file(path)
	if doc==null:push_error("Native map open failed");quit(1);return
	terrains=doc.records.filter(func(r):return r.has("terrain_mesh"))
	var rows:Array=[];var legacy_hidden:=0;var actual_hidden:=0
	for record:Dictionary in doc.records:
		var branch:bool=str(record.uuid).begins_with("river_axel_s12_stream_")
		if not branch and not (str(record.uuid).begins_with("river_axel_main_river_") and absf(float(record.position[0])-320)<24 and absf(float(record.position[2])-145)<24):continue
		var node:=MeshInstance3D.new();node.mesh=Channel.mesh(record,StandardMaterial3D.new())
		var source:Mesh=node.mesh.get_meta("ground_cpu_cache")
		River.apply(node,record,{},null,true)
		var arrays:Array=source.surface_get_arrays(0);var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var visible:bool=node.get_active_material(0)!=River.hidden_slab
		var lo:=1.;var hi:=-1.
		for normal:Vector3 in normals:lo=minf(lo,normal.y);hi=maxf(hi,normal.y)
		var old_visible:bool=not normals.is_empty() and normals[0].y>.99
		if branch:
			if not old_visible:legacy_hidden+=1
			if not visible:actual_hidden+=1
			rows.append({"id":record.uuid,"position":record.position,"polygons":record.channel_mesh.polygons.size(),"surface_paint":record.has("surface_paint"),"normal_y_min":lo,"normal_y_max":hi,"first_normal_y":normals[0].y,"legacy_top_visible":old_visible,"actual_top_visible":visible,"underside_hidden":node.get_active_material(1)==River.hidden_slab,"sides_hidden":node.get_active_material(2)==River.hidden_slab})
		var pose:=Terrain.transform(record)
		for at in range(0,points.size(),3):triangles.append({"id":record.uuid,"points":[pose*points[at],pose*points[at+1],pose*points[at+2]],"normal_y":normals[at].y,"visible":visible})
		node.free()
	var layers:Array=doc.map_meta.terrain_rivers.filter(func(r):return r.id=="axel_s12_stream")
	var curve:=Profile.prepare(layers[0].request);var samples:Array=[];var missing:=0;var buried:=0;var min_gap:=INF;var hidden_samples:=0;var missing_rows:Array=[]
	for i in curve.path.size()-1:
		var a:=Vector2(curve.path[i][0],curve.path[i][1]);var b:=Vector2(curve.path[i+1][0],curve.path[i+1][1]);var lateral:=Vector2(-(b-a).y,(b-a).x).normalized()
		if a.x>338 or a.y<120:continue
		for j in range(5):
			for offset in [-.45,0.,.45]:
				var xz:Vector2=a.lerp(b,float(j)/5.)+lateral*offset;var water:=water_at(xz);var soil:=ground(xz)
				if water.is_empty() or not is_finite(soil):
					missing+=1;missing_rows.append({"xz":[xz.x,xz.y],"offset":offset,"no_water":water.is_empty(),"ground_y":soil if is_finite(soil) else null});continue
				var gap:float=water.y-soil;min_gap=minf(min_gap,gap)
				if gap<=0:buried+=1
				if not water.visible_material:hidden_samples+=1
				samples.append({"xz":[xz.x,xz.y],"offset":offset,"ground_y":soil,"water_y":water.y,"clearance_m":gap,"water_id":water.id,"visible_material":water.visible_material,"normal_y":water.normal_y})
	var report:={"map_path":path,"map_sha256":before_sha,"unchanged":FileAccess.get_sha256(path)==before_sha,"scope":"saved native channel top triangles and native terrain samples within center +/-0.45m along bridge downstream reach; material assignment only, no GPU image approval","water_chunks":rows,"legacy_hidden_top_chunks":legacy_hidden,"actual_hidden_top_chunks":actual_hidden,"samples":samples,"sample_count":samples.size(),"missing_samples":missing,"buried_samples":buried,"minimum_bed_clearance_m":min_gap,"hidden_material_samples":hidden_samples,"river_materials_sha256":FileAccess.get_sha256("res://scripts/world3d/river_materials.gd")}
	report.missing_rows=missing_rows
	var file:=FileAccess.open(OUT+"/sloped_water_diagnostic_"+tag+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SLOPED_WATER ",JSON.stringify({"sha":before_sha,"chunks":rows.size(),"hidden":actual_hidden,"samples":samples.size(),"missing":missing,"buried":buried,"min_gap":min_gap,"hidden_samples":hidden_samples,"unchanged":report.unchanged}));quit(0)
