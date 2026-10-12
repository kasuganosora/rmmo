extends SceneTree
## Headless ownership/order only. This is not renderer/RID acceptance.
const Preview=preload("res://scripts/world_editor/asset_preview.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var failed:=0
var checks:=0
var deaths:Array=[]

class DeathProbe extends Resource:
	var node_id:int
	var events:Array
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and events!=null:
			events.append({"main":OS.get_thread_caller_id()==OS.get_main_thread_id(),"node_alive":is_instance_id_valid(node_id)})

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failed+=1
	print("PASS " if value else "FAIL ",label)
func model()->Node3D:
	var value:=Node3D.new()
	var visual:=MeshInstance3D.new();visual.mesh=BoxMesh.new();value.add_child(visual)
	var material:=StandardMaterial3D.new();var probe:=DeathProbe.new()
	probe.node_id=visual.get_instance_id();probe.events=deaths
	material.set_meta("retirement_probe",probe);visual.material_override=material
	return value
func valid_retirement()->bool:
	return deaths.size()==1 and deaths[0].main and not deaths[0].node_alive

func run()->void:
	var preview:=Preview.new();root.add_child(preview)
	preview.scene=model();preview.viewport_.add_child(preview.scene)
	var original:=preview.scene.get_instance_id()
	preview.current_path="old-private-preview"
	preview.show_asset("")
	check(preview.scene==null and not is_instance_id_valid(original),"switching preview disposes its owned node")
	check(valid_retirement(),"preview keeps material alive until visual destruction on main")
	deaths.clear()
	preview.scene=model();preview.viewport_.add_child(preview.scene);original=preview.scene.get_instance_id()
	root.remove_child(preview)
	check(preview.scene==null and not is_instance_id_valid(original),"removing preview retires model before viewport destruction")
	check(valid_retirement(),"preview exit uses the same retirement order")
	preview.free();deaths.clear()
	preview=Preview.new();root.add_child(preview)
	var adopted:=model();preview.scene=adopted;root.add_child(adopted)
	preview._dispose_scene()
	check(preview.scene==null and is_instance_valid(adopted) and adopted.get_parent()==root,"preview does not destroy a reparented consumer")
	root.remove_child(adopted);Drainer.dispose_scene(adopted);preview.free();deaths.clear()

	var thumbs:=Thumbnails.new();root.add_child(thumbs)
	thumbs._model=model();thumbs._viewport.add_child(thumbs._model);original=thumbs._model.get_instance_id()
	thumbs._dispose_model()
	check(thumbs._model==null and not is_instance_id_valid(original),"thumbnail retirement releases only its private model")
	check(valid_retirement(),"thumbnail retains material through visual destruction on main")
	deaths.clear()
	thumbs._model=model();thumbs._viewport.add_child(thumbs._model);original=thumbs._model.get_instance_id()
	thumbs._busy=true
	process_frame.connect(thumbs._render,CONNECT_ONE_SHOT)
	RenderingServer.frame_post_draw.connect(thumbs._finish,CONNECT_ONE_SHOT)
	root.remove_child(thumbs)
	check(not process_frame.is_connected(thumbs._render) and not RenderingServer.frame_post_draw.is_connected(thumbs._finish),"thumbnail exit disconnects delayed renderer callbacks")
	check(not thumbs._busy and thumbs._model==null and not is_instance_id_valid(original) and valid_retirement(),"thumbnail exit retires live model and clears state")
	thumbs.free();deaths.clear()
	thumbs=Thumbnails.new();root.add_child(thumbs)
	adopted=model();thumbs._model=adopted;root.add_child(adopted)
	thumbs._dispose_model()
	check(thumbs._model==null and is_instance_valid(adopted) and adopted.get_parent()==root,"thumbnail cleanup does not free a different owner's node")
	root.remove_child(adopted);Drainer.dispose_scene(adopted);thumbs.free()
	print("PREVIEW_OWNED_CLEANUP checks=%d failures=%d"%[checks,failed])
	quit(1 if failed else 0)
