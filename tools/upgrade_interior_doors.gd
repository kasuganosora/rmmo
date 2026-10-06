extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const P=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const FORMAL="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const TARGET="D:/code/rmmo_runtime/cache/world3d/interior_door_review/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/interior_timber_door"
const ASSET="D:/code/rmmo_runtime/assets/interior_timber_door/interior_timber_door_mesh.json"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	if not ok:failures+=1;push_error(label_)
func key(a:Vector3,b:Vector3,c:Vector3)->String:
	var points:Array=[]
	for p in [a,b,c]:points.append(str(Vector3i((p*1000).round())))
	points.sort();return str(points)
func triangle_set(mesh:Mesh,pose:Transform3D)->Dictionary:
	var result:Dictionary={};var points:PackedVector3Array=pose*Cpu.capture(mesh).collision_faces()
	for i in range(0,points.size(),3):
		if (points[i+1]-points[i]).cross(points[i+2]-points[i]).length_squared()<1e-14:continue
		result[key(points[i],points[i+1],points[i+2])]=[points[i],points[i+1],points[i+2]]
	return result
func revise(source:Mesh,offset:Vector3,remove:Dictionary,add:Array)->Dictionary:
	var result:=Cpu.new();result.bounds=source.get_aabb();var removed:=0
	# Frozen render vertices were quantized relative to the group's centre.
	# Match within 150 micrometres instead of relying on rounding at bin edges.
	var buckets:Dictionary={};var nearest:Dictionary={}
	for triangle:Array in remove.values():
		var cell:=Vector3i(((triangle[0]+triangle[1]+triangle[2])/3.0*100).floor())
		for x in range(-1,2):
			for y in range(-1,2):
				for z in range(-1,2):
					var bucket:=cell+Vector3i(x,y,z)
					if not buckets.has(bucket):buckets[bucket]=[]
					buckets[bucket].append(triangle)
	for slot in source.get_surface_count():
		var a:Array=source.surfaces[slot].duplicate(true);var points:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array(range(points.size()))
		var keep:=PackedInt32Array()
		for i in range(0,indices.size(),3):
			var triangle:Array=[points[indices[i]]+offset,points[indices[i+1]]+offset,points[indices[i+2]]+offset]
			var cell:=Vector3i(((triangle[0]+triangle[1]+triangle[2])/3.0*100).floor());var matched:=false
			for expected:Array in buckets.get(cell,[]):
				var error:=0.0
				for v:Vector3 in triangle:
					var distance:=INF
					for p:Vector3 in expected:distance=minf(distance,v.distance_to(p))
					error=maxf(error,distance)
				var identity:=key(expected[0],expected[1],expected[2]);nearest[identity]=minf(nearest.get(identity,INF),error)
				if error<.00015:matched=true;break
			if matched:removed+=1
			else:keep.append_array(indices.slice(i,i+3))
		if keep.is_empty():continue
		a[Mesh.ARRAY_INDEX]=keep;result.surfaces.append(a);result.materials.append(source.surface_get_material(slot))
	for row:Dictionary in add:
		for slot in row.mesh.get_surface_count():
			var a:Array=row.mesh.surfaces[slot].duplicate(true)
			a[Mesh.ARRAY_VERTEX]=Transform3D(Basis.IDENTITY,row.position-offset)*a[Mesh.ARRAY_VERTEX]
			result.surfaces.append(a);result.materials.append(row.mesh.surface_get_material(slot))
	if "--debug" in OS.get_cmdline_user_args():
		var errors:Array=nearest.values();errors.sort();print("MATCH_ERRORS ",errors.slice(maxi(0,errors.size()-30)));print("MISSING ",remove.size()-nearest.size())
	return {"mesh":result,"removed":removed}
func store_geometry(record:Dictionary,mesh:Mesh,solid:Mesh)->void:
	var cache:Dictionary={};cache[[0]]={"mesh":mesh,"source":solid}
	var data:=Cook.pack(cache,"","house_prefab_v1");P.compact_data(data)
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	record.prefab_materials=[]
	for material:Dictionary in data.materials:
		if material.has("paint") and not record.prefab_materials.has(material.paint):record.prefab_materials.append(material.paint)
	check(P.valid(record),"valid repaired static prefab")
