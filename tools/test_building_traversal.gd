extends "res://tools/test_local_entry_authority.gd"
const Barrier=preload("res://scripts/world3d/building_traversal_barrier.gd")
class FakeWorld extends Node3D:
	var _map_root:Node3D
	var _player:CharacterBody3D
	var _building_entry:RefCounted
	var _transfer_pending:=false
	func _building_movement_allowed()->bool:return true

func parent_entry(authority:RefCounted)->Dictionary:
	var issued:Dictionary=authority.begin("main","world","town","r1",Vector3.ZERO)
	var proof:=ready(authority,issued)
	check(authority.authorize(issued.ticket,proof.gate.report(),func(_s):return true).ok,"parent world is active before traversal requests")
	proof.gate.authorize_activation(proof.ticket)
	return {"issued":issued,"gate":proof.gate}

func run()->void:
	var timeout:=Timer.new();timeout.wait_time=30;timeout.one_shot=true;root.add_child(timeout);timeout.timeout.connect(func():quit(2));timeout.start()
	var meta:=fixture();var authority:=Authority.new();authority.register_map("town","r1",meta)
	var parent:=parent_entry(authority);var feet:=Vector3(20,0,0)
	var forward:=AABB(Vector3(19,-.4,-1),Vector3(15,3,2))
	var retreat:=AABB(Vector3(18,-.4,-1),Vector3(3,3,2))
	var need:Dictionary=authority.traversal_requirements(parent.issued.ticket,feet,forward)
	check(need.ok and need.buildings.has("home"),"swept footprint requests building before origin enters its interior")
	check(authority.position_snapshot("town","r1",feet).snapshot.membership=="outdoor","prediction does not relabel current outdoor membership")
	var issued:Dictionary=authority.begin_traversal(parent.issued.ticket,feet,forward,"home")
	check(issued.ok and issued.ticket.purpose=="building_traversal" and issued.ticket.anchor_epoch==parent.issued.ticket.epoch,"permit binds readiness purpose and parent activation epoch")
	var proof:=ready(authority,issued)
	check(not authority.authorize(issued.ticket,proof.gate.report(),func(_s):return true).ok,"readiness permit cannot invoke ordinary player activation")
	check(not authority.authorize_traversal(issued.ticket,proof.gate.report(),feet+Vector3(1,0,0),func(_s):return true).ok,"changed authority origin rejects late readiness completion")
	check(not authority.authorize_traversal(issued.ticket,proof.gate.report(),feet,func(_s):return false).ok,"ready report still requires independent current-world check")
	check(authority.authorize_traversal(issued.ticket,proof.gate.report(),feet,func(_s):return true).ok,"all building gates grant only scoped traversal readiness")
	check(authority.validate(parent.issued.ticket).ok,"child permit does not replace active player transaction")
	var fixture_id:String=issued.snapshot.building.fixture_states.keys()[0]
	var state:Dictionary=authority.update_fixture("town","r1","home",fixture_id,1-float(issued.snapshot.building.fixture_states[fixture_id]),0)
	check(state.ok and authority.state_snapshot(issued.ticket).building.state_watermark==1,"pending or active permit exposes newer authoritative door state")
	var world:=FakeWorld.new();root.add_child(world)
	world._map_root=Node3D.new();world.add_child(world._map_root)
	world._player=CharacterBody3D.new();world.add_child(world._player);world._player.position=feet+Vector3.UP*.9
	var tx=preload("res://scripts/world3d/building_entry_transaction.gd").new();tx.issued=parent.issued;tx.gate=parent.gate;world._building_entry=tx
	var barrier:=Barrier.new();barrier.setup(world,world._map_root,authority,parent.issued.ticket)
	check(not barrier.guard(forward,feet).ok and barrier.attempts.size()==1,"boundary guard creates asynchronous whole-building preparation")
	var walk:Dictionary=barrier.attempts.home.transaction.issued.ticket.duplicate(true)
	check(not world._map_root.get_meta("stream_sources",{}).is_empty(),"building collision residency spans every required chunk while waiting")
	check(barrier.guard(retreat,feet).ok and barrier.attempts.is_empty(),"turning away immediately permits known outdoor retreat")
	check(world._map_root.get_meta("stream_sources",{}).is_empty() and not authority.validate(walk).ok,"turning away releases pins and rejects stale completion")
	barrier.guard(forward,feet)
	var next:Dictionary=barrier.attempts.home.transaction.issued.ticket.duplicate(true)
	check(next.epoch>walk.epoch,"returning toward building receives fresh bounded attempt")
	barrier.dispose();world.free()
	var unknown:=Membership.build(meta,{},[AABB(Vector3(19,0,0),Vector3(2,4,2))])
	check(not Membership.sweep(unknown,AABB(Vector3(18,-.1,0),Vector3(3,2,1))).ok,"unresolved semantic region denies forward sweep")
	check(Membership.sweep(unknown,AABB(Vector3(15,-.1,0),Vector3(2,2,1))).ok,"unresolved query does not poison neighboring ready outdoor region")
	authority.register_map("edge","r1",meta,{},[AABB(Vector3(0,0,0),Vector3(2,4,2))])
	check(authority.position_snapshot("edge","r1",Vector3(-.5,0,1)).snapshot.membership=="outdoor" and not authority.footprint_requirements("edge","r1",AABB(Vector3(-1.22,-.4,.28),Vector3(1.44,2.6,1.44))).ok,"feet-only outside cannot authorize an entry whose motion footprint already overlaps unknown")
	check(authority.footprint_requirements("edge","r1",AABB(Vector3(-2.72,-.4,.28),Vector3(1.44,2.6,1.44))).ok,"known safe starting footprint retains a valid retreat path")
	check(Membership.sweep(Membership.build(meta),AABB(Vector3(31,9,0),Vector3(1,1,1))).buildings.is_empty(),"open roof height does not become an indoor sweep")
	var many:=meta.duplicate(true)
	var second:Dictionary=meta.building_instances.home.duplicate(true);second.position[0]+=30;second.parts={};second.signatures={}
	for source:Dictionary in meta.rmmo_records:
		var r:=source.duplicate(true);r.uuid="other_"+r.uuid;r.position[0]+=30;r.building.id="other"
		second.parts[r.building.part]=r.uuid;second.signatures[r.building.part]=Blueprint.geometry_signature(r);many.rmmo_records.append(r)
	many.building_instances["other"]=second
	var catalogue:=Membership.build(many)
	var both:=Membership.sweep(catalogue,AABB(Vector3(20,-.1,-1),Vector3(50,2,2)))
	check(both.get("buildings",{}).size()==2,"one prediction preserves obligations for both intersecting buildings")
	check(Membership.sweep(catalogue,AABB(Vector3(5000,0,0),Vector3(2,2,2))).get("candidate_count",-1)==0,"spatial directory avoids scanning distant buildings per intent")
	var overlapping:=many.duplicate(true);overlapping.building_instances["other"].position[0]-=30
	for r:Dictionary in overlapping.rmmo_records:
		if r.building.id!="other":continue
		r.position[0]-=30;overlapping.building_instances["other"].signatures[r.building.part]=Blueprint.geometry_signature(r)
	check(authority.register_map("town","r1",overlapping).ok,"individually valid overlapping building definitions remain representable")
	var ambiguous:Dictionary=authority.begin_traversal(parent.issued.ticket,feet,forward,"home")
	check(not ambiguous.ok and ambiguous.reason=="membership_unresolved","overlapping interiors cannot issue an ambiguous traversal permit")
	check(authority.validate(parent.issued.ticket).ok,"ambiguous destination cannot revoke the known outdoor activation")
	var superseding:Dictionary=authority.begin("main","world","town","r1",Vector3.ZERO,"new_transfer")
	check(superseding.ok and not authority.validate(issued.ticket).ok,"new parent transfer invalidates old traversal readiness")
	print("BUILDING_TRAVERSAL_CPU checks=",checks," failures=",failures)
	quit(1 if failures else 0)
