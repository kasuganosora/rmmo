extends "res://tools/test_world3d_mcp.gd"
## Three published imported buildings, in one isolated native transaction.
## Default is a full in-memory preflight. --apply writes only an explicitly
## SHA-pinned cache candidate; never the formal town. --check-inputs is read-only.
## Reads the latest handoff.formal_publications receipts directly. Optional
## --publications bundle may pin them further, but cannot replace their identity.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")
const Bounds=preload("res://scripts/world3d/asset_bounds_manifest.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const FORMAL="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const ASSET_ROOT="D:/code/rmmo_runtime/packs/default/assets"
const KEYS=["guardhouse","church","watermill"]
var target:="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf"
var output:=OUT+"/functional_buildings_apply.json"
var bundle_path:=""
var grass_moves_path:=""
var expected_sha:=""
var apply_requested:=false
var inputs_only:=false
var inputs:Dictionary={}
var report:Dictionary={"saved":false,"phase":"inputs","operations":[],"placements":[],"support":[],"outdoor_access":[],"blocking_findings":[]}
var handoff:Dictionary={}
var sites:Dictionary={}
var church:Dictionary={}
var sources:Dictionary={}
var before:Dictionary={}
var check_count:=0
var grass_plan:Dictionary={}
const HANDOFF=OUT+"/blender_building_handoff.json"

static func scoped_handoff(value:Dictionary)->Dictionary:
	# The same work handoff also tracks changing market assets. Keep only the
	# three authoritative publication entries and the geometry anchors we use.
	var result:Dictionary={"schema":1,"formal_publications":{},"designs":{}}
	for key:String in KEYS:
		result.formal_publications[key]=value.get("formal_publications",{}).get(key,{}).duplicate(true)
		var d:Dictionary=value.get("designs",{}).get(key,{})
		if key=="church":result.designs[key]={"source":{"sha256":d.get("source",{}).get("sha256","")},"entrances":d.get("entrances",[]).duplicate(true)}
		elif key=="guardhouse":result.designs[key]={"candidate":{"sha256":d.get("candidate",{}).get("sha256","")},"main_entrance":d.get("main_entrance",{}).duplicate(true)}
		else:result.designs[key]={"candidate_glb":{"sha256":d.get("candidate_glb",{}).get("sha256","")},"front_door":d.get("front_door",{}).duplicate(true),"waterwheel":d.get("waterwheel",{}).duplicate(true),"river_foundation":d.get("river_foundation",{}).duplicate(true)}
	return result

func freeze_building_inputs()->void:
	var bytes:=FileAccess.get_file_as_bytes(HANDOFF)
	var live:Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not live is Dictionary:fail_detail("Latest building handoff is missing or invalid");return
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	report.handoff_observation={"path":HANDOFF,"sha256":hash.finish().hex_encode(),"scope":"observation only; unrelated market fields may change"}
	handoff=scoped_handoff(live)
	var content:=JSON.stringify(handoff,"\t");var sha:=content.sha256_text();var path:=OUT+"/functional_inputs/"+sha+".json"
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file:=FileAccess.open(path+".pending",FileAccess.WRITE)
		if file==null:fail_detail("Cannot create immutable three-building input");return
		file.store_string(content);file.close()
		check(Atomic.publish(path+".pending",path)==OK,"immutable three-building input published")
	if not pin(path,sha):return
	report.building_inputs={"path":path,"sha256":sha,"scope_token":City.token(handoff)}

func verify_live_building_inputs()->void:
	var live:Variant=JSON.parse_string(FileAccess.get_file_as_string(HANDOFF))
	check(live is Dictionary and City.token(scoped_handoff(live))==City.token(handoff),"three building publications and used anchors remain unchanged; unrelated handoff fields ignored")

func check(ok:bool,label:String)->void:
	check_count+=1;super.check(ok,label)

func canon(path:String)->String:return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().to_lower()
func identity(snapshot:Dictionary)->Dictionary:return {"records":snapshot.records,"map_meta":snapshot.map_meta}
func fail_detail(label:String,details:Dictionary={})->void:
	check(false,label);report.blocking_findings.append({"problem":label,"details":details})
func pin(path:String,sha:String="")->bool:
	if path.is_empty() or not FileAccess.file_exists(path):fail_detail("Required evidence missing",{"path":path});return false
	var actual:=FileAccess.get_sha256(path)
	if not sha.is_empty() and actual!=sha:fail_detail("Evidence SHA changed",{"path":path,"expected":sha,"actual":actual});return false
	if inputs.has(path) and inputs[path]!=actual:fail_detail("Evidence changed during transaction",{"path":path});return false
	inputs[path]=actual;return true
func read(path:String)->Dictionary:
	if not pin(path):return {}
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:fail_detail("Expected JSON object",{"path":path});return {}
	return value
func persist()->void:
	report.failures=failed;report.checks=check_count;report.inputs=inputs;report.apply=apply_requested
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var pending:=output+".pending";var file:=FileAccess.open(pending,FileAccess.WRITE)
	if file==null:push_error("Cannot write functional building receipt");return
	file.store_string(JSON.stringify(report,"\t"));file.close();Atomic.publish(pending,output)
func stop()->bool:
	if failed==0:return false
	report.phase="failed_after_candidate_save" if report.saved else "blocked_without_candidate_save";persist()
	if is_instance_valid(editor) and editor._mcp!=null:editor._mcp.stop()
	quit(1);return true
func operation(name_:String,args:Dictionary)->Dictionary:
	report.phase=name_;persist();var result:=await call_tool(name_,args)
	report.operations.append({"tool":name_,"request":args,"result":result})
	if not result.get("ok",false):report.blocking_findings.append({"problem":"Native "+name_+" rejected","details":result})
	persist();return result
func latest_digest(key:String)->String:
	var design:Dictionary=handoff.get("designs",{}).get(key,{})
	if key=="church":return str(design.get("source",{}).get("sha256",""))
	if key=="guardhouse":return str(design.get("candidate",{}).get("sha256",""))
	return str(design.get("candidate_glb",{}).get("sha256",""))
func publication_header_valid(value:Dictionary)->bool:
	return value.get("ok",false)==true and value.get("completed",false)==true and value.get("failures",["missing"])==[] and value.get("items",[]).size()==1
func source_json(path:String)->Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_32()!=0x46546c67 or file.get_32()!=2:return {}
	file.get_32();var length:=file.get_32()
	if file.get_32()!=0x4e4f534a or length>4*1024*1024:return {}
	var data:Variant=JSON.parse_string(file.get_buffer(length).get_string_from_utf8());file.close()
	return data if data is Dictionary else {}
func prepare_inputs()->void:
	freeze_building_inputs();sites=read(OUT+"/functional_building_sites.json");church=read(OUT+"/church_north_reserved_site.json")
	var bundle:Dictionary={}
	if not bundle_path.is_empty():bundle=read(bundle_path)
	if not grass_moves_path.is_empty():
		grass_plan=read(grass_moves_path)
		for path:String in grass_plan.get("inputs",{}):pin(path,str(grass_plan.inputs[path]))
		if grass_plan.has("building_inputs"):check(grass_plan.building_inputs.sha256==report.building_inputs.sha256,"grass proposal uses identical published buildings and anchors")
	if failed:return
	if not bundle.is_empty():check(bundle.get("handoff_sha256","")==report.handoff_observation.sha256,"publication bundle matches observed handoff")
	# Actual completed receipts are authoritative; pending prose alone can never
	# authorize placement, and older v3/v5 resource paths in site notes are ignored.
	var catalog=Assets.new(ASSET_ROOT)
	for key:String in KEYS:
		var published:Dictionary=handoff.get("formal_publications",{}).get(key,{})
		var descriptor:Dictionary=published.get("publication_receipt",{})
		if not bundle.is_empty():check(bundle.get("models",{}).get(key,{})==descriptor,"optional publication bundle agrees with authoritative handoff "+key)
		check(published.get("entry_kind","")=="asset" and published.get("status",{}).get("resource","")=="passed" and published.get("status",{}).get("visual","")=="passed","formal model resource and visual acceptance "+key)
		for proof_key:String in ["source","manifest","acceptance","formal_catalog_use"]:
			var proof_descriptor:Dictionary=published.get(proof_key,{})
			check(str(proof_descriptor.get("sha256","")).length()==64,"explicit "+proof_key+" identity "+key)
			pin(str(proof_descriptor.get("path","")),str(proof_descriptor.get("sha256","")))
		if failed:return
		var catalog_proof:=read(published.formal_catalog_use.path)
		check(catalog_proof.get("failed",-1)==0 and int(catalog_proof.get("passed",0))>0 and catalog_proof.get("native_required",false) and catalog_proof.get("formal_library_readback",false),"actual formal catalog placement/undo/save acceptance "+key)
		if not pin(str(descriptor.get("path","")),str(descriptor.get("sha256",""))):continue
		check(str(descriptor.get("sha256","")).length()==64,"explicit publication receipt SHA "+key)
		var publication:=read(descriptor.path)
		if not publication_header_valid(publication):fail_detail("Model has no completed formal-library publication",{"model":key,"receipt":descriptor});continue
		var item:Dictionary=publication.items[0];var digest:=latest_digest(key)
		check(digest.length()==64 and item.get("sha256","")==digest and publication.get("source_sha256","")==digest,"published source is latest handed-off model "+key)
		var asset_path:=str(item.get("target",""))
		check(digest==published.get("source",{}).get("sha256","") and canon(asset_path)==canon(str(published.get("asset_id",""))),"layout design anchors and formal source have identical identity "+key)
		check(canon(asset_path).begins_with(canon(ASSET_ROOT)+"/"),"formal shared-library resource "+key)
		if not pin(asset_path,digest):continue
		var proof_path:=str(item.get("acceptance_report",publication.get("review_path","")))
		var proof_sha:=str(item.get("acceptance_report_sha256",publication.get("review_sha256","")))
		check(canon(proof_path)==canon(str(published.acceptance.path)) and proof_sha==published.acceptance.sha256,"publication acceptance matches current handoff "+key)
		if not pin(proof_path,proof_sha):continue
		var proof:=read(proof_path)
		check(proof.get("passed",false)==true and proof.get("source_sha256","")==digest and proof.get("asset","")==key,"exact accepted source identity "+key)
		for field:String in ["resource_status","visual_status","pipeline_status"]:check(proof.get(field,"")=="passed","model owner completed "+field+" "+key)
		check(proof.get("evidence",[]).size()>=3,"model CPU/GPU/HTTP evidence available "+key)
		for evidence:Dictionary in proof.get("evidence",[]):pin(str(evidence.get("path","")),str(evidence.get("sha256","")))
		var entries:Array=catalog.entries.filter(func(entry):return canon(str(entry.get("asset_path","")))==canon(asset_path))
		if entries.size()!=1:fail_detail("Published resource is not a unique current catalog entry",{"model":key,"asset":asset_path});continue
		var entry:Dictionary=entries[0]
		check(Imported.valid_descriptor(entry.get("model_building",{})) and entry.get("model_building",{}).get("source_sha","")==digest,"full imported-building semantic contract "+key)
		var source_contract:=Imported.source_descriptor(asset_path,digest)
		check(not source_contract.is_empty() and Imported.same(source_contract,entry.get("model_building",{})),"actual GLB members/regions/fixtures match catalog "+key)
		check(Imported.same(entry.get("model_building",{}),item.get("entry",{}).get("model_building",{})),"published semantic descriptor unchanged "+key)
		var native:=Assets._verified_compiled_identity(asset_path)
		check(not native.is_empty() and native.get("source_sha","")==digest,"published native compiled resource valid "+key)
		for field:String in ["source_sha","payload_sha","generator","bytes"]:check(native.get(field)==published.get("native_identity",{}).get(field),"actual native "+field+" matches published resource "+key)
		var bounds:=Bounds.read(asset_path)
		check(bounds.get("known",false),"actual source bounds and complete door sweeps known "+key)
		var site:Dictionary={}
		for row:Dictionary in sites.get("buildings",[]):
			if row.id==key:site=row.duplicate(true)
		if key=="church":site={"id":key,"position":church.get("position",[]),"rotation":[0,church.get("yaw",0),0],"access":church.get("access",{})}
		check(site.get("position",[]).size()==3 and site.get("rotation",[]).size()==3,"explicit current proposed site "+key)
		sources[key]={"entry":entry.duplicate(true),"catalog_token":City.token(entry),"asset_path":asset_path,"source_sha256":digest,"publication":descriptor,"acceptance":{"path":proof_path,"sha256":proof_sha},"site":site,"bounds":bounds,"json":source_json(asset_path)}
	check(sources.size()==3,"all three models are published, not old draft deliveries")
	report.model_inputs=sources.keys().map(func(key):return {"key":key,"asset_path":sources[key].asset_path,"source_sha256":sources[key].source_sha256,"publication":sources[key].publication,"site":sources[key].site.position})
	report.limits=["No map placement is established by source acceptance or the old site survey.","No residential or model interior traversal repeated; outdoor runtime and visual layout remain pending after save.","Wheel/shaft pivots retained; no automatic waterwheel-drive simulation claimed."]

func move_explicit_grass()->void:
	report.grass_relocations=[]
	if grass_plan.is_empty():return
	check(grass_plan.get("input_sha256","")==expected_sha and not grass_plan.get("moves",[]).is_empty(),"explicit grass relocation plan pins current candidate")
	if failed:return
	var seen:={}
	for move:Dictionary in grass_plan.moves:
		var id:=str(move.get("id",""));var record:Dictionary=editor._doc._find(id).duplicate(true)
		check(not seen.has(id) and not record.is_empty() and City.token(record)==move.get("before_token",""),"explicit existing grass record identity "+id);seen[id]=true
		if failed:return
		check(record.get("kind","")=="asset" and record.get("collision","") == "none" and not record.has("model_building") and not record.has("building") and record.get("bounds_size",[0,INF,0])[1]<=.75,"only existing small nonblocking grass can relocate "+id)
		check(move.get("position",[]).size()==3 and City.vec(move.position).is_finite(),"explicit finite grass target "+id)
		if failed:return
		var args:={"id":id,"position":move.position}
		var result:=await operation("set_object_transform",args)
		if failed:return
		var after_record:Dictionary=editor._doc._find(id).duplicate(true);var unchanged:=after_record.duplicate(true);unchanged.position=record.position
		check(City.token(unchanged)==City.token(record),"grass resource, yaw, scale and ownership remain identical "+id)
		report.grass_relocations.append({"id":id,"before_record":record,"after_record":after_record,"old_position":record.position,"position":after_record.position,"before_token":City.token(record),"after_token":City.token(after_record),"operation":{"tool":"set_object_transform","request":args,"result":result}})
		if failed:return

func ground(at:Vector2)->float:return Props.ground(editor._doc,Vector3(at.x,0,at.y))
func terrain_seed(at:Vector2)->String:
	for record:Dictionary in editor._doc.records:
		if not record.has("terrain_mesh"):continue
		var pose:=Terrain.transform(record);var local:=pose.affine_inverse()*Vector3(at.x,0,at.y)
		if is_finite(Terrain.sample(record,local)):return record.uuid
	return ""
func grading()->Array:
	var requests:Array=church.get("terrain_requests",[]).duplicate(true)
	for request:Dictionary in requests:request.id=terrain_seed(Vector2(request.points[0][0],request.points[0][1]))
	var g:Dictionary=sources.guardhouse.site.grading;var at:=Vector2(g.center[0],g.center[1])
	requests.append({"id":terrain_seed(at),"mode":"flatten","shape":"rectangle","points":[[at.x,at.y]],"plot_width":g.width,"plot_depth":g.depth,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":g.target_height,"blend_margin":g.blend_margin,"strength":1.,"cross_tiles":true})
	check(requests.size()>1 and requests.all(func(r):return not str(r.id).is_empty()),"guard/church native terrain requests have real current seeds; mill riverbed untouched")
	return requests
func node_at(graph:Dictionary,id:String)->Dictionary:
	for node:Dictionary in graph.nodes:
		if node.id==id:return node
	return {}
func add_node(nodes:Array,id:String,at:Vector2)->void:
	var height:=ground(at)
	if not is_finite(height):fail_detail("Road endpoint has no actual terrain",{"id":id,"xz":[at.x,at.y]});return
	nodes.append({"id":id,"position":[at.x,height,at.y]})
func edge(id:String,from:String,to:String,width:float)->Dictionary:return {"id":id,"from":from,"to":to,"kind":"ground","name":id,"width_start":width,"width_end":width}
func road_request()->Dictionary:
	var graph:Dictionary=City.resolve(editor._doc.map_meta).roads;var nodes:Array=[];var edges:Array=[];var removals:Array=[]
	var ga:Dictionary=sources.guardhouse.site.access;var old:=node_at(graph,ga.existing_endpoint_id)
	if old.is_empty() or Vector2(old.position[0],old.position[2]).distance_to(Vector2(158.5,165))>.001:fail_detail("Guard existing north alley endpoint changed; rebase site proposal",{"actual":old});return {}
	var adjusted:=old.duplicate(true);adjusted.position=[158.5,ground(Vector2(158.5,163.5)),163.5];nodes.append(adjusted)
	var previous:String=ga.existing_endpoint_id
	for i in ga.new_points_xz.size():
		var at:Array=ga.new_points_xz[i];var id:="functional_guard_access_"+str(i);add_node(nodes,id,Vector2(at[0],at[1]));edges.append(edge(id+"_edge",previous,id,float(ga.width)));previous=id
	var ma:Dictionary=sources.watermill.site.access;var start:=node_at(graph,ma.existing_start_node);var points:Array=ma.points_xz
	if start.is_empty() or Vector2(start.position[0],start.position[2]).distance_to(Vector2(points[0][0],points[0][1]))>.001:fail_detail("Mill existing dry-bank access node changed",{"actual":start});return {}
	previous=ma.existing_start_node;var mill_first:=1
	# The real farm road already ends one metre east of the surveyed junction.
	# Extend that existing terminal, rather than overlaying it with a new edge.
	var mill_tail:=node_at(graph,"axel_n_944ee84d9ad4")
	if not mill_tail.is_empty():
		var incident:Array=graph.edges.filter(func(e):return mill_tail.id in [e.from,e.to])
		if Vector2(mill_tail.position[0],mill_tail.position[2]).distance_to(Vector2(291,214))>.001 or incident.size()!=1 or ma.existing_start_node not in [incident[0].from,incident[0].to] or incident[0].kind!="ground":fail_detail("Existing mill farm-road terminal changed; rebase access proposal",{"node":mill_tail,"edges":incident});return {}
		var extended:=mill_tail.duplicate(true);extended.position=[points[1][0],ground(Vector2(points[1][0],points[1][1])),points[1][1]];nodes.append(extended)
		previous=mill_tail.id;mill_first=2
		report.mill_access_adjustment={"existing_terminal":mill_tail.id,"before":mill_tail.position,"after":extended.position,"reason":"extend existing farm_03 stub; no overlapping duplicate edge"}
	for i in range(mill_first,points.size()):
		var id:="functional_mill_access_"+str(i);add_node(nodes,id,Vector2(points[i][0],points[i][1]));edges.append(edge(id+"_edge",previous,id,float(ma.width)));previous=id
	var ca:Dictionary=church.access;var junction:=Vector2(ca.split_at_xz[0],ca.split_at_xz[1]);var junction_id:=""
	for node:Dictionary in graph.nodes:
		if Vector2(node.position[0],node.position[2]).distance_to(junction)<.001:junction_id=node.id;break
	if junction_id.is_empty():
		var matches:Array=[]
		for item:Dictionary in graph.edges:
			var a:=node_at(graph,item.from);var b:=node_at(graph,item.to)
			var av:=Vector2(a.position[0],a.position[2]);var bv:=Vector2(b.position[0],b.position[2])
			if Geometry2D.get_closest_point_to_segment(junction,av,bv).distance_to(junction)<.001:matches.append(item)
		if matches.size()!=1 or matches[0].get("kind","")!="ground" or matches[0].has("bridge_ref") or matches[0].has("stone_bridge"):fail_detail("Church north junction requires one actual ordinary main-road segment",{"matches":matches});return {}
		var current:Dictionary=matches[0];junction_id="functional_church_north_junction";add_node(nodes,junction_id,junction)
		var left:=current.duplicate(true);var right:=current.duplicate(true);left.id=current.id+"_church_w";right.id=current.id+"_church_e";left.to=junction_id;right.from=junction_id
		removals.append(current.id);edges.append_array([left,right])
	var tip:="functional_church_door";add_node(nodes,tip,Vector2(ca.new_branch_end_xz[0],ca.new_branch_end_xz[1]));edges.append(edge("functional_church_access",junction_id,tip,float(ca.width)))
	return {"expected_token":City.token(graph),"nodes":nodes,"edges":edges,"remove_edges":removals}

func shape_box(box:AABB,pose:Transform3D)->Dictionary:
	var vertices:Array[Vector3]=[]
	for i in 8:vertices.append(pose*box.get_endpoint(i))
	return Foot.from_points(vertices)
func part_shapes(key:String,record:Dictionary)->Array:
	var source:Dictionary=sources[key];var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position));var result:Array=[]
	for mesh:Dictionary in source.bounds.mesh_nodes:
		var extras:Dictionary=source.json.nodes[mesh.node_index].get("extras",{});var shape:=shape_box(mesh.bounds,pose)
		shape.part=str(extras.get("uuid",mesh.id));shape.semantic=extras;result.append(shape)
	return result
func complete_source_shape(key:String,record:Dictionary)->Dictionary:
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180).scaled_local(City.vec(record.size)),City.vec(record.position))
	# Bounds.read derives exact angular extrema of each authored hinge sweep;
	# catalog bounds are the static pose and cannot be used for this broad phase.
	return shape_box(sources[key].bounds.local_bounds,pose)
