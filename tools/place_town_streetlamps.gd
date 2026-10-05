extends SceneTree
## One-off, review-gated authoring of lamps in the existing house trial district.
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const TARGET="D:/code/rmmo_runtime/cache/world3d/town_streetlamps_review/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/town_streetlamps_20261005"
const PREFAB="D:/code/rmmo_runtime/packs/default/assets/prefabs/78bd5cb3f42365077142ab0e91f3513d1435403707e66a22459d84475e887801.json"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func report(name_:String,data:Dictionary)->void:
	var f:=FileAccess.open(OUT.path_join(name_),FileAccess.WRITE);f.store_string(JSON.stringify(data,"\t"));f.close()
func equivalent(a:Variant,b:Variant)->bool:
	if (a is float or a is int) and (b is float or b is int):return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for k in a:
			if not b.has(k) or not equivalent(a[k],b[k]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equivalent(a[i],b[i]):return false
		return true
	return a==b
func ground(records:Array,point:Vector3)->float:
	for r:Dictionary in records:
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*point;var y:=Terrain.sample(r,local)
		if is_finite(y):return (pose*Vector3(local.x,y,local.z)).y
	return NAN
static func roadside(segments:Array,house:Dictionary)->Dictionary:
	var basis:=Basis(Vector3.UP,deg_to_rad(house.yaw));var origin:=B.vec(house.position);var p:Dictionary=house.parameters
	var anchor:=origin+basis*Vector3(float(p.width)/2-.65,0,-float(p.depth)/2)
	var point:=Vector2(anchor.x,anchor.z);var best:=INF;var found:Dictionary={}
	for segment:Array in segments:
		var closest:=Geometry2D.get_closest_point_to_segment(point,segment[0],segment[1])
		var edge:=Vector3(closest.x,0,closest.y)
		# Only use the street in front of this facade, never a lane behind it.
		if (basis.inverse()*(edge-origin)).z>=-float(p.depth)/2:continue
		var distance:=closest.distance_squared_to(point)
		if distance>=best:continue
		best=distance
		var toward_house:=(anchor-edge).normalized();toward_house.y=0
		var tangent:=Vector3(segment[1].x-segment[0].x,0,segment[1].y-segment[0].y).normalized()
		if tangent.dot(basis.x)<0:tangent=-tangent
		# Blender -Y becomes Godot +Z: the embroidered face must point toward the road.
		if Basis(Vector3.UP,atan2(-tangent.z,tangent.x)).z.dot(-toward_house)<0:tangent=-tangent
		found={"point":edge+toward_house*.50,"edge":edge,"yaw":rad_to_deg(atan2(-tangent.z,tangent.x)),"facade_clearance":sqrt(distance)-.50}
	return found
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if "--publish" in OS.get_cmdline_user_args():
		var r:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/placement.json"))
		var v:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/physical.json"))
		check(r.failures==0 and v.failures==0 and v.lamps==r.lamps.size(),"review complete")
		check(FileAccess.get_sha256(FORMAL)==r.baseline and FileAccess.get_sha256(TARGET)==r.candidate and v.candidate==r.candidate,"unchanged reviewed candidate and formal baseline")
		if failures:quit(1);return
		var doc=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET)
		doc.records=candidate.records;doc.map_meta=candidate.map_meta;doc._next=candidate._next
		check(doc.save(FORMAL)==OK,"native atomic publication")
		var reopened=Doc.open_file(FORMAL)
		check(reopened!=null and equivalent(reopened.records,candidate.records) and equivalent(reopened.map_meta,candidate.map_meta),"formal saved contents reopen")
		report("published.json",{"failures":failures,"lamps":r.lamps.size(),"formal":FileAccess.get_sha256(FORMAL),"candidate":r.candidate})
		quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL)
	check(doc!=null,"open formal map");if failures:quit(1);return
	var original:Array=doc.records.duplicate(true);var meta:Dictionary=doc.map_meta.duplicate(true)
	check(doc.map_meta.building_instances.size()==24,"only the existing 24-house trial district")
	check(not original.any(func(r):return str(r.get("label","")).begins_with("街区试摆路灯")),"do not duplicate an already placed trial")
	var loaded:=Library.read({"prefab_path":PREFAB})
	check(loaded.ok and loaded.records.size()==1,"approved replaceable banner prefab")
	if failures:quit(1);return
	var terrain:Array=original.filter(func(r):return r.has("terrain_mesh"))
	var segments:Array=[]
	for r:Dictionary in original:
		if not r.has("road_mesh"):continue
		var transform:=Transform3D(Basis.from_euler(B.vec(r.rotation)*PI/180),B.vec(r.position))
		for polygon:Array in Road.local_polygons(r):
			for i in polygon.size():
				var a:Vector3=transform*polygon[i];var b:Vector3=transform*polygon[(i+1)%polygon.size()]
				segments.append([Vector2(a.x,a.z),Vector2(b.x,b.z)])
	var lamps:Array=[];var skipped:Array=[];var ordinal:=0
	doc.checkpoint_recovery()
	for id:String in doc.map_meta.building_instances:
		var house:Dictionary=doc.map_meta.building_instances[id];var p:Dictionary=house.parameters
		var basis:=Basis(Vector3.UP,deg_to_rad(house.yaw));var origin:=B.vec(house.position)
		var roadside_at:=roadside(segments,house)
		check(not roadside_at.is_empty() and roadside_at.facade_clearance>1.5,"roadside placement leaves facade clear")
		if failures:break
		var at:Vector3=roadside_at.point;var yaw:float=roadside_at.yaw
		var low:=INF;var high:=-INF
		for delta in [Vector3.ZERO,Vector3(.19,0,0),Vector3(-.19,0,0),Vector3(0,0,.19),Vector3(0,0,-.19)]:
			var h:=ground(terrain,at+delta);low=minf(low,h);high=maxf(high,h)
		check(is_finite(high) and is_finite(low) and high-low<.025,"lamp foot supported "+id)
		if failures:break
		at.y=high
		if lamps.any(func(l):return B.vec(l.position).distance_to(at)<8.5):
			skipped.append({"house":id,"reason":"adjacent frontage already lit within 8.5 m"});continue
		var proposed:Dictionary=loaded.records[0].duplicate(true)
		# The library pivot is the bounding-box centre; the GLB origin is the post foot.
		proposed.position=B.arr(at);proposed.rotation=[0,yaw,0]
		var bounds:=Geometry.bounds([proposed]).grow(.1)
		for zone:Dictionary in doc.map_meta.editor_layout.zones:
			var polygon:=Zones.polygon(zone)
			for cx in [bounds.position.x,bounds.end.x]:
				for cz in [bounds.position.z,bounds.end.z]:check(not Geometry2D.is_point_in_polygon(Vector2(cx,cz),polygon),"outside reserved zone "+zone.id)
		# Check the complete lantern/banner envelope against every house footprint.
		for other:Dictionary in doc.map_meta.building_instances.values():
			var ob:=Basis(Vector3.UP,deg_to_rad(other.yaw));var center:=B.vec(other.position)
			for corner:Vector3 in Geometry.corners(proposed):
				var local:Vector3=ob.inverse()*(corner-center)
				check(not (absf(local.x)<float(other.parameters.width)/2+.1 and absf(local.z)<float(other.parameters.depth)/2+.1),"lamp envelope outside facade")
		if failures:break
		var result:=Library.place(doc,{"prefab_path":PREFAB,"label":"街区试摆路灯"},at-B.vec(loaded.records[0].position))
		check(result.ok,"native prefab placement");if not result.ok:break
		var record:Dictionary=doc._find(result.ids[0]);record.rotation=[0,yaw,0];record.label="街区试摆路灯 %02d"%(ordinal+1)
		lamps.append({"id":record.uuid,"house":id,"position":record.position,"yaw":yaw,"road_edge":B.arr(roadside_at.edge),"road_offset":.50,"facade_clearance":roadside_at.facade_clearance,"width":p.width,"depth":p.depth})
		doc._undo.resize(1);ordinal+=1
	check(equivalent(original,doc.records.slice(0,original.size())) and equivalent(meta,doc.map_meta),"all previous records, houses, roads and reserved areas unchanged")
	check(lamps.size()>0 and lamps.size()<=24,"scoped placement count="+str(lamps.size()))
	var after:Array=doc.records.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original),"undo entire placement")
	check(doc.redo() and equivalent(doc.records,after),"redo entire placement")
	if failures:quit(1);return
	check(doc.save(TARGET)==OK,"native candidate save")
	var reopened=Doc.open_file(TARGET)
	check(reopened!=null and equivalent(reopened.records,after) and equivalent(reopened.map_meta,meta),"candidate save/reopen")
	report("placement.json",{"baseline":baseline,"candidate":FileAccess.get_sha256(TARGET),"prefab":FileAccess.get_sha256(PREFAB),"failures":failures,"lamps":lamps,"skipped":skipped,"houses":24})
	print("TOWN_LAMPS ",lamps.size()," failures=",failures);quit(1 if failures else 0)