func run()->void:
	if "--publish" in OS.get_cmdline_user_args():
		var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/upgrade.json"))
		var physical:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/physical.json"))
		check(report.failures==0 and FileAccess.get_sha256(FORMAL)==report.baseline and FileAccess.get_sha256(TARGET)==report.candidate,"unchanged baseline and candidate")
		check(physical.failures==0 and physical.candidate==report.candidate and physical.doors==report.doors and report.asset==FileAccess.get_sha256(ASSET),"current asset and physical acceptance")
		if failures:quit(1);return
		var doc=Doc.open_file(FORMAL);var candidate=Doc.open_file(TARGET);doc.records=candidate.records;doc.map_meta=candidate.map_meta
		check(doc.save(FORMAL)==OK,"native publication");var reopened=Doc.open_file(FORMAL);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"published ownership reopens")
		print("INTERIOR_PUBLISHED failures=",failures);quit(1 if failures else 0);return
	var baseline:=FileAccess.get_sha256(FORMAL);var doc=Doc.open_file(FORMAL);var original:Array=doc.records.duplicate(true)
	var total:=0;var changed:Dictionary={};var models:=Doc.new()
	for id:String in doc.map_meta.building_instances:
		var instance:Dictionary=doc.map_meta.building_instances[id];var plan:=B.generate(instance.parameters)
		check(plan.ok,"valid source "+id);if not plan.ok:continue
		var yaw:=Basis(Vector3.UP,deg_to_rad(instance.yaw));var origin:=B.vec(instance.position);var groups:Dictionary={}
		for swap:Dictionary in plan.interior_door_replacements:
			var found:Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==id and r.get("fixture",{}).get("id")==swap.id)
			check(found.size()==1,"one existing leaf "+id+" "+swap.id);if found.size()!=1:continue
			var record:Dictionary=found[0];check(not record.get("locked",false),"unlocked leaf");if record.get("locked",false):continue
			var frozen:=P.bake([swap.leaf]);check(frozen.ok,"bake approved leaf");if not frozen.ok:continue
			var replacement:Dictionary=frozen.records[0]
			replacement.position=B.arr(origin+yaw*B.vec(replacement.position));replacement.rotation=B.arr(yaw.get_euler()*180/PI)
			replacement.uuid=record.uuid;replacement.building=record.building.duplicate(true);replacement.fixture.open=record.fixture.open
			for field in ["editor_group","editor_group_name","editor_name","locked","hidden"]:
				if record.has(field):replacement[field]=record[field]
			changed[record.uuid]=true;record.clear();record.merge(replacement);instance.signatures[record.building.part]=B.geometry_signature(record);total+=1
			var section:String=swap.frame.building.part.get_slice("/",0)
			if section not in ["wing","wing_left","wing_right","workshop","yard"]:section="main"
			var group:=str([section,swap.frame.building.floor])
			if not groups.has(group):groups[group]={"section":section,"floor":swap.frame.building.floor,"floor_y":swap.frame.building.floor_y,"remove":{},"collision":{},"add":[],"solid_add":[]}
			var g:Dictionary=groups[group]
			for old:Dictionary in swap.old:
				if old.has("fixture"):continue
				var node:=models._mesh(old);var pose:Transform3D=node.transform
				g.remove.merge(triangle_set(node.mesh,pose))
				if old.get("collision","block")!="none":g.collision.merge(triangle_set(node.get_meta("collision_solid",node.mesh),pose))
				node.free()
			var frame:=P.bake([swap.frame]);check(frame.ok,"bake approved frame");if not frame.ok:continue
			var entry:=P.geometry(frame.records[0]);var at:=B.vec(frame.records[0].position)
			g.add.append({"mesh":entry.mesh,"position":at});g.solid_add.append({"mesh":entry.source,"position":at})
		for group:String in groups:
			var g:Dictionary=groups[group]
			var found:Array=doc.records.filter(func(r):return r.get("building",{}).get("id")==id and not r.has("fixture") and r.has("house_prefab") and r.building.floor==g.floor and is_equal_approx(r.building.floor_y,g.floor_y) and r.building.part.begins_with(g.section+"/baked_") and r.building.role=="shell" and not r.building.part.ends_with("/ceiling"))
			check(found.size()==1,"unique static floor shell "+group);if found.size()!=1:continue
			var record:Dictionary=found[0];check(not record.get("locked",false),"unlocked shell");if record.get("locked",false):continue
			var offset:=yaw.inverse()*(B.vec(record.position)-origin);var old:=P.geometry(record)
			var render:=revise(old.mesh,offset,g.remove,g.add);var solid:=revise(old.source,offset,g.collision,g.solid_add)
			check(render.removed==g.remove.size(),"all old frame/hardware faces removed %d/%d"%[render.removed,g.remove.size()])
			check(solid.removed==g.collision.size(),"all old frame collisions removed %d/%d"%[solid.removed,g.collision.size()])
			store_geometry(record,render.mesh,solid.mesh);changed[record.uuid]=true;instance.signatures[record.building.part]=B.geometry_signature(record)
		print("INTERIOR_HOUSE ",id," total=",total)
		if "--debug" in OS.get_cmdline_user_args():quit();return
	check(total>0 and doc.records.size()==original.size(),"door count and component count")
	for i in original.size():
		if not changed.has(original[i].uuid):check(original[i]==doc.records[i],"unrelated geometry untouched")
	check(B.valid_ownership(doc.map_meta,doc.records),"ownership remains valid")
	if not failures:
		check(doc.save(TARGET)==OK,"candidate native save");var reopened=Doc.open_file(TARGET);check(reopened!=null and B.valid_ownership(reopened.map_meta,reopened.records),"candidate reopens")
	var report:={"baseline":baseline,"candidate":FileAccess.get_sha256(TARGET),"asset":FileAccess.get_sha256(ASSET),"doors":total,"records":changed.size(),"failures":failures}
	var file:=FileAccess.open(OUT+"/upgrade.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("INTERIOR_UPGRADE ",JSON.stringify(report));quit(1 if failures else 0)
