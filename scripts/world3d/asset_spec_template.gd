extends RefCounted
## Immutable model description and private instance projection. The native
## reader builds the description once, before publishing its PackedScene.
## No temporary Node/RenderingServer instance is needed for supported records.
const META:=&"_asset_spec_template"
const Components=preload("res://scripts/world3d/model_components.gd")
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Collision=preload("res://scripts/world3d/model_collision_requirements.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
static var enabled:=true
static var worker_enabled:=true
const WORKSPACE_BYTES:=32*1024*1024
var template:Dictionary={}
var record:Dictionary={}
var local:Array[Transform3D]=[]
var adapted:Array=[]
var poses:Array[Transform3D]=[]
var specs:Array=[]
var placement:=Transform3D.IDENTITY
var frame:=Transform3D.IDENTITY
var states:Dictionary={}
var stream:Script
var draw_order:=0
var at:=0
var phase:=0
var rows_adapted:=0
var rows_projected:=0
var sockets_applied:=0
var meshes_projected:=0
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0,"nodes_created":0,"rows_adapted":0,"rows_projected":0,"sockets_applied":0,"meshes_projected":0}

static func compile(packed:PackedScene)->Dictionary:
	# Only the material-free native reader calls this. Unsupported behaviour
	# keeps the existing graph adapter, rather than silently dropping semantics.
	var scene:=packed.get_state();var rows:Array=[];var by_path:Dictionary={}
	var generic:=false;var legacy:=false;var sockets:Array=[];var instance_bytes:=0
	for i:int in scene.get_node_count():
		if scene.get_node_type(i) not in [&"Node3D",&"MeshInstance3D"] or scene.get_node_instance(i)!=null:return {}
		var row:Dictionary={"name":str(scene.get_node_name(i)),"path":str(scene.get_node_path(i)).trim_prefix("./"),"parent":-1,"local":Transform3D.IDENTITY,"extra":{},"mesh":null,"shadow":GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"owner_path":".","hinge_owner":-1}
		if i>0:
			var parent_path:=str(scene.get_node_path(i,true)).trim_prefix("./")
			if not by_path.has(parent_path):return {}
			row.parent=by_path[parent_path]
		for j:int in scene.get_node_property_count(i):
			var key:=scene.get_node_property_name(i,j);var value:Variant=scene.get_node_property_value(i,j)
			match key:
				&"transform":row.local=value
				&"mesh":row.mesh=value
				&"metadata/extras":row.extra=value
				&"cast_shadow":row.shadow=value
				_:return {} # Scripts, skinning, inherited visibility and custom bounds.
		var extra:Dictionary=row.extra
		# Conservative container allowance, computed once from authored metadata.
		# Used only for scheduling; it is not an RSS/VRAM measurement.
		instance_bytes+=4096+var_to_bytes(extra).size()*8
		if extra.get("rmmo_banner_slot",false):return {}
		generic=generic or extra.has("rmmo_model_components")
		legacy=legacy or extra.get("delivery_stage","")=="textured_repair_v2"
		if row.mesh!=null:
			if not row.mesh is ArrayMesh or not row.mesh.has_meta("ground_cpu_cache") or row.mesh.get_blend_shape_count()>0:return {}
			row.bounds=row.mesh.get_aabb();row.cpu=row.mesh.get_meta("ground_cpu_cache")
			var no_material:Material=null
			row.overrides=[];row.overrides.resize(row.mesh.get_surface_count());row.overrides.fill(no_material)
			var parent:int=row.parent
			while parent>0 and not rows[parent].extra.has("asset_id"):parent=rows[parent].parent
			if parent>=0:row.owner_path=rows[parent].path
			row.hinge_owner=row.parent if row.parent>=0 and rows[row.parent].extra.has("door_hinge") else i
		if Components.valid_socket(extra.get("rmmo_light_socket")):sockets.append(i)
		by_path[row.path]=i;rows.append(row)
	if rows.is_empty():return {}
	# The socket adapter selects the first descendant mesh, not the socket node
	# itself. Precompute that immutable relationship once per model.
	var socket_rows:Array=[]
	for socket:int in sockets:
		for i:int in range(socket+1,rows.size()):
			if socket>0 and not rows[i].path.begins_with(rows[socket].path+"/"):break
			if rows[i].mesh!=null:socket_rows.append({"node":socket,"anchor":i});break
	return {"rows":rows,"generic":generic,"components":generic or legacy,"sockets":socket_rows,"white_generation":Controls.white_generation,"instance_bytes":instance_bytes}

