extends "res://tools/finish_bridge_details_20261007.gd"
const FIX_OUT="D:/code/rmmo_runtime/review_artifacts/bridge_spire_courtyard_20261007"
const FIX_MAP="D:/code/rmmo_runtime/cache/world3d/bridge_spire_courtyard_20261007/map.gltf"
const SPIRE="obj_300001"
const HOUSE="building_911d5e25d3ff8ab3477b"
var house_origin:Vector3
var house_basis:Basis
var house_yaw:float
var gate_x:float
func _initialize()->void:
	OUT=FIX_OUT;TARGET=FIX_MAP;run.call_deferred()
func yard_point(x:float,z:float)->Vector3:return house_origin+house_basis*Vector3(x,0,z)
func wall(a:Vector2,b:Vector2)->void:
	var length:=a.distance_to(b);var count:=maxi(1,roundi(length/2.4));var step:=length/count
	var yaw:=house_yaw-rad_to_deg(atan2(b.y-a.y,b.x-a.x))
	for i in count:
		var p:=a.lerp(b,(i+.5)/count)
		seated("wall",yard_point(p.x,p.y),yaw,Vector3((step+.015)/2.39134,1,1))
func run()->void:
	if "--publish-correction" in OS.get_cmdline_user_args():
		var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/plan.json"));var review:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/review.json"))
		check(p.failures==0 and review.failures==0 and review.plan_sha256==FileAccess.get_sha256(OUT+"/plan.json"),"reviewed current courtyard and tower plan")
		check(FileAccess.get_sha256(FORMAL)==p.formal_sha256,"latest formal map unchanged")
		if failures:quit(1);return
		doc=Doc.open_file(FORMAL);doc.records=p.records;doc.map_meta=p.metadata;doc._next=int(p.next)
		check(doc.save(FORMAL)==OK,"native atomic correction save")
		var reopened=Doc.open_file(FORMAL)
		check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"formal map reopens exactly")
		write_report("published.json",{"failures":failures,"sha256":FileAccess.get_sha256(FORMAL),"tower_position":doc._find(SPIRE).position,"props":p.props.size(),"removed":p.removed});quit(failures);return
	if "--save-plan" in OS.get_cmdline_user_args() or "--publish" in OS.get_cmdline_user_args():super.run();return
	DirAccess.make_dir_recursive_absolute(OUT)
	var baseline:=FileAccess.get_sha256(FORMAL)
	var extra:Dictionary=Doc.authoritative_extras(FORMAL).extras
	doc=Doc.new();doc.records=extra.rmmo_records;doc.map_meta=extra.duplicate(true);doc.map_meta.erase("rmmo_records");doc._next=310000
	var original:Array=doc.records.duplicate(true);var metadata:Dictionary=doc.map_meta.duplicate(true)
	doc.checkpoint_recovery()
	var tower:Dictionary=doc._find(SPIRE);check(not tower.get("editor_locked",false),"spire editable")
	var sites:Array=[]
	for at:Vector3 in [Vector3(377,.12,194)]:
		tower.position=B.arr(at)
		if free_site(tower) and absf(ground(doc,at))<.05:sites.append(B.arr(at))
	check(not sites.is_empty(),"deeper left street tower sites clear")
	if sites.is_empty():quit(1);return
	tower.position=sites[0];changed=[SPIRE]
	var h:Dictionary=doc.map_meta.building_instances[HOUSE]
	house_origin=B.vec(h.position);house_yaw=h.yaw;house_basis=Basis(Vector3.UP,deg_to_rad(house_yaw))
	var door:Dictionary=doc.records.filter(func(r):return r.get("building",{}).get("id","")==HOUSE and r.get("fixture",{}).get("id","")=="f0/north/entrance/door")[0]
	gate_x=(house_basis.inverse()*(B.vec(door.position)-house_origin)).x
	props.wall=entry("写实石围墙·1.5米高·2.4米直墙")
	props.gate=entry("写实石立柱·1.95米")
	props.corner=entry("写实石立柱·1.8米")
	props.tree=entry("写实阔叶橡树·宽冠粗干")
	# Replace only the three detached low bank-wall sections of this property.
	removed=["obj_201004","obj_201005","obj_201006"]
	for id:String in removed:
		check(not doc._find(id).get("editor_locked",false),"old wall editable "+id);doc.remove(id)
	# 2.26m clear gateway aligns with the existing entrance, not the road axis.
	for x in [gate_x-1.4,gate_x+1.4]:seated("gate",yard_point(x,-8.8),house_yaw)
	for p:Vector2 in [Vector2(-6.3,-8.8),Vector2(10,-8.8),Vector2(10,9.4),Vector2(-6.3,9.4)]:seated("corner",yard_point(p.x,p.y),house_yaw)
	wall(Vector2(-6.3,-8.8),Vector2(gate_x-1.65,-8.8))
	wall(Vector2(gate_x+1.65,-8.8),Vector2(10,-8.8))
	wall(Vector2(10,-8.8),Vector2(10,9.4))
	wall(Vector2(10,9.4),Vector2(-6.3,9.4))
	wall(Vector2(-6.3,9.4),Vector2(-6.3,-8.8))
	seated("tree",yard_point(8.25,2.8),house_yaw,Vector3.ONE*.75)
	seated("tree",yard_point(7.8,-4.4),house_yaw+180,Vector3.ONE*.6)
	for p:Dictionary in additions:
		var r:Dictionary=doc._find(p.id)
		check(free_site(r),"courtyard clear of roads and unrelated buildings "+p.id)
		check(absf(ground(doc,B.vec(r.position)))<.08,"courtyard founded on bank "+p.id)
	for r:Dictionary in original:
		if r.uuid in removed or r.uuid==SPIRE:continue
		if not equivalent(r,doc._find(r.uuid)):check(false,"unrelated record modified "+r.uuid)
	check(equivalent(metadata,doc.map_meta),"all map metadata preserved")
	var final:Array=doc.records.duplicate(true)
	check(doc.undo() and equivalent(doc.records,original),"single batch undo")
	check(doc.redo() and equivalent(doc.records,final),"single batch redo")
	var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DETAIL_OUT+"/result.json"))
	write_report("plan.json",{"failures":failures,"formal_sha256":baseline,"records":doc.records,"metadata":doc.map_meta,"next":doc._next,"houses":old.houses,"props":additions,"changed":changed,"removed":removed,"tower_sites":sites,"gate_x":gate_x,"bridge_id":old.bridge_id})
	print("COURTYARD_PLAN failures=",failures," additions=",additions.size()," tower_sites=",sites);quit(failures)
