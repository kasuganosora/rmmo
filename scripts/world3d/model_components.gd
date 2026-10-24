extends RefCounted
## Adapt authored imported parts to existing fixture, lighting and render-batch
## contracts. Persist only per-instance state; native source graphs stay immutable.
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Imported=preload("res://scripts/world3d/imported_building.gd")

static func valid(record:Dictionary)->bool:
	if not Imported.valid_record(record):return false
	if not record.has("model_component_states"):return true
	var states:Variant=record.model_component_states
	if record.get("kind")!="asset" or not states is Dictionary or states.size()>256:return false
	for key in states:
		if not key is String or key.is_empty() or key.length()>512:return false
		if not Fixtures._bounded(states[key],0,1):return false
	return true

static func relative_pose(node:Node,root:Node)->Transform3D:
	var pose:=Transform3D.IDENTITY
	var current:Node=node
	while current!=null:
		if current is Node3D:pose=current.transform*pose
		if current==root:break
		current=current.get_parent()
	return pose

static func architectural_hinge(node:Node3D,model:Node)->Dictionary:
	var owner:Node=node
	if owner.get_parent()!=null and owner.get_parent().get_meta("extras",{}).has("door_hinge"):owner=owner.get_parent()
	var extra:Dictionary=owner.get_meta("extras",{})
	var point:Variant=extra.get("door_hinge")
	var state:String=extra.get("door_pose","")
	if not point is Array or point.size()!=3 or state not in ["closed","open_90","parked_open_180"]:return {}
	for value in point:
		if not Fixtures._bounded(value,-100000,100000):return {}
	var pivot:=relative_pose(node,model).affine_inverse()*Vector3(point[0],point[2],-point[1])
	var angle:float=float(extra.get("open_angle_degrees",-90 if "right" in str(owner.name) else 90))
	if state=="parked_open_180":angle=180.0
	return {"id":"architecture:"+str(model.get_path_to(owner)),"angle":angle,"open":0.0 if state=="closed" else 1.0,"pivot":[pivot.x,pivot.y,pivot.z]}

static func valid_socket(socket:Variant)->bool:
	if not socket is Dictionary:return false
	for key in ["position","color"]:
		var values:Variant=socket.get(key)
		if not values is Array or values.size()!=3:return false
		for value in values:
			if not Fixtures._bounded(value,0 if key=="color" else -1000,1 if key=="color" else 1000):return false
	return Fixtures._bounded(socket.get("range"),.1,30) and Fixtures._bounded(socket.get("energy"),0,8) and socket.get("flame") is bool and socket.get("indoor") is bool

static func _encloses_emitting_socket(mesh_node:MeshInstance3D,point:Vector3)->bool:
	# Imported luminous solids may surround their own OmniLight. Let their light
	# escape, but retain lantern-frame/ordinary scene shadows. This is only called
	# within an opted-in, validated fixture subtree; never edit shared materials.
	if mesh_node.mesh==null or mesh_node.mesh.get_surface_count()==0:return false
	for slot in mesh_node.mesh.get_surface_count():
		var material:Material=mesh_node.get_active_material(slot)
		if not material is BaseMaterial3D:return false
		if not material.emission_enabled or material.emission_energy_multiplier<=0:return false
		if maxf(material.emission.r,maxf(material.emission.g,material.emission.b))<=0 and material.emission_texture==null:return false
	var box:=mesh_node.get_aabb()
	# Boundary sockets and degenerate solids keep their authored shadow state.
	var epsilon:float=maxf(box.size.length()*0.000001,0.0000001)
	if not box.grow(-epsilon).has_point(point):return false
	var triangles:PackedVector3Array=mesh_node.mesh.get_faces()
	if triangles.size()<12 or triangles.size()%3!=0:return false
	# Welding positions (not render vertices) permits ordinary UV/normal seams.
	# Reject open/non-manifold emitters instead of treating an AABB as a solid.
	var positions:Dictionary={};var edges:Dictionary={}
	for offset in range(0,triangles.size(),3):
		var a:Vector3=triangles[offset];var b:Vector3=triangles[offset+1];var c:Vector3=triangles[offset+2]
		if (b-a).cross(c-a).length_squared()<=pow(epsilon,4):return false
		var ab:=b-a;var ac:=c-a;var ap:=point-a
		if absf(ab.cross(ac).normalized().dot(ap))<=epsilon:
			var d00:=ab.dot(ab);var d01:=ab.dot(ac);var d11:=ac.dot(ac)
			var d20:=ap.dot(ab);var d21:=ap.dot(ac);var denominator:=d00*d11-d01*d01
			var u:float=(d11*d20-d01*d21)/denominator
			var v:float=(d00*d21-d01*d20)/denominator
			if u>=-0.000001 and v>=-0.000001 and u+v<=1.000001:return false
		var indices:Array[int]=[]
		for vertex:Vector3 in [a,b,c]:
			var key:=vertex.snapped(Vector3.ONE*epsilon)
			if not positions.has(key):positions[key]=positions.size()
			indices.append(positions[key])
		for j in 3:
			var start:int=indices[j];var finish:int=indices[(j+1)%3]
			if start==finish:return false
			var edge:=Vector2i(mini(start,finish),maxi(start,finish))
			edges[edge]=int(edges.get(edge,0))+1
	for count:int in edges.values():
		if count!=2:return false
	# Odd crossings mean inside; de-duplicate hits on shared triangle edges.
	# Two non-axis rays must agree, including for concave or hollow emitters.
	for direction:Vector3 in [Vector3(.811,.379,.443).normalized(),Vector3(-.327,.827,.458).normalized()]:
		var distances:Array[float]=[]
		for offset in range(0,triangles.size(),3):
			var hit:Variant=Geometry3D.ray_intersects_triangle(point,direction,triangles[offset],triangles[offset+1],triangles[offset+2])
			if hit!=null:distances.append(point.distance_to(hit))
		distances.sort()
		var crossings:=0;var previous:=-INF
		for distance:float in distances:
			if distance-previous>epsilon:crossings+=1;previous=distance
		if crossings%2==0:return false
	return true