static func prepare_records(packed:PackedScene,records:Array,orders:Dictionary,token:RefCounted)->Dictionary:
	var result:Dictionary={};var bytes:=0
	for value:Dictionary in records:
		if token!=null and token.is_cancelled():break
		if not orders.has(value.uuid) or not supports(packed,value):continue
		var charge:int=packed.get_meta(META).instance_bytes+var_to_bytes(value).size()*8
		if bytes+charge>WORKSPACE_BYTES:continue
		bytes+=charge
		var packet:=prepare_one(packed,value,orders[value.uuid],token)
		if packet.get("cancelled",false):return result
		result[value.uuid]=packet
	return result

static func prepare_one(packed:PackedScene,value:Dictionary,order:int,token:RefCounted)->Dictionary:
	var cursor:=new();cursor.begin(packed,value,order)
	while not cursor.advance(2000):
		if token!=null and token.is_cancelled():return {"cancelled":true}
	return {"specs":cursor.specs,"record":value,"profile":cursor.profile}

static func supports(packed:PackedScene,value:Dictionary,local_collision:bool=false)->bool:
	if not enabled or local_collision or not Controls.white_materials or not preload("res://scripts/world3d/runtime_package_policy.gd").trusted():return false
	var description:Dictionary=packed.get_meta(META,{})
	if description.is_empty() or description.white_generation!=Controls.white_generation:return false
	if value.has("model_building") and not description.generic:return false
	for key:String in ["house_prefab","bridge_mesh","parametric_tree","tree_settings","vegetation_batch","wind_response","banner"]:
		if value.has(key):return false
	if value.has("surface_paint") and not preload("res://scripts/world3d/surface_materials.gd").white_face_mapping_elision_enabled:return false
	return true

func begin(packed:PackedScene,value:Dictionary,order:int)->void:
	template=packed.get_meta(META);record=value;draw_order=order
	stream=load("res://scripts/world3d/world_stream.gd")
	placement=preload("res://scripts/world3d/collision_instance_preparation.gd").record_pose(value)
	frame=preload("res://scripts/world3d/imported_building.gd").frame(value) if template.generic else Transform3D.IDENTITY
	states=value.get("model_building_states",{}) if template.generic else value.get("model_component_states",{})
	local.resize(template.rows.size());adapted.resize(template.rows.size());poses.resize(template.rows.size())

func _relative(index:int)->Transform3D:
	var pose:=Transform3D.IDENTITY
	while index>=0:pose=local[index]*pose;index=template.rows[index].parent
	return pose

func _hinge(index:int,extra:Dictionary)->Variant:
	if extra.has("rmmo_hinge"):return extra.rmmo_hinge
	var owner:int=template.rows[index].hinge_owner
	var authored:Dictionary=template.rows[owner].extra
	var point:Variant=authored.get("door_hinge");var state:String=authored.get("door_pose","")
	if not point is Array or point.size()!=3 or state not in ["closed","open_90","parked_open_180"]:return null
	for value in point:
		if not Fixtures._bounded(value,-100000,100000):return null
	var pivot:=_relative(index).affine_inverse()*Vector3(point[0],point[2],-point[1])
	var angle:float=float(authored.get("open_angle_degrees",-90 if "right" in template.rows[owner].name else 90))
	if state=="parked_open_180":angle=180.0
	var hinge:Dictionary={"id":"architecture:"+template.rows[owner].path,"angle":angle,"open":0.0 if state=="closed" else 1.0,"pivot":[pivot.x,pivot.y,pivot.z]}
	extra.rmmo_hinge=hinge;return hinge