func hinge_envelopes(key:String,record:Dictionary)->Array:
	var result:Array=[];var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180).scaled_local(City.vec(record.size)),City.vec(record.position))
	for mesh:Dictionary in sources[key].bounds.mesh_nodes:
		var extra:Dictionary=sources[key].json.nodes[mesh.node_index].get("extras",{})
		if not extra.has("rmmo_hinge"):continue
		var geometry:=shape_box(mesh.bounds,pose)
		result.append({"id":extra.rmmo_hinge.id,"sweep_degrees":extra.rmmo_hinge.angle,"world_polygon":Array(geometry.polygon).map(func(p):return [p.x,p.y]),"world_min":City.xyz(geometry.bounds.position),"world_max":City.xyz(geometry.bounds.end),"source":"native Bounds.read continuous rmmo_hinge extrema; includes authored handles"})
	return result
func range_under(polygon:PackedVector2Array)->Dictionary:
	var low:=INF;var high:=-INF;var covered:=0.;var at_low:Array=[];var at_high:Array=[]
	var rect:=Rect2(polygon[0],Vector2.ZERO)
	for p:Vector2 in polygon:rect=rect.expand(p)
	for r:Dictionary in editor._doc.records:
		if not r.has("terrain_mesh"):continue
		var transform:=Terrain.transform(r);var bounds:AABB=transform*Terrain.bounds(r)
		if not rect.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true):continue
		for z in int(r.terrain_mesh.rows):
			for x in int(r.terrain_mesh.columns):
				if not Terrain.solid(r.terrain_mesh,x,z):continue
				var corners:Array=Terrain.cell(r,x,z).map(func(p):return transform*p)
				var cell:=Rect2(Vector2(corners[0].x,corners[0].z),Vector2.ZERO)
				for p:Vector3 in corners:cell=cell.expand(Vector2(p.x,p.z))
				if not rect.intersects(cell,true):continue
				for indices:Array in [[0,1,2],[0,2,3]]:
					var tri:=PackedVector2Array();var a:Vector3=corners[indices[0]];var normal:Vector3=(corners[indices[1]]-a).cross(corners[indices[2]]-a)
					for i:int in indices:tri.append(Vector2(corners[i].x,corners[i].z))
					for patch:PackedVector2Array in Geometry2D.intersect_polygons(polygon,tri):
						covered+=absf(Poly.area(Array(patch)))
						for p:Vector2 in patch:
							var height:=a.y-(normal.x*(p.x-a.x)+normal.z*(p.y-a.z))/normal.y
							if height<low:low=height;at_low=[p.x,height,p.y]
							if height>high:high=height;at_high=[p.x,height,p.y]
	var expected:=absf(Poly.area(Array(polygon)))
	return {"min":low,"max":high,"minimum_at":at_low,"maximum_at":at_high,"covered_area":covered,"expected_area":expected,"complete":is_finite(low) and absf(covered-expected)<maxf(.001,expected*.00001)}
