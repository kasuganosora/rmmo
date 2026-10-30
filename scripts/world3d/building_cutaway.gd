extends RefCounted
## Per-camera presentation only. Never edits records, collision layers or navmesh.
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const CELL:=32.0
static var incremental_catalog_enabled:=true # Diagnostic legacy-work control.
var map_root:Node
var buildings:Dictionary={}
var _part_buildings:Dictionary={}
var index:Dictionary={}
var hidden:Dictionary={}
var excluded:Array[RID]=[]
var enabled:=false
var active_key:=""
var clear_time:=0.0
var target_cache:Dictionary={}
var applied_key:=""
var applied_revision:=-1

func _instances(root:Node)->Dictionary:
	return _instances_for(root,{})

func _instances_for(root:Node,wanted:Dictionary)->Dictionary:
	var meta:Dictionary=preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root)
	var native:Dictionary=meta.get("building_instances",{})
	var result:Dictionary={}
	if wanted.is_empty():result=native.duplicate()
	else:
		for id:String in wanted:
			if native.has(id):result[id]=native[id]
	var author:Dictionary=root.get_meta("author_reference_extras",meta)
	# The mounted package producer already owns the authored model contract.
	# A camera needs rooms/poses, not a repeated audit of thousands of members.
	var trusted:bool=incremental_catalog_enabled and root.has_meta("source_map_sha256") and root.has_meta("author_reference_extras") and preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	for raw:Dictionary in author.get("rmmo_records",[]):
		var state:Dictionary=raw.get("rmmo_state",{})
		if incremental_catalog_enabled:
			if not raw.has("model_building") and not state.has("model_building"):continue
			if not wanted.is_empty() and not wanted.has(str(state.get("uuid",raw.get("uuid","")))):continue
		var record:Dictionary=raw.duplicate();record.merge(state,true)
		if record.has("model_building") and (trusted or preload("res://scripts/world3d/imported_building.gd").valid_record(record)):result[str(record.uuid)]={"imported_record":record}
	return result

func bind(root:Node)->void:
	restore();map_root=root;buildings.clear();index.clear();target_cache.clear();_part_buildings.clear()
	if not is_instance_valid(root):return
	var meta:Dictionary=preload("res://scripts/world3d/gltf_map_io.gd").extras_of(root)
	var instances:=_instances(root)
	for id:String in instances:_sync_building(id,instances[id])
	var shared:Variant=instances if incremental_catalog_enabled else null
	append_records(root,meta.get("rmmo_records",[]),shared)
	# Imported author records describe the whole resource. Its already loaded
	# presentation members are in the streaming library, including on a rebind.
	append_specs(root,root.get_meta("stream_library",[]),shared)

func append_specs(root:Node,specs:Array,catalog:Variant=null)->void:
	if root!=map_root or not is_instance_valid(map_root):return
	var records:Array=[]
	for spec:Dictionary in specs:
		var record:Dictionary=spec.get("ground_batch_record",{})
		var extra:Dictionary=spec.get("extras",{})
		# Lights, transparent pieces and authored LODs may not be batch candidates.
		# Membership is independent of batching and uses their actual world box.
		if extra.has("building") and spec.get("mesh") is Mesh and spec.get("transform") is Transform3D:
			var bounds:AABB=spec.transform*spec.mesh.get_aabb()
			var center:=bounds.get_center();var size:=bounds.size
			record={"uuid":str(spec.uuid),"building":extra.building,"position":[center.x,center.y,center.z],"size":[size.x,size.y,size.z]}
		if record.has("building"):records.append(record)
	append_records(root,records,catalog)

