extends "res://tools/arrange_bridge_street_finish.gd"
const DETAIL_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_details_20261007"
const DETAIL_MAP="D:/code/rmmo_runtime/cache/world3d/bridge_details_20261007/map.gltf"
var changed:Array=[]
var removed:Array=[]
func _initialize()->void:
	OUT=DETAIL_OUT;TARGET=DETAIL_MAP;run.call_deferred()
func entry(label_:String)->Dictionary:
	var library=Assets.new("D:/code/rmmo_runtime/packs/default/assets")
	var found:Array=library.entries.filter(func(e):return e.label==label_)
	check(found.size()==1,"published prefab "+label_)
	return found[0] if found.size()==1 else {}
func free_site(r:Dictionary)->bool:
	var bounds:=Geometry.bounds([r]);var shapes:=Foot.record_shapes(r)
	for zone:Dictionary in doc.map_meta.editor_layout.zones:
		if not str(zone.id).begins_with("user_"):continue
		var polygon:=PackedVector2Array()
		for p:Array in zone.polygon:polygon.append(Vector2(p[0],p[1]))
		var rectangle:=PackedVector2Array([Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.end.x,bounds.position.z),Vector2(bounds.end.x,bounds.end.z),Vector2(bounds.position.x,bounds.end.z)])
		if not Geometry2D.intersect_polygons(polygon,rectangle).is_empty():return false
	for obstacle:Dictionary in doc.records:
		if not obstacle.has("building") and not obstacle.has("road_mesh") and not obstacle.has("bridge_mesh"):continue
		if bounds.intersects(Geometry.bounds([obstacle])) and Foot.batches_overlap(shapes,Foot.record_shapes(obstacle)):return false
	return true
func try_ground(key:String,at:Vector3,yaw:float=0.,scale_:Vector3=Vector3.ONE)->bool:
	var support:=ground(doc,at)
	if not is_finite(support) or support<-.3:return false
	var before:=additions.size();var id:=seated(key,at,yaw,scale_)
	if id.is_empty():return false
	var r:Dictionary=doc._find(id)
	if free_site(r):return true
	doc.records=doc.records.filter(func(v):return v.uuid!=id);additions.resize(before);return false
func run()->void:
	if "--save-plan" in OS.get_cmdline_user_args() or "--publish" in OS.get_cmdline_user_args():
		super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var baseline:=FileAccess.get_sha256(FORMAL)
	var read:=Doc.authoritative_extras(FORMAL);check(read.has("extras"),"latest saved map")
	if not read.has("extras"):quit(1);return
	doc=Doc.new();doc.records=read.extras.rmmo_records.duplicate(true);doc.map_meta=read.extras.duplicate(true);doc.map_meta.erase("rmmo_records");doc._next=300000
	var original:Array=doc.records.duplicate(true);var metadata:Dictionary=doc.map_meta.duplicate(true)
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FINAL_OUT+"/plan.json"))
	houses=old.houses.duplicate(true)
	# Apply narrowly to the identities from the earlier delivery, preserving
	# every user-adjusted transform and every unrelated record.
	doc.checkpoint_recovery()
	var natural:=Library.read(entry("原木金丝带彩柱"));check(natural.ok,"natural wood source")
	for item:Dictionary in old.props:
		var r:Dictionary=doc._find(item.id)
		if r.is_empty():continue
		if item.source=="reference_POST_green":
			check(not r.get("editor_locked",false),"green pillar editable")
			r.asset_path=natural.records[0].asset_path;r.label="原木金丝带彩柱";changed.append(r.uuid)
	# Road edges are deferred by the user; preserve all existing road/curb records.
	props.spire=entry("写实方形红顶尖塔·三层窗")
	props.shrub_round=entry("写实大团灌木·圆团");props.shrub_spread=entry("写实大团灌木·横向铺展");props.shrub_tall=entry("写实大团灌木·高冠")
	props.blue_banner=entry("写实蓝色尖尾墙挂布幡")
	# Background tower outside the five reserved special-building areas.
	var tower_ok:=false
	for at:Vector3 in [Vector3(351,0,158),Vector3(357,0,151),Vector3(347,0,145),Vector3(360,0,171)]:
		if try_ground("spire",at,0):tower_ok=true;break
	check(tower_ok,"tower site clear of buildings and roads")
	# Independently rooted foliage beside existing low walls and the river.
	var walls:Array=old.props.filter(func(p):return p.source=="bridge_street_kit_08_low_garden_wall")
	for i in walls.size():
		var wall:Dictionary=doc._find(walls[i].id)
		if wall.is_empty():continue
		var pose:=Basis(Vector3.UP,deg_to_rad(wall.rotation[1]));var at:=B.vec(wall.position)
		for side in [-1.,1.]:try_ground("shrub_spread" if i%2==0 else "shrub_round",at+pose*Vector3(.3*sin(i*2.3+side),0,side*1.15),i*31+side*18,Vector3.ONE*(1.05+.10*(i%3)))
	for spec:Array in [[306.,141.],[310.,138.],[313.,132.],[320.,141.],[325.,143.],[316.,186.],[319.,192.],[325.,208.]]:
		try_ground("shrub_tall" if int(spec[0])%2==0 else "shrub_round",Vector3(spec[0],0,spec[1]),spec[0]*7,Vector3.ONE*.9)
	# Small hanging banners attach to blank front-wall piers, above headroom;
	# no signs on doors or windows, and no implicit guild landmark assignment.
	var flag_count:=0
	for h:Dictionary in houses:
		if h.rear or h.edge!=0 or flag_count>=3:continue
		var p:Dictionary=doc.map_meta.building_instances[h.id].parameters
		if p.floors<2:continue
		var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw));var at:=B.vec(h.position)+basis*Vector3(p.width/2-.8,2.8,-p.depth/2-.12)
		prop("blue_banner",at,h.yaw);flag_count+=1
	var preserved:=true
	for r:Dictionary in original:
		if r.uuid in changed or r.uuid in removed:continue
		if not equivalent(r,doc._find(r.uuid)):preserved=false
	check(preserved,"all unrelated records including three user-moved planters preserved")
	check(equivalent(doc.map_meta,metadata),"building road reservations and environment metadata unchanged")
	var final:Array=doc.records.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original),"one content undo")
	check(doc.redo() and equivalent(doc.records,final),"one content redo")
	write_report("plan.json",{"failures":failures,"formal_sha256":baseline,"records":doc.records,"metadata":doc.map_meta,"next":doc._next,"houses":houses,"props":additions,"omitted":omitted,"changed":changed,"removed":removed,"bridge_id":"stone_e_0be972769041dbc9"})
	print("DETAIL_PLAN additions=",additions.size()," changed=",changed.size()," removed=",removed.size()," failures=",failures);quit(failures)
