extends SceneTree
## CPU/physics-only fixture: incremental observers, no user map or asset writes.
const Lights=preload("res://scripts/world3d/house_candle_lights.gd")
const Cutaway=preload("res://scripts/world3d/building_cutaway.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Rig=preload("res://scripts/world3d/third_person_camera.gd")
const World=preload("res://scripts/world3d/world_3d.gd")
class DeferredFixture extends Node:
	signal published(specs:Array)
	signal completed
	signal failed(reason:String)
	var _reference_index:Dictionary={}
	var _entry_loading:Dictionary={}
	var source_signatures:Dictionary={}
	func is_complete()->bool:return false
	func release_demand(_id:String)->void:pass
class NavigationFixture extends Node:
	var arrivals:=0
	var runtime_geometry_key:=""
	func set_geometry_pending(_value:bool)->bool:return true
	func configure_geometry_provider(_provider:Callable,_release:Callable)->void:pass
	func append_specs(_specs:Array)->Dictionary:
		arrivals+=1;return {"ok":true}
	func set_geometry_error(_reason:String)->void:pass
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func house(id:String,x:float)->Dictionary:
	var records:Array=[]
	for row in [["candle",2.15,0,"light_sconce"],["floor",4.0,1,"floor"],["roof",8.2,2,"roof"],["head",10.5,2,"roof"]]:
		var part:="roof/headhouse/ceiling" if row[0]=="head" else str(row[0])
		var size:Array=[.26,.54,.46] if row[0]=="candle" else [4.,.2,4.]
		records.append({"uuid":id+"_"+str(row[0]),"position":[x,row[1],0.],"rotation":[0.,0.,0.],"size":size,
			"building_shape":"candle_sconce" if row[0]=="candle" else "",
			"building":{"id":id,"part":part,"role":row[3],"floor":row[2],"floor_y":float(row[2])*4.}})
	var parts:Dictionary={}
	for record:Dictionary in records:parts[record.building.part]=record.uuid
	return {"records":records,"instance":{"parameters":Blueprint.defaults(),"position":[x,0.,0.],"yaw":0.,"version":8,"parts":parts}}

func specs(records:Array)->Array:
	var result:Array=[]
	for record:Dictionary in records:result.append({"uuid":record.uuid,"ground_batch_record":record})
	return result

func install(scene:Node3D,records:Array)->void:
	var meshes:Dictionary=scene.get_meta("stream_meshes",{})
	var bodies:Dictionary=scene.get_meta("stream_bodies",{})
	for record:Dictionary in records:
		var visual:=Node3D.new();scene.add_child(visual);visual.position=Blueprint.vec(record.position)
		meshes[record.uuid]=visual
		if record.building.part=="floor":
			var body:=StaticBody3D.new();scene.add_child(body);body.position=visual.position;body.set_meta("uuid",record.uuid)
			var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Blueprint.vec(record.size);collision.shape=shape;body.add_child(collision)
			bodies[record.uuid]=body
	scene.set_meta("stream_meshes",meshes);scene.set_meta("stream_bodies",bodies)

func run()->void:
	create_timer(40).timeout.connect(func():quit(2))
	var a:=house("house_a",0.);var b:=house("house_b",64.)
	var scene:=Node3D.new();root.add_child(scene)
	scene.set_meta("extras",{"building_instances":{"house_a":a.instance,"house_b":b.instance},"rmmo_records":a.records})
	install(scene,a.records)
	var lights:=Lights.new();root.add_child(lights);lights.set_process(false);lights.bind_map(scene)
	var cut:=Cutaway.new();cut.bind(scene)
	var rig:=Rig.new();rig.bind_map(scene,{})
	check(not rig.cutaway.enabled,"default camera cutaway remains disabled")
	# Bind the production signal path with CPU-only navigation/deferred doubles.
	# The world itself never enters the tree or starts a game/loading transaction.
	var world:=World.new();var queue:=DeferredFixture.new();queue.name="DeferredAssets";scene.add_child(queue)
	var live_navigation:=NavigationFixture.new();var staged_navigation:=NavigationFixture.new()
	root.add_child(live_navigation);root.add_child(staged_navigation)
	world._map_root=scene;world._navigation=live_navigation;world._house_candles=lights;world._camera=rig
	world._bind_deferred_geometry(scene,staged_navigation)
	queue.published.emit(specs(b.records))
	check(staged_navigation.arrivals==1 and lights.fixtures.size()==1 and rig.cutaway.buildings.house_b.parts.is_empty(),"staged transfer navigation cannot publish into live presentation observers")
	world._bind_deferred_geometry(scene,live_navigation)
	check(lights.fixtures.size()==1 and cut.buildings.house_a.parts.size()==4 and cut.buildings.house_b.parts.is_empty(),"initial partial map only registers resident components")
	var original_effect:Node3D=lights.fixtures[0].effect
	var original_parts:Dictionary=cut.buildings.house_a.parts
	var original_cells:Dictionary=cut.buildings.house_a.cells
	check(cut.buildings.house_a.parts.house_a_roof.size()==3,"cutaway keeps compact presentation data without frozen payload")
	cut.enabled=true
	await physics_frame;await physics_frame
	var room:Dictionary=cut.locate(Vector3.ZERO)
	cut.update(room,Vector3(0,2,0),Vector3(0,6,0),scene.get_world_3d().direct_space_state,[],.016)
	check(cut.target_cache.has("house_a:0") and cut.hidden.has("house_a_floor") and cut.hidden.has("house_a_roof"),"initial enabled cutaway hides slabs and upper parts through real physics query")
	check(cut.excluded.size()==1,"cutaway excludes the hidden floor body only from camera queries")
	var targets:Dictionary=cut.target_cache["house_a:0"]
	cut.target_cache["house_b:0"]={"old":true}
	install(scene,b.records)
	# Exercise the published-spec interface; no append to root records is needed.
	queue.published.emit(specs(b.records));cut.append_specs(scene,specs(b.records))
	check(live_navigation.arrivals==1 and staged_navigation.arrivals==2 and rig.cutaway.buildings.house_b.parts.size()==4,"production published callback updates live camera and lamps independently of HUD")
	check(lights.fixtures.size()==2 and lights._fixtures_by_id.house_a_candle.effect==original_effect,"late house adds exactly one effect and preserves existing effect identity")
	check(is_same(original_parts,cut.buildings.house_a.parts) and is_same(original_cells,cut.buildings.house_a.cells),"late house does not rebuild unrelated parts or spatial cells")
	check(is_same(targets,cut.target_cache["house_a:0"]) and not scene.get_meta("stream_meshes").house_a_roof.visible,"late house preserves another active room cache and hiding")
	check(not cut.target_cache.has("house_b:0") and cut.buildings.house_b.parts.size()==4,"late house invalidates only its stale room targets")
	check(cut.locate(Vector3(64,8.2,0)).get("key")=="house_b:headhouse","late roof headhouse participates in room lookup")
	var effect_b:Node3D=lights._fixtures_by_id.house_b_candle.effect
	cut.target_cache["house_b:0"]={"house_b_roof":true}
	var b_targets:Dictionary=cut.target_cache["house_b:0"]
	for i in 3:lights.append_specs(scene,specs(b.records));cut.append_specs(scene,specs(b.records))
	check(lights.fixtures.size()==2 and lights._fixtures_by_id.house_b_candle.effect==effect_b,"duplicate publications are idempotent")
	check(is_same(b_targets,cut.target_cache["house_b:0"]),"duplicate publications preserve unchanged target cache")
	lights.set_hours(0)
	check(lights.lit_count()==1,"only the nearby registered candle consumes the nighttime light budget")
	var observer:=Node3D.new();scene.add_child(observer);observer.position=Vector3(64,0,0);lights.observer=observer;lights.refresh()
	check(lights.lit_count()==1 and lights._fixtures_by_id.house_b_candle.light.visible,"late resident candle emits at night near its observer")
	lights.set_hours(12)
	var old_position:Vector3=effect_b.global_position
	scene.get_meta("stream_meshes").house_b_candle.position.x+=1.
	lights.refresh()
	check(lights.lit_count()==0 and effect_b.global_position==old_position and lights._day_settled,"stable daylight skips invisible candle transforms")
	lights.set_hours(0)
	check(is_equal_approx(effect_b.global_position.x,old_position.x+1.),"night transition refreshes a candle moved during daylight")
	await physics_frame;await physics_frame
	room=cut.locate(Vector3(64,0,0))
	cut.target_cache.erase("house_b:0")
	cut.update(room,Vector3(64,2,0),Vector3(64,6,0),scene.get_world_3d().direct_space_state,[],.016)
	check(cut.hidden.has("house_b_floor") and not cut.hidden.has("house_a_floor"),"entering late house switches cutaway to its actual parts")
	var late_floor:Node3D=scene.get_meta("stream_meshes").house_b_floor
	lights.remove_specs(scene,specs(b.records));cut.remove_specs(scene,specs(b.records))
	check(lights.fixtures.size()==1 and not effect_b.visible and effect_b.is_queued_for_deletion(),"retirement removes effect registry and hides pending freed nodes immediately")
	check(not cut.buildings.has("house_b") and cut.locate(Vector3(64,0,0)).is_empty(),"retirement removes affected building spatial registration")
	check(late_floor.visible and cut.hidden.is_empty() and cut.excluded.is_empty() and not cut.target_cache.has("house_b:0"),"retirement restores cutaway visibility and drops stale targets and body exclusions")
	lights.remove_specs(scene,specs(b.records));cut.remove_specs(scene,specs(b.records))
	check(lights.fixtures.size()==1 and cut.buildings.has("house_a"),"duplicate retirement leaves other house intact")
	lights.append_specs(scene,specs(b.records));cut.append_specs(scene,specs(b.records))
	check(lights.fixtures.size()==2 and lights._fixtures_by_id.house_b_candle.effect!=effect_b and cut.buildings.house_b.parts.size()==4,"return restores retired building registrations exactly once")
	check(cut.locate(Vector3(64,8.2,0)).get("key")=="house_b:headhouse","return rebuilds headhouse and spatial membership")
	var replacement:=Node3D.new();root.add_child(replacement)
	replacement.set_meta("extras",{"building_instances":{"house_a":a.instance},"rmmo_records":a.records})
	install(replacement,a.records)
	lights.bind_map(replacement);cut.bind(replacement)
	lights.append_specs(scene,specs(b.records));cut.append_specs(scene,specs(b.records))
	lights.remove_specs(scene,specs(a.records));cut.remove_specs(scene,specs(a.records))
	check(lights.fixtures.size()==1 and cut.buildings.size()==1 and cut.buildings.house_a.parts.size()==4,"stale arrivals and removals from outgoing map cannot affect replacement with same UUIDs")
	check(cut.target_cache.is_empty() and cut.hidden.is_empty() and cut.excluded.is_empty(),"map replacement clears all prior room visibility state")
	lights.bind_map(null);cut.bind(null)
	check(lights.fixtures.is_empty() and cut.buildings.is_empty() and cut.index.is_empty(),"map release clears observer registries")
	staged_navigation.free();live_navigation.free();world.free();rig.free()
	lights.free();scene.free();replacement.free()
	await process_frame
	print("HOUSE_STREAM_OBSERVERS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