func append_records(root:Node,records:Array,catalog:Variant=null)->void:
	if root!=map_root or not is_instance_valid(map_root) or records.is_empty():return
	var instances:Dictionary
	if catalog is Dictionary:instances=catalog
	elif incremental_catalog_enabled:
		var wanted:Dictionary={}
		for record:Dictionary in records:
			var id:=str(record.get("building",{}).get("id",""))
			if not id.is_empty():wanted[id]=true
		if wanted.is_empty():return
		instances=_instances_for(root,wanted)
	else:instances=_instances(root)
	var changed:Dictionary={};var touched:Dictionary={}
	for record:Dictionary in records:
		var id:=str(record.get("building",{}).get("id",""))
		if not instances.has(id):continue
		if not touched.has(id):
			if _sync_building(id,instances[id]):changed[id]=true
			touched[id]=true
		var uuid:=str(record.uuid)
		var previous_id:=str(_part_buildings.get(uuid,""))
		if not previous_id.is_empty() and previous_id!=id:
			if buildings.has(previous_id):
				_restore_parts([uuid]);buildings[previous_id].parts.erase(uuid);changed[previous_id]=true
		# Keep only presentation data, never another retained frozen geometry blob.
		var part:={"position":record.position,"size":record.size,"building":record.building}
		if buildings[id].parts.get(uuid,{})==part:continue
		buildings[id].parts[uuid]=part.duplicate(true);_part_buildings[uuid]=id;changed[id]=true
	for id:String in changed:
		_refresh_headhouse(id);_invalidate_building(id)

func remove_specs(root:Node,specs:Array)->void:
	var ids:Array=[]
	for spec:Dictionary in specs:ids.append(str(spec.get("uuid","")))
	remove_uuids(root,ids)

func remove_uuids(root:Node,ids:Array)->void:
	if root!=map_root or not is_instance_valid(map_root):return
	var changed:Dictionary={}
	for uuid:String in ids:
		var id:=str(_part_buildings.get(uuid,""))
		if id.is_empty() or not buildings.has(id):continue
		_restore_parts([uuid]);buildings[id].parts.erase(uuid);_part_buildings.erase(uuid);changed[id]=true
	for id:String in changed:
		_invalidate_building(id)
		if buildings[id].parts.is_empty():
			_remove_cells(id);buildings.erase(id)
		else:_refresh_headhouse(id)

func _sync_building(id:String,instance:Dictionary)->bool:
	if instance.has("imported_record"):return _sync_imported(id,instance.imported_record)
	var header:={"parameters":instance.parameters,"position":instance.position,"yaw":instance.yaw,"version":instance.get("version",1)}
	if buildings.has(id) and buildings[id].header==header:return false
	var parts:Dictionary=buildings[id].parts if buildings.has(id) else {}
	if buildings.has(id):_remove_cells(id)
	var p:=Blueprint.instance_parameters(instance)
	var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(instance.yaw)),Blueprint.vec(instance.position))
	var regions:Array=[Rect2(-p.width/2,-p.depth/2-float(p.get("jetty",0)),p.width,p.depth+float(p.get("jetty",0)))]
	if p.get("layout") in ["townhouse","hall"]:
		for annex:Dictionary in preload("res://scripts/world3d/medieval_building.gd").annex_specs(p):
			regions.append(Rect2(annex.center[0]-annex.width/2,annex.center[1]-annex.depth/2,annex.width,annex.depth))
	var cells:Dictionary={}
	for rect:Rect2 in regions:
		var bounds:AABB=frame*AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,1,rect.size.y))
		for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
			for z in range(floori(bounds.position.z/CELL),floori(bounds.end.z/CELL)+1):
				var key:=Vector2i(x,z);cells[key]=true
				if not index.has(key):index[key]=[]
				if not index[key].has(id):index[key].append(id)
	buildings[id]={"parameters":p,"frame":frame,"regions":regions,"parts":parts,"headhouse":{},"cells":cells,"header":header.duplicate(true)}
	return true