static func apply(model:Node3D,record:Dictionary,trusted_package:bool=false)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.model_components.apply") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var cursor:=begin(model,record,trusted_package)
	advance(cursor,0)

static func begin(model:Node3D,record:Dictionary,trusted_package:bool=false,nodes:Array[Node]=[])->Dictionary:
	if not trusted_package and not valid(record):return {}
	if nodes.is_empty():nodes=[model];nodes.append_array(model.find_children("*","",true,false))
	# The mounted package already owns its authored annotations. Adapt those
	# parts directly; rebuilding/copying and comparing thousands of descriptor
	# members per instance adds no runtime state. Explicit diagnostics still
	# inspect the same node list, without two additional graph traversals.
	var generic:=false;var legacy:=false
	for node:Node in nodes:
		var extra:Variant=node.get_meta("extras",{})
		if not extra is Dictionary:continue
		generic=generic or extra.has("rmmo_model_components")
		legacy=legacy or extra.get("delivery_stage","")=="textured_repair_v2"
	var authored:Dictionary={}
	if generic and not trusted_package:
		authored=Imported.describe_nodes(nodes)
		if authored.is_empty():
			model.set_meta("model_components_error","invalid_authored_building");return {}
	if record.has("model_building") and not generic:
		model.set_meta("model_components_error","missing_authored_building_contract");return {}
	if generic and not trusted_package and record.has("model_building"):
		var expected:Dictionary=record.model_building.duplicate(true);expected.erase("source_sha")
		if not Imported.same(expected,authored):
			model.set_meta("model_components_error","authored_building_mismatch");return {}
	if not generic and not legacy:return {}
	var states:Dictionary=record.get("model_building_states",{}) if generic else record.get("model_component_states",{})
	return {"model":model,"record":record,"nodes":nodes,"generic":generic,"frame":Imported.frame(record) if generic else Transform3D.IDENTITY,"states":states,"phase":0,"at":0,"batch_sources":[]}

static func advance(cursor:Dictionary,budget_usec:int)->bool:
	if cursor.is_empty() or int(cursor.phase)>=3:return true
	var began:=Time.get_ticks_usec();var advanced:=false
	while int(cursor.phase)<3 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true
		if int(cursor.at)>=cursor.nodes.size():cursor.phase+=1;cursor.at=0;continue
		var node:Node=cursor.nodes[cursor.at];cursor.at+=1
		if cursor.phase==0:_adapt_mesh(node,cursor.model,cursor.record,cursor.generic,cursor.states,cursor.frame)
		elif cursor.phase==1:_adapt_socket(node,cursor.model)
		elif node is MeshInstance3D:
			# Renaming is a separate pass, after every owner path/socket resolved.
			var uuid:String=node.get_meta("extras",{}).get("uuid","")
			if not uuid.is_empty():node.name=uuid
			if node.has_meta("ground_batch_record"):cursor.batch_sources.append(node)
	if cursor.phase<3:return false
	cursor.model.set_meta("model_component_batch_sources",cursor.batch_sources)
	return true

static func _adapt_mesh(node:Node,model:Node3D,record:Dictionary,generic:bool,states:Dictionary,frame:Transform3D)->void:
	if not node is MeshInstance3D or node.mesh==null:return
	var extra:Dictionary=node.get_meta("extras",{}).duplicate(true)
	var owner_path:="."
	if not generic:
		var parent:Node=node.get_parent()
		while parent!=null and parent!=model and not parent.get_meta("extras",{}).has("asset_id"):parent=parent.get_parent()
		owner_path=str(model.get_path_to(parent)) if parent!=null else "."
	var hinge:Variant=extra.get("rmmo_hinge")
	if hinge==null:
		var legacy_hinge:=architectural_hinge(node,model)
		if not legacy_hinge.is_empty():hinge=legacy_hinge;extra.rmmo_hinge=legacy_hinge
	var adapted:=part_data(extra,str(node.name),record,generic,states,frame,relative_pose(node,model) if generic else Transform3D.IDENTITY,node.get_aabb(),owner_path,hinge)
	if adapted.has("fixture_delta"):node.transform=node.transform*adapted.fixture_delta
	if adapted.batch:node.set_meta("ground_batch_record",adapted.row)
	node.set_meta("extras",extra)

