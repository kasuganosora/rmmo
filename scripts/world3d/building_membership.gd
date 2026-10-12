extends RefCounted
## Authority-side CPU catalogue from a COMPLETE, already validated author snapshot.
## Render visibility/cutaway is deliberately not an input to membership.
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Location=preload("res://scripts/world3d/world_location.gd")
const PROTOCOL=1
const CELL_M=32.0

static func digest(value:Variant)->String:
	return JSON.stringify(value,"",true,true).sha256_text()

static func header(record:Dictionary)->Dictionary:
	var result:=record.duplicate(true)
	if result.has("rmmo_state"):
		for key in result.rmmo_state:result[key]=result.rmmo_state[key]
	return result

static func build(meta:Dictionary,bounds_by_uuid:Dictionary={},imported_bounds:Array=[])->Dictionary:
	if not meta.get("rmmo_records") is Array or not Blueprint.valid_meta(meta):return _fail("invalid_author_catalogue")
	var records:Dictionary={};var buildings:Dictionary={};var unknown:Array=imported_bounds.duplicate()
	for raw:Variant in meta.rmmo_records:
		if not raw is Dictionary or not raw.get("uuid") is String or records.has(raw.uuid):return _fail("invalid_member_identity")
		var record:=header(raw)
		for key in ["position","rotation","size"]:
			if not _vector(record.get(key)).is_finite():return _fail("invalid_member_pose")
		records[record.uuid]=record
	for id:String in meta.get("building_instances",{}):
		var instance:Dictionary=meta.building_instances[id]
		var parts:Array=instance.parts.values();parts.sort()
		var complete:=not parts.is_empty();var owned:Dictionary={};var fixtures:Dictionary={}
		var structural:Array=[];var poses:Array=[];var entrance:=false;var conflict:=false
		for part:String in instance.parts:
			var uuid:String=instance.parts[part]
			if not records.has(uuid):complete=false;continue
			var r:Dictionary=records[uuid];var info:Dictionary=r.get("building",{})
			if info.get("id")!=id or info.get("part")!=part:return _fail("building_ownership_mismatch")
			owned[uuid]=true
			var definition:Dictionary=r.get("rmmo_ref",{}).duplicate(true)
			if definition.is_empty():
				definition=r.duplicate(true)
				for field in ["uuid","position","rotation","rmmo_state","building","fixture","editor_group","editor_group_name","editor_name","editor_hidden","editor_locked"]:definition.erase(field)
			var f:Dictionary=r.get("fixture",{}).duplicate(true)
			if not f.is_empty():
				if not Fixtures.valid({"kind":"box","fixture":f}):return _fail("invalid_fixture")
				if fixtures.has(f.id) and fixtures[f.id]!=float(f.open):return _fail("fixture_state_disagrees")
				fixtures[f.id]=float(f.open)
				entrance=entrance or (f.kind=="door" and float(info.get("floor",-1))==0)
				f.erase("open")
			var structural_info:=info.duplicate(true)
			if structural_info.has("floor_y"):structural_info.floor_y=float(structural_info.floor_y)-float(instance.position[1])
			structural.append([uuid,definition,structural_info,f,r.size])
			poses.append([uuid,r.position,r.rotation])
			# A hand-moved member no longer proves the generator's interior volumes.
			var signature:Variant=JSON.parse_string(str(instance.signatures.get(part,"")))
			if not signature is Dictionary:conflict=true
			else:
				for field in ["position","rotation","size"]:
					if not _vector(signature.get(field)).is_equal_approx(_vector(r[field])):conflict=true
		structural.sort_custom(func(a,b):return a[0]<b[0]);poses.sort_custom(func(a,b):return a[0]<b[0])
		var p:=Blueprint.instance_parameters(instance)
		var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(instance.yaw))),_vector(instance.position))
		var base:float=p.get("base_height",0.0) if p.get("layout") in ["townhouse","hall"] else 0.0
		var regions:Array=[]
		for floor_id in int(p.floors):
			var jetty:float=float(p.get("jetty",0.0)) if floor_id>0 else 0.0
			regions.append({"rect":Rect2(-float(p.width)/2,-float(p.depth)/2-jetty,p.width,float(p.depth)+jetty),"bottom":base+floor_id*float(p.floor_height),"top":base+(floor_id+1)*float(p.floor_height),"floor":floor_id})
		if p.get("layout") in ["townhouse","hall"]:
			for annex:Dictionary in preload("res://scripts/world3d/medieval_building.gd").annex_specs(p):
				for floor_id in int(p.get("annex_floors",1)):
					regions.append({"rect":Rect2(annex.center[0]-annex.width/2,annex.center[1]-annex.depth/2,annex.width,annex.depth),"bottom":base+floor_id*float(p.floor_height),"top":base+(floor_id+1)*float(p.floor_height),"floor":floor_id})
		var envelope:=AABB()
		for region:Dictionary in regions:
			var box:=frame*AABB(Vector3(region.rect.position.x,region.bottom-.2,region.rect.position.y),Vector3(region.rect.size.x,region.top-region.bottom+.4,region.rect.size.y))
			envelope=box if envelope.size==Vector3.ZERO else envelope.merge(box)
		for uuid:String in parts:
			if bounds_by_uuid.get(uuid) is AABB:envelope=envelope.merge(bounds_by_uuid[uuid])
			if records.has(uuid) and str(records[uuid].get("building",{}).get("part","")).contains("headhouse"):
				var r:Dictionary=records[uuid]
				var local:Vector3=frame.affine_inverse()*_vector(r.position)
				var bottom:float=base+int(p.floors)*float(p.floor_height)
				var height:float=maxf(.2,local.y+_vector(r.size).y/2-bottom)
				unknown.append(frame*AABB(Vector3(local.x-_vector(r.size).x/2,bottom,local.z-_vector(r.size).z/2),Vector3(_vector(r.size).x,height,_vector(r.size).z)))
		buildings[id]={"instance_id":id,"structure_revision":digest([instance.version,p,structural]),"pose_revision":digest([instance.position,instance.yaw,poses]),"members":parts,"member_set":owned,"fixtures":fixtures,"frame":frame,"regions":regions,"bounds":envelope,"complete":complete,"semantic_ready":complete and entrance and not conflict}
	# Missing ownership or unannotated imported structures can only deny, never
	# grant indoor/outdoor proof. Proven dependency bounds cover hollow meshes too.
	for uuid:String in records:
		var r:Dictionary=records[uuid]
		if r.has("building"):
			if not buildings.has(r.building.id) or not buildings[r.building.id].member_set.has(uuid):return _fail("orphan_building_member")
			continue
		var fort:Dictionary=r.get("fortification",{})
		var tower:bool=str(fort.get("part","")).contains("tower") or str(fort.get("role","")).contains("tower")
		var imported:bool=r.get("kind")=="asset" or r.has("asset_path")
		if tower or imported:
			var bound:Variant=bounds_by_uuid.get(uuid)
			if not bound is AABB:
				if imported:return _fail("unclassified_asset_bounds")
				bound=Transform3D(Basis.from_euler(_vector(r.rotation)*PI/180),_vector(r.position))*AABB(-_vector(r.size)/2,_vector(r.size))
			unknown.append(bound)
	var result:Dictionary={"ok":true,"buildings":buildings,"unknown":unknown,"record_count":records.size()}
	result.spatial=_spatial(result)
	return result