func local_polygon(points:Array,pose:Transform3D)->PackedVector2Array:
	var result:=PackedVector2Array()
	for point:Array in points:
		var p:=pose*Vector3(point[0],0,point[1]);result.append(Vector2(p.x,p.z))
	return result
func verify_support(key:String,record:Dictionary,pieces:Array)->void:
	var design:Dictionary=handoff.designs[key];var origin:=City.vec(record.position);var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),origin)
	var floor_height:=origin.y+(0. if key=="watermill" else .3)
	# Exact source component ranges prevent an upstairs eave being extruded down
	# into the ground. This is the existing native terrain footprint guard.
	for tile:Dictionary in editor._doc.records:
		if not tile.has("terrain_mesh"):continue
		var conflict:=Foot.terrain_conflict(tile,pieces,floor_height-.005)
		if not conflict.is_empty():fail_detail("Actual terrain penetrates building above its ground floor: "+key,conflict);return
	if key=="watermill":
		var foundation:Dictionary=design.get("river_foundation",{})
		check(foundation.get("actual_support_is_union_of_polygons",false) and not foundation.get("modules",[]).is_empty(),"mill actual independent foundation polygons supplied")
		for module:Dictionary in foundation.get("modules",[]):
			var poly:=local_polygon(module.support_polygon_xz,pose);var sampled:=range_under(poly);var bottom:=origin.y+float(module.bottom_y)
			report.support.append({"building":key,"part":module.group,"base_y":bottom,"terrain":sampled})
			check(sampled.complete and sampled.min>=bottom-.005 and sampled.max<=floor_height+.005,"mill foundation physically reaches existing riverbank: "+str(module.group))
	else:
		var bases:=0
		for piece:Dictionary in pieces:
			var semantic:Dictionary=piece.semantic.get("rmmo_part",{})
			# Raised interior floor slabs are carried by their authored foundation,
			# not by soil directly at the slab underside.
			if semantic.get("role","")!="floor" or int(semantic.get("floor",-1))!=0 or piece.bounds.position.y>origin.y+.005:continue
			var sampled:=range_under(piece.polygon);bases+=1
			report.support.append({"building":key,"part":piece.part,"base_y":piece.bounds.position.y,"terrain":sampled})
			check(sampled.complete and sampled.min>=piece.bounds.position.y-.005 and sampled.max<=floor_height+.005,"actual ground-floor bearing is continuous: "+key+"/"+piece.part)
		check(bases>0,"source has actual ground-floor bearing components: "+key)
