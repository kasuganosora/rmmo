extends SceneTree
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Ready=preload("res://scripts/world3d/model_texture_readiness.gd")
const SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const PAYLOAD="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var scene:=Node3D.new();scene.set_meta(Binding.TABLE_META,SHA)
	var material:=StandardMaterial3D.new();material.resource_local_to_scene=true
	material.set_meta(Binding.BINDINGS_META,{"albedo_texture":{"id":SHA,"normal":false}})
	var part:=MeshInstance3D.new();part.mesh=BoxMesh.new();part.material_override=material
	scene.add_child(part);part.owner=scene
	var packed:=PackedScene.new();packed.pack(scene);scene.free()
	packed.set_meta("compiled_asset_validated",true);packed.set_meta("_rmmo_native_audited",true)
	packed.set_meta("_rmmo_source_digest",SHA);packed.set_meta("_rmmo_native_payload_sha",PAYLOAD);packed.set_meta("_rmmo_native_generator","fixture")
	var path:="user://native-readiness-fixture.scn"
	check(not Assets.cache_packed(path,packed,SHA),"unbound split scene cannot enter the global ready cache")
	Assets._scenes[path]=packed # Simulate an old/synchronous consumer's polluted cache.
	check(not Assets._native_cached(path,{"source_sha":SHA,"payload_sha":PAYLOAD,"generator":"fixture","texture_table":{"sha256":SHA}}),"old unbound cache owner cannot satisfy native readiness")
	Assets._scenes.erase(path)
	var private:=Compiled.instantiate(packed)
	var private_material:StandardMaterial3D=private.get_child(0).material_override
	check(private_material!=material and private_material.albedo_texture==null,"private preparation has actual local-to-scene material copies")
	check(not Assets.cache_scene(path,private,SHA),"unbound private graph cannot be repacked into a ready cache entry")
	var texture:=GradientTexture2D.new()
	var binding:=Binding.begin_scene(private,{SHA:"source"},SHA)
	check(binding.ok and binding.visited_materials==1,"private binding walks actual instance material once")
	check(not Ready.scene_ready(private) and not Ready.packed_ready(packed),"neither source nor private graph is ready before adoption")
	check(Binding.adopt(binding,{"source":texture}) and not Ready.scene_ready(private),"dependency adoption alone does not mark completion")
	check(Binding.step(binding)==Binding.READY and Ready.scene_ready(private),"last setter marks this private graph ready")
	check(private_material.albedo_texture==texture and material.albedo_texture==null and not Ready.packed_ready(packed),"binding private local material does not falsely mark the unbound source")
	Binding.release(binding)
	check(Assets.cache_scene(path,private,SHA),"complete private scene preserves readiness through normal cache repacking")
	private=null
	var candidate:={"source_sha":SHA,"payload_sha":PAYLOAD,"generator":"fixture","texture_table":{"sha256":SHA}}
	check(Assets._native_cached(path,candidate),"fully bound native cache satisfies matching table identity")
	var replacement:=candidate.duplicate(true);replacement.texture_table.sha256=PAYLOAD
	check(not Assets._native_cached(path,replacement),"changed table cannot reuse an older bound material graph")
	var cached:PackedScene=Assets._scenes[path]
	var reopened:=Compiled.instantiate(cached)
	check(Ready.scene_ready(reopened) and reopened.get_child(0).material_override.albedo_texture==texture,"re-instantiation preserves readiness and exact shared texture owner")
	reopened.free();Assets._scenes.erase(path)
	var packed_binding:=Binding.begin(packed,{SHA:"source"},SHA)
	Binding.adopt(packed_binding,{"source":texture})
	check(Binding.step(packed_binding)==Binding.READY and Ready.packed_ready(packed),"direct packed binding writes runtime completion only after finishing")
	check(Assets.cache_packed(path,packed,SHA),"fully bound packed graph can be published")
	for index:int in 2:
		var direct:=Assets._instantiate(packed)
		check(Ready.scene_ready(direct) and direct.get_child(0).material_override.albedo_texture==texture,"public cached instance %d retains its binding completion"%index)
		direct.free()
	Binding.release(packed_binding);Assets._scenes.erase(path)
	var empty:=Node3D.new();empty.set_meta(Binding.TABLE_META,SHA)
	var empty_packed:=PackedScene.new();empty_packed.pack(empty);empty.free()
	var empty_binding:=Binding.begin(empty_packed,{},SHA);Binding.adopt(empty_binding,{})
	check(not Ready.packed_ready(empty_packed) and Binding.step(empty_binding)==Binding.READY and Ready.packed_ready(empty_packed),"zero-texture split table still completes its binding transaction")
	Binding.release(empty_binding)
	var forged:=empty_packed.instantiate();forged.set_meta(Ready.READY_META,SHA)
	var from_disk:=PackedScene.new();from_disk.pack(forged);forged.free()
	var unproven:=Compiled.instantiate(from_disk)
	check(not Ready.scene_ready(unproven),"authored node metadata cannot counterfeit a runtime completion")
	unproven.free()
	print("NATIVE_TEXTURE_READINESS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