static func _cells(box:AABB,limit:int=4096)->Array:
	var low:=Vector2i(floori(box.position.x/CELL_M),floori(box.position.z/CELL_M))
	var high:=Vector2i(floori(box.end.x/CELL_M),floori(box.end.z/CELL_M))
	if (high.x-low.x+1)*(high.y-low.y+1)>limit:return []
	var cells:Array=[]
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):cells.append(Vector2i(x,z))
	return cells

static func _spatial(catalogue:Dictionary)->Dictionary:
	var result:Dictionary={"cells":{},"global_buildings":[],"global_unknown":[]}
	for id:String in catalogue.buildings:
		var cells:=_cells(catalogue.buildings[id].bounds.grow(.3))
		if cells.is_empty():result.global_buildings.append(id)
		for cell:Vector2i in cells:
			if not result.cells.has(cell):result.cells[cell]={"buildings":[],"unknown":[]}
			result.cells[cell].buildings.append(id)
	for at:int in catalogue.unknown.size():
		var cells:=_cells(catalogue.unknown[at].grow(.15))
		if cells.is_empty():result.global_unknown.append(at)
		for cell:Vector2i in cells:
			if not result.cells.has(cell):result.cells[cell]={"buildings":[],"unknown":[]}
			result.cells[cell].unknown.append(at)
	return result

