extends SceneTree
const Authority=preload("res://scripts/world3d/local_entry_authority.gd")
const Membership=preload("res://scripts/world3d/building_membership.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Gate=preload("res://scripts/world3d/entry_readiness.gd")
class Clock extends RefCounted:
	var value:=1000000
	func now()->int:return value
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func fixture()->Dictionary:
	var plan:Dictionary=Blueprint.generate({"template":"house","floors":2})
	var instance:Dictionary={"version":Blueprint.VERSION,"parameters":plan.parameters,"position":[31.0,0.0,0.0],"yaw":0.0,"parts":{},"signatures":{}}
	var records:Array=[]
	for source:Dictionary in plan.records:
		var r:Dictionary=source.duplicate(true);r.uuid="part_%d"%records.size();r.position[0]+=31.0;r.building.id="home"
		instance.parts[r.building.part]=r.uuid;instance.signatures[r.building.part]=Blueprint.geometry_signature(r);records.append(r)
	return {"rmmo_records":records,"building_instances":{"home":instance}}

func ready(authority:RefCounted,start:Dictionary)->Dictionary:
	var gate=Gate.new();var began:Dictionary=gate.begin(start.snapshot)
	check(began.ok,"gate accepts signed local snapshot")
	var ticket:Dictionary=gate.token()
	for stage:String in ["metadata","geometry","physics","render","base_gameplay"]:gate.mark(stage,ticket)
	if start.snapshot.membership=="indoor":
		var b:Dictionary=start.snapshot.building
		var receipt:Dictionary={"instance_id":b.instance_id,"structure_revision":b.structure_revision,"pose_revision":b.pose_revision,"state_sequence":b.state_watermark,"member_ids":b.member_ids.duplicate(),"fixture_states":b.fixture_states.duplicate(true),"structure_ready":true,"render_ready":true,"physics_synchronized":true,"interactions_bound":true}
		var partial:Dictionary=receipt.duplicate(true);partial.member_ids.pop_back()
		check(not gate.complete_building(partial,ticket).ok,"cross-chunk member omission cannot finish building")
		check(gate.complete_building(receipt,ticket).ok,"all exact building members accepted")
	check(gate.mark("first_frame",ticket).ok,"ready frame follows full geometry and dynamic state")
	check(not authority.authorize(start.ticket,gate.report(),Callable()).ok,"client readiness cannot replace authority occupancy check")
	return {"gate":gate,"ticket":ticket}

func run()->void:
	var meta:=fixture();var built:=Membership.build(meta)
	check(built.ok,"catalogue uses real generated building recipe")
	if not built.ok:quit(1);return
	check(built.buildings.home.semantic_ready,"complete recipe has floor and entrance semantics")
	check(Membership.locate(built,Vector3(31,4.0,0)).membership=="indoor","second floor belongs to exact building")
	check(Membership.locate(built,Vector3(31,9,0)).membership=="outdoor","open roof is not an interior")
	check(Membership.locate(built,Vector3(31,0,15)).membership=="outdoor","yard is not an interior")
	check(Membership.locate(built,Vector3(31,-3,0)).membership=="outdoor","space below floor is not an interior")
	var translated:=meta.duplicate(true);translated.building_instances.home.position[1]+=3.0
	for r:Dictionary in translated.rmmo_records:
		r.position[1]+=3.0;r.building.floor_y+=3.0;translated.building_instances.home.signatures[r.building.part]=Blueprint.geometry_signature(r)
	var shifted:=Membership.build(translated)
	check(shifted.buildings.home.structure_revision==built.buildings.home.structure_revision and shifted.buildings.home.pose_revision!=built.buildings.home.pose_revision,"moving a whole building changes pose but preserves structural identity")
	var missing:=meta.duplicate(true);missing.rmmo_records.pop_back()
	check(Membership.locate(Membership.build(missing),Vector3(31,4,0)).membership=="unresolved","missing member never grants indoor or outdoor")
	var moved:=meta.duplicate(true);moved.rmmo_records[0].position[0]+=1
	check(Membership.locate(Membership.build(moved),Vector3(31,4,0)).membership=="unresolved","hand-edited geometry cannot inherit recipe interior proof")
	var unknown:=Membership.build(meta,{},[AABB(Vector3(100,0,100),Vector3(10,10,10))])
	check(Membership.locate(unknown,Vector3(105,2,105)).membership=="unresolved","unannotated imported building cannot default outside")
	var clock:=Clock.new();var authority:=Authority.new(clock.now)
	check(authority.register_map("town","rev1",meta).ok,"register complete map in local server state")
	check(authority.capabilities().protocol_version==1 and not authority.capabilities().persistent_reconnect,"capability explicitly separates local state from disk persistence")
	var start:Dictionary=authority.begin("s","w","town","rev1",Vector3(31,4,0))
	check(start.ok and start.membership_resolved and start.required_group=="building:home","authority issues exact index building group")
	check(start.required_bounds.position.x<32 and start.required_bounds.end.x>32,"group closure crosses logical chunk boundary")
	check(start.required_members.size()==meta.rmmo_records.size(),"complete building requested independent of current chunk")
	var valid:=ready(authority,start)
	check(authority.authorize(start.ticket,valid.gate.report(),func(_snapshot):return true).ok,"exact current transaction permits activation")
	check(authority.authorize(start.ticket,valid.gate.report(),func(_snapshot):return true).duplicate,"activation replay is idempotent")
	var corrupted:Dictionary=valid.gate.report();corrupted.token.position_m[0]+=1
	check(not authority.authorize(start.ticket,corrupted,func(_snapshot):return true).ok,"same epoch report at a different position is rejected")
	var reconnected:Dictionary=authority.reconnect("s","w",start.snapshot)
	check(reconnected.ok and reconnected.ticket.epoch>start.ticket.epoch,"reconnection creates new epoch")
	check(not authority.validate(start.ticket).ok,"old completion rejected after reconnect")
	check(authority.cancel(reconnected.ticket).ok and not authority.validate(reconnected.ticket).ok,"cancel invalidates late worker reports")
	start=authority.begin("s","w","town","rev1",Vector3(31,4,0))
	var fixture_id:String=start.snapshot.building.fixture_states.keys()[0]
	var amount:float=1.0-float(start.snapshot.building.fixture_states[fixture_id])
	var change:Dictionary=authority.update_fixture("town","rev1","home",fixture_id,amount,0)
	check(change.ok and change.building.state_watermark==1,"door update has independent sequence")
	check(change.building.structure_revision==start.snapshot.building.structure_revision and change.building.pose_revision==start.snapshot.building.pose_revision,"door update does not change structure or pose identity")
	check(not authority.update_fixture("town","rev1","home",fixture_id,0,0).ok,"out-of-order door event rejected")
	valid=ready(authority,start)
	check(authority.authorize(start.ticket,valid.gate.report(),func(_snapshot):return true).state_watermark==0,"activation uses fixed cut without chasing newer door events")
	check(authority.state_snapshot(start.ticket).building.state_watermark==1,"new dynamic state remains available after fixed cut activation")
	check(authority.register_map("town","rev1",meta).ok and authority.state_snapshot(start.ticket).building.state_watermark==1,"scene re-registration preserves authoritative door state")
	var checkpoint:Dictionary=authority.position_snapshot("town","rev1",Vector3(31,4,0))
	check(checkpoint.ok and checkpoint.snapshot.building.state_watermark==1 and authority.validate(start.ticket).ok,"ordinary position checkpoint preserves epoch and current fixture sequence")
	check(not authority.authorize(start.ticket,valid.gate.report(),func(_snapshot):return false).ok,"invalidated support cannot restore or activate position")
	var other:=authority.begin("s2","w","town","rev1",Vector3(90,0,90))
	authority.cancel(start.ticket)
	check(authority.validate(other.ticket).ok,"loading cancellation affects only one session")
	start=authority.begin("s","w","town","rev1",Vector3(31,4,0))
	authority.register_map("town","rev2",meta)
	check(not authority.validate(start.ticket).ok,"map revision invalidates prepared building")
	check(not authority.begin_recovery("s","w",start.snapshot).ok,"failed transfer cannot restore changed original map")
	var indoor:Dictionary=authority.begin("s","w","town","rev2",Vector3(31,4,0))
	authority.register_map("town","rev2",translated)
	check(not authority.validate(indoor.ticket).ok and not authority.begin_recovery("s","w",indoor.snapshot).ok,"changed original building pose prevents stale activation and recovery")
	var relocated:Dictionary=authority.position_snapshot("town","rev2",Vector3(31,7,0))
	check(relocated.ok and relocated.snapshot.building.state_watermark==1,"moving the same structure preserves dynamic fixture state")
	start=authority.begin("s","w","town","rev2",Vector3(31,4,0),"entry",1)
	clock.value+=1000
	check(not authority.validate(start.ticket).ok,"pending authority transaction has bounded deadline")
	authority.clear()
	check(not authority.validate(other.ticket).ok,"new server session rejects every prior ticket")
	await evidence()
	print("RESULT ",checks," checks ",failures," failures")
	quit(1 if failures else 0)

func evidence()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new();scene.add_child(mesh)
	var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape);scene.add_child(body)
	var spec:Dictionary={"uuid":"one","transform":Transform3D.IDENTITY,"extras":{"uuid":"one","building":{"id":"h"},"rmmo_collision":"walk"}}
	scene.set_meta("stream_library",[spec])
	var snapshot:Dictionary={"membership":"indoor","building":{"instance_id":"h","structure_revision":"s","pose_revision":"p","state_watermark":0,"member_ids":["one"],"fixture_states":{}}}
	var authority:=Authority.new()
	check(not authority.inspect_root(snapshot,scene,2,1).ok,"parsed CPU spec is not render or physics readiness")
	scene.set_meta("stream_meshes",{"one":mesh});scene.set_meta("stream_bodies",{"one":body})
	body.set_meta("stream_physics_published_frame",Engine.get_physics_frames())
	var published:int=Engine.get_physics_frames()
	check(not authority.inspect_root(snapshot,scene,published,published).physics_synchronized,"same frame cannot prove physics synchronization")
	await physics_frame;await physics_frame
	check(authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).ok,"actual render body and later physics tick complete evidence")
	body.collision_layer=0
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).physics_synchronized,"disabled collision layer cannot pass body evidence")
	body.collision_layer=1
	shape.disabled=true
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).physics_synchronized,"disabled shapes cannot pass body evidence")
	shape.disabled=false
	body.remove_meta("stream_physics_published_frame")
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).physics_synchronized,"caller frame cannot fabricate a missing body publication receipt")
	body.set_meta("stream_physics_published_frame",published)
	spec.closed_transform=Transform3D.IDENTITY;spec.extras.fixture={"id":"door","kind":"door","pivot":[0,0,0],"angle":90.0,"open":0.0}
	snapshot.building.fixture_states={"door":1.0}
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).interactions_bound,"old door state cannot pass newer authority watermark")
	spec.extras.fixture.open=1.0
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).interactions_bound,"new door scalar without transformed render object is not applied")
	spec.transform=preload("res://scripts/world3d/building_fixtures.gd").pose(Transform3D.IDENTITY,spec.extras.fixture,1.0);mesh.transform=spec.transform;body.transform=spec.transform
	check(authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).interactions_bound,"matching applied door pose and state produce interaction evidence")
	snapshot.building.member_ids.append("missing_second_chunk")
	check(not authority.inspect_root(snapshot,scene,Engine.get_physics_frames(),published).structure_ready,"resident first chunk cannot hide missing distant member")
	scene.free()