# The caller owns extras. Both the editor's graph adapter and the immutable
# streaming projection use this operation; no Node or shared Resource is mutated.
static func part_data(extra:Dictionary,node_name:String,record:Dictionary,generic:bool,states:Dictionary,frame:Transform3D,relative:Transform3D,bounds:AABB,owner_path:String,hinge:Variant)->Dictionary:
	if generic:
		extra.rmmo_source_uuid=extra.get("rmmo_source_uuid",extra.get("uuid"))
		extra.uuid=str(record.uuid)+"__"+str(extra.rmmo_source_uuid)
	var row:Dictionary={"kind":"box","uuid":str(extra.get("uuid",node_name)),"size":[1,1,1]}
	if generic:
		var part:Dictionary=extra.rmmo_part
		row.building={"id":str(record.uuid),"floor":int(part.floor),"floor_y":float(part.floor_y),"part":str(part.part)+("/ceiling" if part.role=="ceiling" else ""),"role":str(part.role)}
		var world_bounds:AABB=frame*relative*bounds
		row.position=Fixtures.arr(world_bounds.get_center());row.size=Fixtures.arr(world_bounds.size)
	else:
		var group:String=extra.get("semantic_group","")
		row.building={"id":str(record.uuid)+":"+group+":"+owner_path,"floor":1 if group.begins_with("3") or group in ["11_Exterior_Upper","20_Floor_L1"] else 0,"part":node_name+("/ceiling" if group=="33_Ceilings_L1" else ""),"role":"roof" if group.begins_with("50_") else "body"}
		if group in ["00_Foundation","20_Floor_L1"]:row.building.role="floor"
		elif group=="33_Ceilings_L1":row.building.role="ceiling"
	var result:Dictionary={"row":row,"batch":false}
	if hinge is Dictionary and hinge.get("id") is String and Fixtures._bounded(hinge.get("angle"),-180,180):
		var id:=str(hinge.id) if generic else owner_path+":"+str(hinge.id)
		var fixture:={"id":id,"kind":"door","pivot":hinge.get("pivot",[0,0,0]),"angle":hinge.angle,"open":float(states.get(id,hinge.get("open",0.0)))}
		result.fixture_delta=Fixtures.pose(Transform3D.IDENTITY,fixture,fixture.open-float(hinge.get("open",0.0)))
		extra.fixture=fixture;extra.rmmo_collision="block";row.fixture=fixture
		row.building.id=str(record.uuid)
	extra.building=row.building.duplicate(true)
	if not extra.has("rmmo_model_light") and not extra.has("rmmo_visibility_range") and not extra.get("rmmo_auto_lod",false):
		result.batch=not extra.has("rmmo_wind") and not extra.has("wind_response") and not str(extra.get("finish_component","")).contains("banner_cloth")
	return result

static func _adapt_socket(node:Node,model:Node3D)->void:
	# A socket is carried by one mesh so it survives streaming's flattened view.
	var socket:Variant=node.get_meta("extras",{}).get("rmmo_light_socket")
	if not valid_socket(socket) or not node is Node3D:return
	var meshes:Array=node.find_children("*","MeshInstance3D",true,false)
	if meshes.is_empty():return
	var anchor:MeshInstance3D=meshes[0]
	var p:Variant=socket.get("position")
	if not p is Array or p.size()!=3:return
	var socket_point:Vector3=relative_pose(node,model)*Vector3(p[0],p[1],p[2])
	for emitter:MeshInstance3D in meshes:
		var pose:=relative_pose(emitter,model)
		if absf(pose.basis.determinant())<=0.00000001:continue
		if _encloses_emitting_socket(emitter,pose.affine_inverse()*socket_point):
			emitter.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var local:Vector3=relative_pose(anchor,model).affine_inverse()*socket_point
	var extra:Dictionary=anchor.get_meta("extras",{}).duplicate(true)
	extra.rmmo_model_light=socket.duplicate(true);extra.rmmo_model_light.position=[local.x,local.y,local.z]
	anchor.set_meta("extras",extra);anchor.remove_meta("ground_batch_record")

static func rows(model:Node)->Array:
	var result:Dictionary={}
	for node in model.find_children("*","MeshInstance3D",true,false):
		var extra:Dictionary=node.get_meta("extras",{})
		if not extra.has("rmmo_hinge") or not extra.has("fixture"):continue
		var f:Dictionary=extra.fixture
		if not result.has(f.id):result[f.id]={"id":f.id,"kind":"door","open":f.open,"angle":f.angle,"floor":extra.get("rmmo_part",{}).get("floor",0),"floor_y":extra.get("rmmo_part",{}).get("floor_y",0.0),"members":[]}
		result[f.id].members.append(str(extra.get("uuid",node.name)))
	return result.values()