static func _near(catalogue:Dictionary,clip:AABB)->Dictionary:
	var spatial:Dictionary=catalogue.get("spatial",{})
	if spatial.is_empty():return {"buildings":catalogue.buildings.keys(),"unknown":range(catalogue.unknown.size())}
	var buildings:Dictionary={};var unknown:Dictionary={}
	for id:String in spatial.global_buildings:buildings[id]=true
	for at:int in spatial.global_unknown:unknown[at]=true
	for cell:Vector2i in _cells(clip,64):
		var row:Dictionary=spatial.cells.get(cell,{})
		for id:String in row.get("buildings",[]):buildings[id]=true
		for at:int in row.get("unknown",[]):unknown[at]=true
	return {"buildings":buildings.keys(),"unknown":unknown.keys()}

## This predicts readiness obligations only, never the player's membership.
## Conservative local bounds can prepare an extra building at a rotated corner;
## actual indoor membership still comes exclusively from locate(feet).
static func sweep(catalogue:Dictionary,clip:AABB)->Dictionary:
	if not catalogue.get("ok",false) or not clip.position.is_finite() or not clip.size.is_finite() or not clip.has_volume() or _cells(clip,64).is_empty():return _fail("invalid_sweep")
	var near:=_near(catalogue,clip);var required:Dictionary={}
	for id:String in near.buildings:
		var b:Dictionary=catalogue.buildings[id]
		if not b.semantic_ready:
			if b.bounds.grow(.3).intersects(clip):return _fail("membership_unresolved")
			continue
		var local:AABB=b.frame.affine_inverse()*clip
		for region:Dictionary in b.regions:
			var room:=AABB(Vector3(region.rect.position.x,region.bottom-.15,region.rect.position.y),Vector3(region.rect.size.x,region.top-region.bottom+.15,region.rect.size.y))
			if not room.intersects(local):continue
			var intersection:=room.intersection(local)
			required[id]=b.frame*(intersection.position+intersection.size*.5)
			break
	for at:int in near.unknown:
		if catalogue.unknown[at].grow(.15).intersects(clip):return _fail("membership_unresolved")
	return {"ok":true,"buildings":required,"candidate_count":near.buildings.size()}

static func locate(catalogue:Dictionary,feet:Vector3)->Dictionary:
	if not catalogue.get("ok",false) or not feet.is_finite():return {"membership":"unresolved","reason":"catalogue_unavailable"}
	var hits:Array=[]
	var near:=_near(catalogue,AABB(feet,Vector3(.001,.001,.001)))
	for id:String in near.buildings:
		var b:Dictionary=catalogue.buildings[id]
		var point:Vector3=b.frame.affine_inverse()*feet
		if not b.semantic_ready and b.bounds.grow(.3).has_point(feet):return {"membership":"unresolved","reason":"building_semantics_unavailable","instance_id":id}
		for region:Dictionary in b.regions:
			if point.y<region.bottom-.15 or point.y>=region.top:continue
			# Walls and the actual doorway threshold use conservative indoor demand.
			# Yards, balconies, roof terraces and space below a jetty stay outside.
			if region.rect.has_point(Vector2(point.x,point.z)):
				hits.append({"membership":"indoor","instance_id":id,"floor":region.floor});break
	if hits.size()>1:return {"membership":"unresolved","reason":"overlapping_interiors"}
	if hits.size()==1:return hits[0]
	for at:int in near.unknown:
		var bound:AABB=catalogue.unknown[at]
		if bound.grow(.15).has_point(feet):return {"membership":"unresolved","reason":"unannotated_structure"}
	return {"membership":"outdoor"}

static func _vector(value:Variant)->Vector3:
	if value is Vector3:return value
	if value is Array and value.size()==3:
		for number:Variant in value:
			if not number is int and not number is float:return Vector3(NAN,NAN,NAN)
		return Vector3(value[0],value[1],value[2])
	return Vector3(NAN,NAN,NAN)

static func _fail(reason:String)->Dictionary:return {"ok":false,"reason":reason}
