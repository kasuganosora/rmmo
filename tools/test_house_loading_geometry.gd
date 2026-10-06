extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var failed:=0
func check(ok: bool,label_: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label_)
	if not ok: failed+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for size_ in [Vector3(2,3,.3),Vector3(.024,1.234,9.87)]:
		var box:=BoxMesh.new(); box.size=size_
		var expected:=box.surface_get_arrays(0); var actual:=Cpu.primitive_arrays(box,0); var same:=true
		for channel in Mesh.ARRAY_MAX:
			if expected[channel]==null: same=same and actual[channel]==null; continue
			if expected[channel].size()!=actual[channel].size(): same=false; continue
			for i in expected[channel].size():
				if typeof(expected[channel][i]) in [TYPE_VECTOR3,TYPE_VECTOR2]: same=same and expected[channel][i].is_equal_approx(actual[channel][i])
				else: same=same and is_equal_approx(expected[channel][i],actual[channel][i])
		check(same,"canonical box preserves engine topology, UV, normals and tangents: "+str(size_))
	var folder:=preload("res://scripts/world3d/map_paths.gd").cache_directory("loading_geometry_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("normal.png"); var image:=Image.create(4,4,false,Image.FORMAT_RGB8); image.fill(Color(.5,.5,1)); image.save_png(path)
	var doc=preload("res://scripts/world3d/world_document.gd").new(); doc.add_box("block",Vector3.ZERO,Vector3(2,3,.3))
	var node: MeshInstance3D=doc._mesh(doc.records[0]); var geo:=Paint.geometry(node)
	var entries: Array=[]
	for face in geo.surfaces[0].faces:
		entries.append({"mesh":".","surface":0,"face":face,"geometry":geo.surfaces[0].signature,"mapping":"meters","material":{"name":"normal test","color":[1,1,1,1],"roughness":.8,"normal_path":path},"scale":[2,3],"offset":[.2,.1],"rotation":30})
	node.free(); doc.records[0].surface_paint=entries
	node=doc._mesh(doc.records[0]); check(not node.has_meta("paint_error"),"normal mapped paint succeeds")
	check(node.mesh.has_meta("ground_cpu_cache"),"paint retains CPU geometry for later consumers")
	var cpu: Mesh=Cpu.capture(node.mesh)
	var equal_tangents:=true
	for slot in cpu.get_surface_count():
		var arrays: Array=cpu.surface_get_arrays(slot)
		var temporary:=ArrayMesh.new(); var source: Array=arrays.duplicate(); source[Mesh.ARRAY_TANGENT]=null; temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source)
		var st:=SurfaceTool.new(); st.create_from(temporary,0); st.generate_tangents(); var expected: Array=st.commit_to_arrays()
		var actual: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]; var wanted: PackedFloat32Array=expected[Mesh.ARRAY_TANGENT]
		equal_tangents=equal_tangents and actual.size()==wanted.size()
		for i in mini(actual.size(),wanted.size()): equal_tangents=equal_tangents and is_equal_approx(actual[i],wanted[i])
	check(equal_tangents,"CPU tangent path matches previous GPU roundtrip including handedness")
	var spec:=Stream._spec(node); check(spec.get("collision_mesh") is BoxMesh,"painted box keeps exact primitive")
	var host:=Node3D.new(); root.add_child(host); var body:=Stream._make_body(host,spec)
	check(body.get_child(0).shape is BoxShape3D and body.get_child(0).shape.size.is_equal_approx(Vector3(2,3,.3)),"painted wall collision dimensions preserved")
	doc.load_paint_validation={}; doc.load_texture_checks={}; doc.load_box_meshes={}
	var first: MeshInstance3D=doc._mesh(doc.records[0])
	var moved: Dictionary=doc.records[0].duplicate(true); moved.uuid="other"; moved.position=[12,0,3]; moved.rotation=[0,45,0]
	var second: MeshInstance3D=doc._mesh(moved)
	check(first.mesh==second.mesh and first.position!=second.position and doc.load_box_hits==1,"immutable load shares geometry without sharing instance transform or identity")
	moved.surface_paint[0].rotation=70
	var changed: MeshInstance3D=doc._mesh(moved)
	check(changed.mesh!=first.mesh,"different face UV parameters cannot reuse another box")
	var primitive:Dictionary=doc.records[0].duplicate(true)
	primitive.erase("surface_paint");primitive.building_shape="cylinder";primitive.size=[.08,.18,.08]
	var pin_a:MeshInstance3D=doc._mesh(primitive);var pin_b:MeshInstance3D=doc._mesh(primitive)
	check(pin_a.mesh==pin_b.mesh,"repeated hinge pins reuse their cylinder mesh")
	var pin_cpu:Mesh=Cpu.capture(pin_a.mesh);pin_a.free();pin_b.free();doc.load_box_meshes.clear()
	var restored:Mesh=pin_cpu.restore()
	check(restored==pin_cpu.restore(),"CPU cache restores one shared GPU mesh for repeated instances")
	var blueprint=preload("res://scripts/world3d/building_blueprint.gd")
	var recipe:Dictionary=blueprint.generate(blueprint.medieval_presets()[0].parameters)
	for shape in ["wall_grid","draped_cloth","joined_box","roof_prism","candle_sconce"]:
		var choices:Array=recipe.records.filter(func(r):return r.get("building_shape")==shape)
		check(not choices.is_empty(),"custom geometry fixture available: "+shape)
		if choices.is_empty():continue
		var record:Dictionary=choices[0].duplicate(true)
		var a:MeshInstance3D=doc._mesh(record)
		record.uuid+="_moved";record.position[0]+=27;record.rotation[1]+=90
		var b:MeshInstance3D=doc._mesh(record)
		check(a.mesh==b.mesh and a.transform!=b.transform,"custom geometry reused independently: "+shape)
		check(b.get_meta("paint_source_materials").size()==b.get_meta("paint_source").get_surface_count(),"all original material slots preserved: "+shape)
		if shape=="joined_box":check(Stream._spec(b).collision_mesh is BoxMesh,"trimmed skins retain full solid collision on cache hit")
		record.size[1]*=1.1
		var c:MeshInstance3D=doc._mesh(record)
		check(c.mesh!=a.mesh,"custom size participates in cache identity: "+shape)
		a.free();b.free();c.free()
	first.free(); second.free(); changed.free()
	doc.load_paint_validation=null; doc.load_texture_checks=null; doc.load_box_meshes=null
	DirAccess.remove_absolute(path)
	var invalid: MeshInstance3D=doc._mesh(doc.records[0]); check(invalid.has_meta("paint_error"),"new editor operation rejects removed texture")
	invalid.free(); node.free(); host.free()
	print("HOUSE_LOADING_GEOMETRY_FINISHED failures=",failed); quit(1 if failed else 0)
