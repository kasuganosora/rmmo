extends SceneTree
## Headless regression for light effects arriving during a sliced picking load.
const Lamps=preload("res://scripts/world3d/streetlamp_lights.gd")
const Walk=preload("res://scripts/world_editor/walk_mode.gd")
const Native=preload("res://scripts/world3d/compiled_asset_cache.gd")
var failures:=0

class EditorProbe:
	extends "res://scripts/world_editor/world_editor.gd"
	func _ready()->void:pass # Exercise production picking without opening a map/UI.

class WeatherProbe:
	extends Node
	var values:Dictionary={"time_hours":22.0}
	var night_sky:Dictionary={"ready":false}

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func fixture(parent:Node,name_:String,extras:Dictionary)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_;node.mesh=BoxMesh.new()
	var material:=StandardMaterial3D.new();node.mesh.material=material
	node.set_meta("extras",extras);parent.add_child(node);return node

func clear_bodies(editor:Node,uuid:String)->void:
	for body:Node in editor._bodies_by_uuid.get(uuid,[]):body.free()
	editor._bodies_by_uuid.erase(uuid)

func run()->void:
	var editor:=EditorProbe.new();root.add_child(editor)
	var holder:=Node3D.new();holder.set_meta("asset_uuid","fixture");editor.add_child(holder)
	var socket:Dictionary={"position":[0,.5,0],"color":[1,.8,.5],"range":4.0,"energy":.3,"flame":true,"indoor":true}
	var candle:=fixture(holder,"Candle",{"rmmo_model_light":socket})
	var crystal:=fixture(holder,"Crystal",{"rmmo_streetlamp_crystal":true})
	var ordinary:=fixture(holder,"AuthoredLightFlame",{})
	var authored_none:=fixture(holder,"StreetlampHalo",{"rmmo_collision":"none"})
	var camera:=Camera3D.new();root.add_child(camera)
	var weather:=WeatherProbe.new();root.add_child(weather)
	var controller:=Lamps.new();root.add_child(controller);controller.set_process(false)
	controller.weather=weather;controller.camera=camera
	Lamps.register(candle);Lamps.register(crystal)
	editor._add_bodies(holder)
	check(editor._bodies_by_uuid.fixture.size()==4,"initial authored lamp, crystal, same-name mesh and nonphysical mesh stay selectable")
	clear_bodies(editor,"fixture")
	# Take the ordinary initial plan before the controller adds its children,
	# reproducing the order of an asynchronous map reopen.
	var plan:Dictionary=editor._picking_plan(holder)
	controller.refresh()
	var flame:MeshInstance3D=candle.get_node("AuthoredLightFlame")
	var halo:MeshInstance3D=crystal.get_node("StreetlampHalo")
	check(flame.mesh!=null and halo.mesh!=null and flame.visible and halo.visible,"production flame and night halo are still rendered")
	check(controller.fixtures.size()==2 and controller.lights.size()==2 and controller.lights.all(func(light):return light.visible),"both original light fixtures remain lit")
	for effect:MeshInstance3D in [flame,halo]:
		check(effect.get_meta("runtime_light_effect",false) and not Walk.physical(effect.get_meta("extras",{})),"runtime_light_effect plus rmmo_collision=none excludes derived "+str(effect.name))
		check(not editor._picking_node_enabled(effect),"shared synchronous/sliced picking predicate excludes "+str(effect.name))
	var pending:Array[Node]=[holder]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		if not editor._picking_node_enabled(node):continue
		editor._add_bodies(node,false,plan)
		for child:Node in node.get_children():pending.append(child)
	check(editor._bodies_by_uuid.fixture.size()==4,"late-arriving effects add no pick or walk bodies during sliced traversal")
	check(editor._bodies_by_uuid.fixture.all(func(body):return body.get_meta("visual") not in [flame,halo]),"no body refers to either runtime effect")
	for source:MeshInstance3D in [candle,crystal,ordinary,authored_none]:
		var found:Array=editor._bodies_by_uuid.fixture.filter(func(body):return body.get_meta("visual")==source)
		check(found.size()==1,"authored fixture remains individually pickable: "+str(source.name))
		if found.size()==1:
			check(bool(found[0].collision_layer&Walk.WALK_MASK)==Walk.physical(source.get_meta("extras",{})),"original walk collision semantics retained: "+str(source.name))
	clear_bodies(editor,"fixture");editor._add_bodies(holder)
	check(editor._bodies_by_uuid.fixture.size()==4,"synchronous rebuild after effect discovery matches initial authored body count")
	weather.values.time_hours=12.;controller.refresh()
	check(flame.visible and not halo.visible,"indoor candle and daytime halo visibility unchanged")
	clear_bodies(editor,"fixture");editor._add_bodies(holder)
	check(editor._bodies_by_uuid.fixture.size()==4,"day/night toggles cannot change picking body count")
	print("NATIVE_GENERATOR ",Native.generator())
	controller.free();editor.free();weather.free();camera.free()
	await process_frame
	print("EDITOR_LIGHT_EFFECT_PICKING failures=",failures);quit(1 if failures else 0)
