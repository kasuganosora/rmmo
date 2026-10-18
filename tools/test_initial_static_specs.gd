extends SceneTree
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func asset()->Node3D:
	var result:=Node3D.new();result.name="Imported";result.transform=Transform3D(Basis(Vector3.UP,.63).scaled(Vector3(1.1,.9,1.2)),Vector3(156,7.5,209))
	var group:=Node3D.new();group.name="Floor";group.rotation_degrees=Vector3(8,32,-4);group.position=Vector3(4,1.2,-3);result.add_child(group)
	for i:int in 8:
		var box:=BoxMesh.new();box.size=Vector3(1+i*.1,2,.4)
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,box.surface_get_arrays(0));mesh.surface_set_material(0,StandardMaterial3D.new())
		var node:=MeshInstance3D.new();node.name="Part%d"%i;node.mesh=mesh;node.position=Vector3(i*.4,0,0);node.rotation_degrees=Vector3(0,i*13,0)
		var extra:Dictionary={"uuid":"asset__part%d"%i,"rmmo_collision":"block","building":{"id":"asset","floor":i%2,"part":"body%d"%i,"role":"body"}}
		if i==1:extra.fixture={"id":"door","kind":"door","pivot":[0,0,0],"angle":90,"open":.4}
		node.set_meta("extras",extra);node.set_meta("map_draw_order",1234+i)
		node.set_meta("ground_batch_record",{"uuid":extra.uuid,"kind":"box","building":extra.building,"size":[1,2,.4],"surface_id":"block"})
		group.add_child(node)
	return result
func run()->void:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.disable_3d=true;root.add_child(viewport)
	var original:=asset()
	var baseline:=Node3D.new();viewport.add_child(baseline);baseline.add_child(original)
	var candidate:=Node3D.new();var copy:=original.duplicate();candidate.add_child(copy)
	var compiled_owner:=PackedScene.new();var owner_watch:WeakRef=weakref(compiled_owner)
	copy.set_meta("_compiled_resource_owner",compiled_owner);compiled_owner=null
	var before:Array=[];Stream._adopt(baseline,before,{})
	var loader:=Loader.new();root.add_child(loader)
	var after:Array=[];var parts:Array=Paint.meshes(copy)
	check(await loader._prepare_static_asset_specs(candidate,copy,parts,after),"private static asset projection completes without entering a world")
	check(not candidate.is_inside_tree() and Paint.meshes(candidate).is_empty() and after.size()==before.size(),"only complete specs leave preparation; disposable render nodes never enter a live scenario")
	check(not copy.has_meta("_compiled_resource_owner") and owner_watch.get_ref()==null,"empty imported holders release their compiled PackedScene owner after spec transfer")
	var by_id:Dictionary={}
	for row:Dictionary in before:by_id[row.uuid]=row
	for row:Dictionary in after:
		var old:Dictionary=by_id.get(row.uuid,{})
		check(not old.is_empty() and row.transform.is_equal_approx(old.transform) and row.position.is_equal_approx(old.position),"same hierarchical world pose "+str(row.uuid))
		check(row.chunk_min==old.chunk_min and row.chunk_max==old.chunk_max and row.extras==old.extras and row.map_draw_order==old.map_draw_order and row.cast_shadow==old.cast_shadow,"same bounds, membership, draw order and shadow policy "+str(row.uuid))
		check(row.mesh==old.mesh and row.material_override==old.material_override and row.surface_overrides==old.surface_overrides and row.collision_mesh==old.collision_mesh,"same render/material/collision allocations "+str(row.uuid))
		if row.has("closed_transform"):check(row.closed_transform.is_equal_approx(old.closed_transform),"hinge closed pose remains exact")
	candidate.free();viewport.free()
	var native_root:=Node3D.new();var native:=asset();native_root.add_child(native);native.add_child(OmniLight3D.new())
	native.set_meta("_compiled_resource_owner",PackedScene.new())
	var retained:Array=[]
	check(await loader._prepare_static_asset_specs(native_root,native,Paint.meshes(native),retained) and retained.is_empty() and not Paint.meshes(native_root).is_empty(),"native light graph retains ordinary graph adoption and all nodes")
	check(native.has_meta("_compiled_resource_owner"),"actual native graph retains its compiled owner")
	native_root.free();loader.free()
	print("INITIAL_STATIC_SPECS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