func verify_wheel(record:Dictionary)->void:
	var wheel:Dictionary=handoff.designs.watermill.waterwheel;var box:Array=wheel.clear_water_corridor_xz
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position))
	var poly:=local_polygon([[box[0],box[1]],[box[2],box[1]],[box[2],box[3]],[box[0],box[3]]],pose)
	var bed:=range_under(poly);var bottom:float=record.position[1]+float(wheel.bottom_y);var max_bed:float=record.position[1]+float(wheel.minimum_bed_y)
	check(bed.complete and bed.max<=max_bed+.0001,"whole actual mill wheel corridor clears untouched riverbed")
	var area:=0.;var levels:Array=[]
	for water:Dictionary in editor._doc.records:
		if water.get("surface_id","")!="water" or not water.has("channel_mesh"):continue
		var transform:=Transform3D(Basis.from_euler(City.vec(water.rotation)*PI/180),City.vec(water.position))
		for local:Array in Channel.local_polygons(water):
			var points:Array=local.map(func(p):return transform*p);var flat:=PackedVector2Array()
			for p:Vector3 in points:flat.append(Vector2(p.x,p.z))
			for patch:PackedVector2Array in Geometry2D.intersect_polygons(poly,flat):
				area+=absf(Poly.area(Array(patch)))
				var plane:=Plane(points[0],points[1],points[2])
				for p:Vector2 in patch:levels.append((plane.d-plane.normal.x*p.x-plane.normal.z*p.y)/plane.normal.y)
	var expected:=absf(Poly.area(Array(poly)));var wet:bool=absf(area-expected)<maxf(.001,expected*.00001) and not levels.is_empty()
	check(wet,"actual saved water mesh continuously covers the entire wheel corridor")
	if wet:
		var allowed:Array=wheel.accepted_water_y_design_range
		check(levels.min()>=record.position[1]+allowed[0]-.0001 and levels.max()<=record.position[1]+allowed[1]+.0001,"actual wheel immersion uses accepted local water range")
	report.wheel={"actual_root":record.position,"axis_world":City.xyz(pose*City.vec(wheel.axis_center)),"bed":bed,"maximum_allowed_bed":max_bed,"bottom_y":bottom,"actual_water_area":area,"required_area":expected,"water_levels_min":levels.min() if not levels.is_empty() else null,"water_levels_max":levels.max() if not levels.is_empty() else null,"river_modified":false}
