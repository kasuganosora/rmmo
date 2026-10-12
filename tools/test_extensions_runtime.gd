extends SceneTree
## Load the saved HTTP fixtures through the production game loader and streamer.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	for path:String in OS.get_cmdline_user_args():
		var loader:=Loader.new();root.add_child(loader);loader.start(path)
		var result:Array=await loader.finished
		check(result[2].is_empty() and result[0]!=null,"game loads "+path.get_base_dir().get_file())
		if result[0]==null:loader.queue_free();continue
		var scene:Node3D=result[0];var host:=Node3D.new();root.add_child(host);host.add_child(scene)
		var records:Array=scene.get_meta("extras").rmmo_records
		var specs:Array=scene.get_meta("stream_library")
		for position:Vector3 in [Vector3.ZERO,Vector3(30,4,0),Vector3(0,4,90),Vector3(140,3,0),Vector3(300,3,0),Vector3(0,3,150)]:
			Stream.sync(scene,host,position)
			for i in 35:await process_frame
		var volume:Array=records.filter(func(r):return r.has("terrain_volume"))
		for r:Dictionary in volume:
			var found:Array=specs.filter(func(s):return s.uuid==r.uuid)
			check(found.size()==1 and found[0].mesh!=null and found[0].mesh.get_surface_count()>0,"volume geometry enters actual game stream")
			check(scene.get_meta("stream_bodies",{}).has(r.uuid),"volume actual game collision is resident")
		var crops:Array=records.filter(func(r):return r.get("vegetation_batch",false))
		if not crops.is_empty():
			Stream.sync(scene,host,Vector3.ZERO)
			for i in 100:await process_frame
			var batcher:=scene.get_node_or_null("GroundRenderBatches")
			check(batcher!=null and batcher.groups.values().any(func(g):return g.category=="vegetation" and is_instance_valid(g.get("visual")) and g.visual is MultiMeshInstance3D),"game publishes crop instancing batches")
		var gates:Array=records.filter(func(r):return r.has("fixture") and r.get("fortification",{}).get("id")=="water_arches")
		if not gates.is_empty():check(specs.filter(func(s):return s.get("extras",{}).has("fixture")).size()>=6,"game preserves independent grille fixtures")
		var ring_gates:Array=records.filter(func(r):return r.has("fixture") and str(r.get("fortification",{}).get("id","")).begins_with("ring_water_"))
		if not ring_gates.is_empty():check(specs.filter(func(s):return s.get("extras",{}).has("fixture")).size()>=ring_gates.size(),"game preserves all ring water gate hinges")
		host.queue_free()
		if is_instance_valid(loader):loader.queue_free()
		for i in 5:await process_frame
	print("EXTENSIONS_RUNTIME_FINISHED failures=",failures);quit(1 if failures else 0)
