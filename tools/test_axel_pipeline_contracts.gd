extends "res://tools/test_map_dependency_index.gd"
const Components=preload("res://scripts/world3d/model_components.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const MapData=preload("res://scripts/world3d/world_map_data.gd")
func road(id:String,x:float)->Dictionary:
	return {"uuid":id,"kind":"box","position":[x,0,0],"rotation":[0,25,0],"size":[16,.18,16],"surface_id":"block","collision":"block","road_mesh":{"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"uv_origin":[0,0,0],"grade":[.02,-.01]},"terrain_follow":{"version":1,"terrain_ids":["terrain"],"polygons":[[[-.5,-.5],[.5,-.5],[.5,.5],[-.5,.5]]],"offset":.03,"max_grade":.15}}
func run()->void:
	content_root=Paths.external_root();folder=Paths.cache_directory("axel_pipeline_contract_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var records:Array=[road("near",0),road("far",600)]
	var malformed:=road("malformed",900);malformed.terrain_follow.max_grade=-1.;records.append(malformed)
	var unknown:=road("unknown",1200);unknown.custom_behavior={"moving":true};records.append(unknown)
	var original:=var_to_bytes(records)
	var f:=fixture("map",records)
	var built:=Index.build(f.path,content_root,records)
	check(built.ok,"terrain-follow source index builds")
	if built.ok:
		check(built.rows[0].classification=="spatial" and built.rows[1].reason=="native_road","frozen terrain-follow roads use measured road geometry")
		check(built.rows[2].classification=="global" and built.rows[3].classification=="global","malformed follow and unknown behavior retain conservative fallback")
		var selected:=Index.select(built,[AABB(Vector3(-12,-5,-12),Vector3(24,10,24))])
		check(selected.ok and selected.record_indices==[0,2,3] and selected.deferred_indices==[1],"far valid road is deferred while unsafe records stay eager")
		var restored:=Cursor.hydrate_references(selected.extras,f.path,content_root)
		check(restored.ok and restored.extras.rmmo_records[0].terrain_follow==records[0].terrain_follow,"selected hydration retains editable terrain binding")
		check(Index.validate_selected(built,[records[0],records[2],records[3]],content_root).ok,"selected road retains ordinary semantic and source validation")
	check(original==var_to_bytes(records),"author road poses and bindings unchanged")
	var model:=Node3D.new();model.name="LegacyGuild";model.set_meta("extras",{"delivery_stage":"textured_repair_v2"});root.add_child(model)
	var groups:Array=["00_Foundation","20_Floor_L1","33_Ceilings_L1","50_Roof","32_Furniture_L1","43_Entrance_Doors"]
	for i in groups.size():
		var mesh:=MeshInstance3D.new();mesh.name="piece_%d"%i;mesh.mesh=BoxMesh.new();mesh.mesh.size=Vector3(4,.2,4);mesh.position.y=i*2
		mesh.set_meta("extras",{"uuid":str(mesh.name),"semantic_group":groups[i]});model.add_child(mesh)
	var record:Dictionary={"kind":"asset","uuid":"guild","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	Components.apply(model,record)
	var library:Array=[]
	for mesh:MeshInstance3D in model.get_children():
		check(mesh.get_meta("extras").building==mesh.get_meta("ground_batch_record").building,"one adapted membership for batching, cutaway and map "+str(mesh.name))
		library.append(Stream._spec(mesh))
	var map:=Node3D.new();map.set_meta("stream_library",library)
	var data:=MapData.new();data.build(map)
	check(data.shapes.size()==1,"legacy radar projects occupied ground floor instead of every imported part")
	check(model.get_child_count()==groups.size(),"cartography does not remove model components")
	model.free();map.free()
	print("AXEL_PIPELINE_CONTRACTS ",JSON.stringify({"passed":passed,"failures":failures}))
	quit(0 if failures==0 else 1)
