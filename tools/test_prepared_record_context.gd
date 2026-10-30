extends "res://tools/test_editor_native_sequential_requests.gd"
const Context=preload("res://scripts/world3d/prepared_record_context.gd")
const Deps=preload("res://scripts/world3d/record_asset_dependencies.gd")
const Kit=preload("res://scripts/world3d/auto_tile_kit.gd")
const Rules=preload("res://scripts/world3d/auto_tile_rules.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")

func dependency_case()->void:
	var path:=content_root.path_join("kit.glb");var edge:=content_root.path_join("edge.glb")
	var record:=tile_record(path)
	var alias:={"kind":"asset","asset_path":content_root.path_join("./kit.glb")}
	check(Deps.paths([record,alias]).size()==1,"collector canonicalizes and deduplicates ordinary/kit aliases")
	var cliff:={"tile3d":{"family":"cliff","drops":[0,0,0,0],"options":{"kit":{"version":1,"name":"cliff","family":"cliff","pieces":{"top":path,"edge":edge}}}}}
	check(Deps.paths([record,cliff])==[path],"flat cliff collects its actual top without an unused edge")
	cliff.tile3d.drops[2]=1
	check(Deps.paths([record,cliff])==[path,edge],"cliff edge is requested when an actual side uses it")
	var road:={"tile3d":{"family":"road","mask":5,"options":{"kit":{"version":1,"name":"road","family":"road","pieces":{"0":path,"1":path,"3":path,"5":edge,"7":path,"15":path}}}}}
	check(Deps.paths([road])==[edge],"collector selects the rotated mask variant instead of every kit variant")
	check(not Deps.has_models({"kind":"asset","asset_path":path,"house_prefab":{}}),"inline generated assets do not introduce a model request")

func triangle_model(vertices:int,surfaces:int)->Node3D:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var positions:=PackedVector3Array();positions.resize(vertices)
	var triangle:=[Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]
	for index:int in vertices:positions[index]=triangle[index%3]
	arrays[Mesh.ARRAY_VERTEX]=positions
	var mesh:=ArrayMesh.new()
	for index:int in surfaces:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var model:=Node3D.new();var node:=MeshInstance3D.new();node.mesh=mesh;model.add_child(node);node.owner=model
	return model

func geometry_limits_case()->void:
	var model:=triangle_model(3,17);var output:=Kit._piece_from_scene(model)
	check(output!=null and output.get_surface_count()==17,"17 legitimate surfaces are not rejected by the former kit-only cap")
	var packed:=PackedScene.new();check(packed.pack(model)==OK,"context fixture packs the real 17-surface mesh")
	check(not model.get_child(0).mesh.has_meta("_compiled_resource_owners"),"native source mesh has no reverse owner reference")
	model.free();output=null
	model=triangle_model(50001,1);output=Kit._piece_from_scene(model)
	check(output!=null and output.surface_get_array_len(0)==50001,"50001 legitimate vertices survive the former kit-only cap")
	var replacement:=PackedScene.new();replacement.pack(model);model.free();output=null
	var path:=content_root.path_join("context.glb");var context:=Context.new({path:packed})
	var first:=context.piece(path)
	context.accept(path,packed)
	check(context.piece(path)==first,"accepting the same template preserves operation-local piece identity")
	context.accept(path,replacement)
	var next:=context.piece(path)
	check(next!=first and next.surface_get_array_len(0)==50001,"accepting another template invalidates only its derived piece")
	model=triangle_model(3,RenderingServer.MAX_MESH_SURFACES)
	var extra:=MeshInstance3D.new();var extra_mesh:=ArrayMesh.new();extra_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,first.surface_get_arrays(0));extra.mesh=extra_mesh;model.add_child(extra)
	check(Kit._piece_from_scene(model)==null,"actual engine surface ceiling is rejected before an invalid GPU append")
	model.free()

func tile_record(path:String)->Dictionary:
	var doc:=Doc.new();var id:=doc.add_box_silent("ground",Vector3.ZERO,Vector3.ONE)
	var record:Dictionary=doc._find(id)
	Rules.configure(record,Vector2i.ZERO,"stairs",1.,0.,{"rise":1.,"direction":0,"kit":{"version":1,"name":"native kit","family":"stairs","pieces":{"default":path}}})
	record.collision="none"
	return record

func make_spec(path:String,reference:WeakRef,kind:String)->Dictionary:
	var context:=Context.new({path:reference.get_ref()})
	var doc:=Doc.new();var record:=tile_record(path)
	if kind=="paint":
		var base:MeshInstance3D=doc._mesh(record,true,null,context)
		var geometry:Dictionary=Paint.geometry(base)
		record.surface_paint=[]
		for face:Variant in geometry.surfaces[0].faces:
			record.surface_paint.append({"mesh":".","surface":0,"face":face,"geometry":geometry.surfaces[0].signature,"mapping":"planar","scale":[1.,1.],"offset":[0.,0.],"rotation":0.,"material":{"name":"paint","color":[.6,.5,.4,1.],"roughness":.8}})
		base.free()
	elif kind=="building":record.building={"id":"kit_building","part":"floor","floor":0,"floor_y":0.}
	else:record.fortification={"id":"kit_fortification","part":"wall"}
	var visual:MeshInstance3D=doc._mesh(record,true,null,context)
	check(not visual.has_meta("tile_error") and not visual.has_meta("paint_error"),kind+": real kit build/paint succeeds "+str(visual.get_meta("paint_error","")))
	var spec:Dictionary=Stream._spec(visual)
	check(not spec.has("collision_mesh"),kind+": ownership proof does not rely on a collision owner")
	check((spec.mesh is Cpu)==(kind!="paint"),kind+": actual spec takes the expected renderer/CPU derived path")
	visual.free()
	return spec

func source_refs(captured:Dictionary)->Array:
	return [captured.packed,captured.mesh,weakref(captured.scene.get_child(0).mesh.surface_get_material(0).albedo_texture)]

func owner_case(kind:String)->void:
	var model:=fixture("kit_derived_"+kind,true)
	var host:=Host.new();root.add_child(host)
	var service:Node=load(ServicePath).for_consumer(host);var pool:=ControlledPool.new();configure(service,pool)
	var captured:=await capture_scene(service,host,host,model.path);await quiet(service,pool)
	var refs:Array=source_refs(captured)
	var spec:=make_spec(model.path,captured.packed,kind)
	Drainer.dispose_scene(captured.scene);captured.scene=null
	await quiet(service,pool)
	check(not expired(refs[0]) and not expired(refs[1]),kind+": final derived spec retains the READY template and original mesh")
	check(not expired(refs[2]),kind+": final derived spec retains its native texture owner")
	check(not Assets._scenes.has(model.path),kind+": no global scene cache was populated")
	var ledger:RefCounted=service.ledger
	spec.clear();service.close();host.free()
	await settle(ledger,pool);await retired(PublishedGeometry.for_tree(self),refs)
	check(refs.all(func(reference):return expired(reference)),kind+": spec release retires packed/mesh/texture without a cache flush")

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	create_timer(80).timeout.connect(func():printerr("CONTEXT watchdog");quit(2))
	dependency_case();geometry_limits_case()
	# Exercise the existing authored-collision policy's render-only branch.
	var collision_policy=preload("res://scripts/world3d/model_collision_requirements.gd")
	var previous:bool=collision_policy.enabled;collision_policy.enabled=true
	for kind:String in ["paint","building","fortification"]:await owner_case(kind)
	collision_policy.enabled=previous
	print("CONTEXT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