func verify_space(key:String,record:Dictionary,all_new:Array)->void:
	var full:=complete_source_shape(key,record);var pieces:=part_shapes(key,record)
	check(not Foot.batches_overlap([full],Zones.obstacles(editor._doc.map_meta)),"complete building and door sweep avoid R1-R5/passages: "+key)
	for old:Dictionary in editor._doc.records:
		if old.uuid==record.uuid or old.has("terrain_mesh") or old.has("road_mesh"):continue
		if key=="watermill" and old.has("channel_mesh") and old.get("surface_id","")=="water":continue
		if not Foot.batches_overlap([full],Foot.record_shapes(old)):continue
		if Foot.batches_overlap(pieces,Foot.record_shapes(old)):fail_detail("Actual source component envelopes overlap existing content: "+key,{"uuid":old.uuid,"kind":old.kind,"new_building":old.uuid in all_new});return
	verify_support(key,record,pieces)
	if key=="watermill":verify_wheel(record)
	var design:Dictionary=handoff.designs[key];var door:Dictionary={}
	if key=="guardhouse":door=design.main_entrance
	elif key=="church":door=design.entrances.filter(func(row):return row.id=="main")[0]
	else:door=design.front_door
	var pose:=Transform3D(Basis.from_euler(City.vec(record.rotation)*PI/180),City.vec(record.position))
	var threshold:=pose*City.vec(door.get("position",door.get("center",[])));var outward:Vector3=pose.basis*City.vec(door.outward)
	var at:=threshold+outward*2.;var sampled:=ground(Vector2(at.x,at.z))
	check(is_finite(sampled),"exterior main-door approach has real terrain: "+key)
	var access:Dictionary=sources[key].site.access
	var route:Array=access.get("points_xz",[access.get("split_at_xz",[]),access.get("new_branch_end_xz",[])])
	report.outdoor_access.append({"key":key,"uuid":record.uuid,"threshold":City.xyz(threshold),"outward":City.xyz(outward),"exterior_sample":City.xyz(at),"ground_y":sampled,"access_points_xz":route,"access_endpoint_xz":route[-1],"runtime_capsule":"pending actual outdoor runtime","interior":"model-owner acceptance reused, not retested"})