func _adapt(index:int)->void:
	var row:Dictionary=template.rows[index];local[index]=row.local
	if row.mesh==null:return
	var extra:Dictionary=row.extra.duplicate(true)
	if extra.has("uuid") and extra.get("rmmo_part") is Dictionary:extra.rmmo_source_uuid=extra.uuid
	extra.uuid=str(record.uuid)+"__"+row.path.replace("/","__")
	var mode:String=record.get("collision","")
	if mode in ["none","walk","block"]:extra.rmmo_collision=mode
	var data:Dictionary={"extra":extra,"batch":false}
	if template.components:
		var hinge:Variant=_hinge(index,extra)
		data.merge(Components.part_data(extra,row.name,record,template.generic,states,frame,_relative(index) if template.generic else Transform3D.IDENTITY,row.bounds,row.owner_path,hinge),true)
		if data.has("fixture_delta"):local[index]=local[index]*data.fixture_delta
	adapted[index]=data

func _socket(entry:Dictionary)->void:
	var row:Dictionary=template.rows[entry.node];var anchor:int=entry.anchor
	var socket:Dictionary=row.extra.rmmo_light_socket;var p:Array=socket.position
	var point:Vector3=_relative(entry.node)*Vector3(p[0],p[1],p[2])
	var position:Vector3=_relative(anchor).affine_inverse()*point
	var data:Dictionary=adapted[anchor]
	data.extra.rmmo_model_light=socket.duplicate(true)
	data.extra.rmmo_model_light.position=[position.x,position.y,position.z];data.batch=false
	# Native white materials have no emission. The graph adapter's enclosing
	# luminous-solid test exits before geometry reads and retains cast_shadow.

func _project(index:int)->void:
	var row:Dictionary=template.rows[index]
	var pose:Transform3D=(placement if row.parent<0 else poses[row.parent])*local[index]
	poses[index]=pose
	if row.mesh==null:return
	var data:Dictionary=adapted[index]
	# Match the graph projection's ownership boundary: runtime fixture state
	# must not mutate the batch record (including nested hinge pivots).
	var extra:Dictionary=data.extra.duplicate(true)
	var bounds:AABB=pose*row.bounds
	var no_material:Material=null
	var spec:Dictionary={"native_visual":false,"uuid":str(extra.uuid),"position":pose.origin,"rotation":pose.basis.get_euler(),"transform":pose,"chunk_min":stream.chunk_key(bounds.position),"chunk_max":stream.chunk_key(bounds.end),"chunk":stream.chunk_key(pose.origin),"mesh":row.cpu if data.batch else row.mesh,"material_override":no_material,"surface_overrides":row.overrides.duplicate(),"cast_shadow":row.shadow,"extras":extra,"map_draw_order":draw_order+specs.size()}
	if Collision.needs_adopted_collision(extra):spec.collision_mesh=row.cpu
	if data.batch:spec.ground_batch_record=data.row
	Fixtures.prepare_spec(spec);specs.append(spec);meshes_projected+=1

func advance(budget_usec:int)->bool:
	var began:=Time.get_ticks_usec();var advanced:=false
	while phase<3 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true
		if phase==0:
			if at==template.rows.size():at=0;phase=1;continue
			_adapt(at);at+=1;rows_adapted+=1
		elif phase==1:
			if at==template.sockets.size():at=0;phase=2;continue
			if template.components:_socket(template.sockets[at]);sockets_applied+=1
			at+=1
		else:
			if at==template.rows.size():phase=3;break
			_project(at);at+=1;rows_projected+=1
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(profile.max_slice_us,elapsed)
	if advanced and phase==3:_snapshot_work() # A completed worker packet already owns its profile.
	return phase==3

func _snapshot_work()->void:
	profile.rows_adapted=rows_adapted;profile.rows_projected=rows_projected;profile.sockets_applied=sockets_applied;profile.meshes_projected=meshes_projected

func dispose()->void:
	if phase<3:_snapshot_work()
	template={};record={};states={};local.clear();adapted.clear();poses.clear();specs.clear();phase=3