func _sync_imported(id:String,record:Dictionary)->bool:
	var Imported=preload("res://scripts/world3d/imported_building.gd")
	# Member annotations arrive through append_specs. They do not change room
	# cells; retaining/copying them here also duplicates a potentially huge table.
	var header:={"regions":record.model_building.regions,"position":record.position,"rotation":record.rotation,"size":record.size} if incremental_catalog_enabled else {"model_building":record.model_building,"position":record.position,"rotation":record.rotation,"size":record.size}
	if buildings.has(id) and buildings[id].header==header:return false
	var parts:Dictionary=buildings[id].parts if buildings.has(id) else {}
	if buildings.has(id):_remove_cells(id)
	var frame:Transform3D=Imported.frame(record)
	var rooms:Array=Imported.regions(record);var cells:Dictionary={}
	rooms.sort_custom(func(a,b):return a.bottom>b.bottom)
	for room:Dictionary in rooms:
		var bounds:AABB=frame*AABB(Vector3(room.rect.position.x,room.bottom,room.rect.position.y),Vector3(room.rect.size.x,room.top-room.bottom,room.rect.size.y))
		for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
			for z in range(floori(bounds.position.z/CELL),floori(bounds.end.z/CELL)+1):
				var key:=Vector2i(x,z);cells[key]=true
				if not index.has(key):index[key]=[]
				if not index[key].has(id):index[key].append(id)
	buildings[id]={"parameters":{},"frame":frame,"regions":[],"authored_regions":rooms,"parts":parts,"headhouse":{},"cells":cells,"header":header.duplicate(true)}
	return true

func _remove_cells(id:String)->void:
	for key:Vector2i in buildings[id].cells:
		index[key].erase(id)
		if index[key].is_empty():index.erase(key)

func _refresh_headhouse(id:String)->void:
	var b:Dictionary=buildings[id];b.headhouse={}
	for uuid:String in b.parts:
		var record:Dictionary=b.parts[uuid]
		if record.building.get("part","")!="roof/headhouse/ceiling":continue
		var center:Vector3=b.frame.affine_inverse()*Blueprint.vec(record.position)
		var size:=Blueprint.vec(record.size)
		b.headhouse={"rect":Rect2(center.x-size.x/2,center.z-size.z/2,size.x,size.z),"top":center.y-size.y/2,"ceiling_id":uuid}
		break

func _key_owner(key:String)->String:
	return key.left(key.rfind(":")) if key.contains(":") else ""

func _invalidate_building(id:String)->void:
	for key:String in target_cache.keys():
		if _key_owner(key)==id:target_cache.erase(key)
	if _key_owner(applied_key)==id or _key_owner(active_key)==id:
		_restore_parts(buildings[id].parts.keys());active_key="";applied_key="";applied_revision=-1

func _restore_parts(ids:Array)->void:
	var remaining:Dictionary={}
	for uuid:String in hidden:remaining[uuid]=true
	for uuid:String in ids:remaining.erase(uuid)
	if remaining.size()!=hidden.size():apply_hidden(remaining)

func locate(feet:Vector3)->Dictionary:
	for id:String in index.get(Vector2i(floori(feet.x/CELL),floori(feet.z/CELL)),[]):
		var b:Dictionary=buildings[id];var p:Dictionary=b.parameters
		var at:Vector3=b.frame.affine_inverse()*feet
		if b.has("authored_regions"):
			for room:Dictionary in b.authored_regions:
				if at.y>=room.bottom-.15 and at.y<room.top and room.rect.grow(-.12).has_point(Vector2(at.x,at.z)):
					return {"id":id,"floor":room.floor,"key":id+":"+str(room.floor)+"_"+str(room.id).sha256_text().substr(0,8),"ceiling_y":(b.frame*Vector3(at.x,room.top,at.z)).y}
			continue
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
	if not enabled or room.is_empty() or not is_instance_valid(map_root) or not buildings.has(room.id):restore();return
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
	if b.has("authored_regions") and first_info.get("role") in ["roof","ceiling"]:
		blocked=not first.is_empty() and float(first.position[1])>focus.y+.25
	if not blocked:restore();return
	active_key=room.key;clear_time=0
	if not target_cache.has(room.key):
		var targets:Dictionary={}
		for id:String in b.parts:
			var record:Dictionary=b.parts[id];var info:Dictionary=record.get("building",{})
			if int(info.get("floor",0))>room.floor:targets[id]=true
			elif info.get("role")=="roof" and float(record.position[1])>=float(room.ceiling_y)-.3:targets[id]=true
			elif b.has("authored_regions") and info.get("role")=="ceiling" and float(record.position[1])>focus.y+.25:targets[id]=true
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