func final_guards()->void:
	verify_live_building_inputs()
	for path:String in inputs:check(FileAccess.get_sha256(path)==inputs[path],"input identity retained "+path.get_file())
	check(FileAccess.get_sha256(target)==expected_sha,"candidate has not changed during private staging")
	check(FileAccess.get_sha256(FORMAL)==report.formal_before_sha256,"formal town remains unchanged")
	var catalog=Assets.new(ASSET_ROOT)
	for key:String in KEYS:
		var matches:Array=catalog.entries.filter(func(entry):return canon(str(entry.get("asset_path","")))==canon(sources[key].asset_path))
		check(matches.size()==1 and City.token(matches[0])==sources[key].catalog_token,"individual published catalog entry unchanged "+key)
func run()->void:
	if "--self-test" in OS.get_cmdline_user_args():
		check(not publication_header_valid({}),"empty publication cannot pass")
		check(not publication_header_valid({"ok":true,"completed":false,"failures":[],"items":[{}]}),"unfinished publication cannot pass")
		check(publication_header_valid({"ok":true,"completed":true,"failures":[],"items":[{}]}),"completed receipt header recognized; resource checks remain separate")
		var pose:=Transform3D(Basis(Vector3.UP,PI),Vector3(310,10,78));check((pose*Vector3(0,.3,11.24)).distance_to(Vector3(310,10.3,66.76))<.0001,"north-facing church origin and actual main threshold")
		var scoped:={"formal_publications":{"church":{"source":{"sha256":"a"}}},"designs":{"watermill":{"waterwheel":{"axis_center":[1,2,3]}}},"market_optimization":{"status":"pending"}}
		var unrelated:=scoped.duplicate(true);unrelated.market_optimization.status="ready"
		check(City.token(scoped_handoff(scoped))==City.token(scoped_handoff(unrelated)),"unrelated market handoff edit cannot invalidate building inputs")
		unrelated.formal_publications.church.source.sha256="b"
		check(City.token(scoped_handoff(scoped))!=City.token(scoped_handoff(unrelated)),"changed actual building publication invalidates scoped inputs")
		unrelated=scoped.duplicate(true);unrelated.designs.watermill.waterwheel.axis_center=[1,2,4]
		check(City.token(scoped_handoff(scoped))!=City.token(scoped_handoff(unrelated)),"changed used wheel anchor invalidates scoped inputs")
		quit(0 if failed==0 else 1);return
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--apply":apply_requested=true
		elif arg=="--check-inputs":inputs_only=true
		elif arg.begins_with("--map="):target=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--publications="):bundle_path=arg.trim_prefix("--publications=")
		elif arg.begins_with("--grass-moves="):grass_moves_path=arg.trim_prefix("--grass-moves=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	check(Paths.allowed(output) and output.get_extension()=="json","report confined to external content root")
	prepare_inputs();persist()
	if stop():return
	if inputs_only:verify_live_building_inputs();report.phase="published_inputs_verified_site_not_applied";persist();quit(0 if failed==0 else 1);return
	check(canon(target).begins_with("d:/code/rmmo_runtime/cache/world3d/") and canon(target)!=canon(FORMAL),"candidate-only target")
	check(expected_sha.length()==64 and FileAccess.file_exists(target) and FileAccess.get_sha256(target)==expected_sha,"explicit current candidate SHA required")
	if stop():return
	report.merge({"map":target,"input_sha256":expected_sha,"formal_before_sha256":FileAccess.get_sha256(FORMAL)})
	create_timer(2400).timeout.connect(func():fail_detail("Functional-building transaction timed out");persist();quit(2));rpc_timeout_ms=600000
	var fixture:=OUT+"/functional_buildings_fixture/map.gltf";DirAccess.make_dir_recursive_absolute(fixture.get_base_dir());var empty:=Doc.new()
	check(empty.save(fixture)==OK,"native isolated startup fixture")
	if stop():return
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=fixture;session.world3d_editor_doc=empty
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=OUT+"/functional_buildings_drafts";root.add_child(editor);await settle()
	while (editor._load_job!=null and editor._load_job.active) or editor._ground_batches.stats().get("pending_groups",0)>0:await process_frame
	var original=Doc.open_file(target);check(original!=null,"actual current candidate opens natively")
	if stop():return
	before=original.recovery_snapshot();var staged:=Doc.new();staged.apply_recovery(before);editor._doc=staged;editor._city.refresh();editor._authoring.refresh()
	check(not staged.map_meta.get("town_reference",{}).has("functional_buildings"),"functional buildings not already placed")
	var listener:=TCPServer.new();port=33840
	while listener.listen(port,"127.0.0.1")!=OK:port+=1
	listener.stop();check(editor.start_mcp(port).ok,"current 3D loopback native operations")
	if stop():return
	await operation("configure_transform",{"gravity_placement":false})
	await move_explicit_grass()
	if stop():return
	var strokes:=grading();report.terrain_request={"strokes":strokes}
	if stop():return
	await operation("apply_terrain_layout",report.terrain_request)
	if stop():return
	var request:=road_request();report.road_request=request
	if stop():return
	await operation("update_road_graph",request)
	if stop():return
	var ids:Array=[]
	for key:String in KEYS:
		var source:Dictionary=sources[key];var origin:=City.vec(source.site.position);var landing:=origin+Vector3.UP*float(source.entry.bounds_position[1])
		var placed:=await operation("place_asset",{"asset_id":source.asset_path,"position":City.xyz(landing)})
		if stop():return
		if placed.get("ids",[]).size()!=1:fail_detail("Expected one complete imported building record",{"key":key,"result":placed});stop();return
		var id:String=placed.ids[0];ids.append(id)
		await operation("set_object_transform",{"id":id,"position":City.xyz(origin),"rotation":source.site.rotation,"size":[1,1,1]})
		if stop():return
		var actual:Dictionary=staged._find(id)
		check(City.vec(actual.position).distance_to(origin)<.00001 and City.vec(actual.rotation).distance_to(City.vec(source.site.rotation))<.00001 and City.vec(actual.size).distance_to(Vector3.ONE)<.00001,"actual native root pose is exact; no bounds-bottom placement offset remains "+key)
		check(Imported.verify_source(actual) and Imported.same(actual.model_building,source.entry.model_building),"preserved actual source members/regions/fixtures "+key)
		var components:=await operation("list_building_components",{"id":id})
		report.placements.append({"key":key,"uuid":id,"asset_path":source.asset_path,"source_sha256":source.source_sha256,"position":actual.position,"rotation":actual.rotation,"scale":actual.size,"model_building_token":City.token(actual.model_building),"components":components,"hinge_sweep_envelopes":hinge_envelopes(key,actual),"publication":source.publication})
		if stop():return
	for placement:Dictionary in report.placements:verify_space(placement.key,staged._find(placement.uuid),ids)
	for move:Dictionary in report.grass_relocations:
		var record:Dictionary=staged._find(move.id);var shape:=Foot.record_shapes(record)
		check(not Foot.batches_overlap(shape,Zones.obstacles(staged.map_meta)),"relocated grass avoids protected zones "+move.id)
		for other:Dictionary in staged.records:
			if other.uuid==move.id or other.has("terrain_mesh"):continue
			if Foot.batches_overlap(shape,Foot.record_shapes(other)):fail_detail("Relocated grass overlaps final scene",{"id":move.id,"other":other.uuid});break
	if stop():return
	var roads:Dictionary=editor._roads.prepare({});report.final_road_validation={"ok":roads.get("ok",false),"error":roads.get("error",""),"conflicts":roads.get("conflicts",[]),"diff":roads.get("diff",{})}
	if not roads.get("ok",false):fail_detail("Final native full road/door clearance rejected",report.final_road_validation)
	elif roads.diff.added!=0 or roads.diff.updated!=0 or roads.diff.removed!=0:fail_detail("Final road state requires an uncommitted regeneration",report.final_road_validation)
	if stop():return
	check(City.token(before.map_meta.get("terrain_rivers",[]))==City.token(staged.map_meta.get("terrain_rivers",[])),"main river and continuous tributary ownership unchanged")
	check(City.token(City.resolve(before.map_meta).zones)==City.token(City.resolve(staged.map_meta).zones),"R1-R5 preserved")
	check(City.token(before.map_meta.get("building_instances",{}))==City.token(staged.map_meta.get("building_instances",{})),"existing native houses unchanged")
	var moved_tokens:Dictionary={}
	for move:Dictionary in report.grass_relocations:moved_tokens[move.id]=move.after_token
	for old:Dictionary in before.records:
		if old.has("terrain_mesh") or old.has("road_mesh"):continue
		if moved_tokens.has(old.uuid):
			check(City.token(staged._find(old.uuid))==moved_tokens[old.uuid],"relocated grass retained exact verified final state "+old.uuid);continue
		if City.token(old)!=City.token(staged._find(old.uuid)):fail_detail("Preexisting object changed",{"uuid":old.uuid});break
	staged.map_meta.town_reference.functional_buildings={"phase":"native_candidate_outdoor_review_pending","placements":report.placements,"inputs":inputs,"outdoor_access":report.outdoor_access,"wheel":report.wheel,"relocated_vegetation":moved_tokens,"model_interiors":"owner evidence reused","project_supplementary_design":true}
	check(staged.validate_save()==OK,"whole native document validates with imported building semantics")
	if stop():return
	var after:Dictionary=staged.recovery_snapshot();original.apply_recovery(after);original.commit_recovery_change(before)
	report.transaction={"undo_passed":original.undo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(before))}
	check(report.transaction.undo_passed,"one native undo restores terrain/roads/all objects/metadata")
	report.transaction.redo_passed=original.redo() and City.token(identity(original.recovery_snapshot()))==City.token(identity(after))
	check(report.transaction.redo_passed,"one native redo restores all three functional sites")
	check(original._disk_signature==expected_sha,"native original disk conflict signature preserved")
	final_guards()
	if stop():return
	report.phase="native_preflight_complete_outdoor_review_pending";persist()
	if apply_requested:
		check(original.save(target)==OK,"native atomic conflict-aware candidate save")
		if stop():return
		report.saved=true;report.output_sha256=FileAccess.get_sha256(target);report.candidate_sha256=report.output_sha256;persist()
		var reopened=Doc.open_file(target)
		check(reopened!=null and reopened.validate_save()==OK,"saved candidate reopens natively")
		if reopened!=null:check(City.token(identity(reopened.recovery_snapshot()))==City.token(identity(after)),"native saved terrain/roads/buildings/metadata exact identity")
		check(FileAccess.get_sha256(FORMAL)==report.formal_before_sha256,"formal town never modified")
		if stop():return
		report.phase="native_functional_buildings_complete_outdoor_review_pending";report.native_reopen_passed=true;report.transaction.save_reopen=true
	persist();editor._mcp.stop();quit(0)
