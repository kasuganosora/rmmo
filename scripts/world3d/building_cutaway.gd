extends RefCounted
## Per-camera presentation only. Never edits records, collision layers or navmesh.
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const CELL:=32.0
var map_root:Node
var buildings:Dictionary={}
var index:Dictionary={}
var hidden:Dictionary={}
var excluded:Array[RID]=[]
var enabled:=false
var active_key:=""
var clear_time:=0.0
var target_cache:Dictionary={}
var applied_key:=""
var applied_revision:=-1

func bind(root:Node)->void:
	restore();map_root=root;buildings.clear();index.clear();target_cache.clear()
	if not is_instance_valid(root):return
	var meta:Dictionary=preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root)
	var records:Dictionary={}
	for record:Dictionary in meta.get("rmmo_records",[]):records[str(record.uuid)]=record
	for id:String in meta.get("building_instances",{}):
		var instance:Dictionary=meta.building_instances[id]
		var p:=Blueprint.instance_parameters(instance)
		var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(instance.yaw)),Blueprint.vec(instance.position))
		var regions:Array=[Rect2(-p.width/2,-p.depth/2-float(p.get("jetty",0)),p.width,p.depth+float(p.get("jetty",0)))]
		if p.get("layout") in ["townhouse","hall"]:
			for annex:Dictionary in preload("res://scripts/world3d/medieval_building.gd").annex_specs(p):
				regions.append(Rect2(annex.center[0]-annex.width/2,annex.center[1]-annex.depth/2,annex.width,annex.depth))
		var parts:Dictionary={}
		for uuid:String in instance.parts.values():
			if records.has(uuid):parts[uuid]=records[uuid]
		var headhouse:Dictionary={}
		for uuid:String in parts:
			var record:Dictionary=parts[uuid]
			if record.building.part!="roof/headhouse/ceiling":continue
			var center:Vector3=frame.affine_inverse()*Blueprint.vec(record.position)
			var size:=Blueprint.vec(record.size)
			headhouse={"rect":Rect2(center.x-size.x/2,center.z-size.z/2,size.x,size.z),"top":center.y-size.y/2,"ceiling_id":uuid}
		buildings[id]={"parameters":p,"frame":frame,"regions":regions,"parts":parts,"headhouse":headhouse}
		for rect:Rect2 in regions:
			var bounds: AABB=frame*AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,1,rect.size.y))
			for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
				for z in range(floori(bounds.position.z/CELL),floori(bounds.end.z/CELL)+1):
					var key:=Vector2i(x,z)
					if not index.has(key):index[key]=[]
					if not index[key].has(id):index[key].append(id)

func locate(feet:Vector3)->Dictionary:
	for id:String in index.get(Vector2i(floori(feet.x/CELL),floori(feet.z/CELL)),[]):
		var b:Dictionary=buildings[id];var p:Dictionary=b.parameters
		var at:Vector3=b.frame.affine_inverse()*feet
		if at.y<-.15:continue
		var base:float=p.get("base_height",0.0) if p.get("layout") in ["townhouse","hall"] else 0.0
		var floor_id:=maxi(0,floori((at.y-base+.08)/float(p.floor_height)))
		var head:Dictionary=b.headhouse
		if floor_id==int(p.floors) and not head.is_empty() and at.y<head.top and head.rect.grow(-.12).has_point(Vector2(at.x,at.z)):
			return {"id":id,"floor":floor_id,"key":id+":headhouse","ceiling_y":b.frame.origin.y+head.top,"ceiling_id":head.ceiling_id}
		for i:int in b.regions.size():
			# Exclude yards, balconies, the open roof terrace and upper-storey jetty
			# space at street level. Attached wings use their own occupied storeys.
			var rect:Rect2=b.regions[i]
			if i==0 and floor_id==0:rect=Rect2(-p.width/2,-p.depth/2,p.width,p.depth)
			if floor_id >= (int(p.floors) if i==0 else int(p.get("annex_floors",1))):continue
			if rect.grow(-.12).has_point(Vector2(at.x,at.z)):
				return {"id":id,"floor":floor_id,"key":id+":"+str(floor_id),"ceiling_y":b.frame.origin.y+base+(floor_id+1)*p.floor_height}
	return {}

func update(room:Dictionary,focus:Vector3,wanted:Vector3,space:PhysicsDirectSpaceState3D,ignore:Array[RID],delta:float)->void:
	if not enabled or room.is_empty() or not is_instance_valid(map_root):restore();return
	var query:=PhysicsRayQueryParameters3D.create(wanted,focus)
	query.exclude=ignore;query.collide_with_areas=false;query.hit_from_inside=true
	# Always query the full physical building, including currently hidden slabs.
	# Querying only visible meshes would toggle hiding on/off every frame.
	var hit:=space.intersect_ray(query)
	var b:Dictionary=buildings[room.id]
	var first_id:String=preload("res://scripts/world3d/fortification_collision_batcher.gd").hit_uuid(hit)
	var first:Dictionary=b.parts.get(first_id,{})
	var first_info:Dictionary=first.get("building",{})
	# Only the first camera-to-person obstruction counts. Walls, props, stairs,
	# gables and other buildings never trigger a cutaway, even with a slab behind.
	var ceiling:bool=first_info.get("role")=="floor" or str(first_info.get("part","")).ends_with("/ceiling")
	var blocked:bool=ceiling and (int(first_info.get("floor",0))>room.floor or first_id==room.get("ceiling_id","_none"))
	if not blocked:restore();return
	active_key=room.key;clear_time=0
	if not target_cache.has(room.key):
		var targets:Dictionary={}
		for id:String in b.parts:
			var record:Dictionary=b.parts[id];var info:Dictionary=record.get("building",{})
			if int(info.get("floor",0))>room.floor:targets[id]=true
			elif info.get("role")=="roof" and float(record.position[1])>=float(room.ceiling_y)-.3:targets[id]=true
			elif id==room.get("ceiling_id",""):targets[id]=true
		target_cache[room.key]=targets
	var revision:int=map_root.get_meta("stream_visibility_revision",0)
	if applied_key==room.key and applied_revision==revision:return
	apply_hidden(target_cache[room.key]);applied_key=room.key;applied_revision=revision

func apply_hidden(targets:Dictionary)->void:
	for id:String in hidden.keys():
		if targets.has(id):continue
		var previous:Dictionary=hidden[id];var mesh=previous.node.get_ref()
		if is_instance_valid(mesh):mesh.visible=previous.visible
		hidden.erase(id)
	excluded.clear()
	if not is_instance_valid(map_root):return
	var meshes:Dictionary=map_root.get_meta("stream_meshes",{})
	var bodies:Dictionary=map_root.get_meta("stream_bodies",{})
	for id:String in targets:
		var mesh=meshes.get(id)
		if is_instance_valid(mesh):
			if not hidden.has(id) or hidden[id].node.get_ref()!=mesh:hidden[id]={"node":weakref(mesh),"visible":mesh.visible}
			mesh.visible=false
		var body=bodies.get(id)
		if is_instance_valid(body):excluded.append(body.get_rid())

func restore()->void:
	if not hidden.is_empty() or not excluded.is_empty():apply_hidden({})
	active_key="";clear_time=0;applied_key="";applied_revision=-1
