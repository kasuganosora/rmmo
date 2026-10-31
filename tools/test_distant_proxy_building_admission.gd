extends "res://tools/test_distant_proxy_distance_admission.gd"
## Coarse bounds must avoid constructing unused render cohorts, while live
## changes and the order of actual far work remain observable immediately.
class ScriptedVisual extends MeshInstance3D:
	var properties:Dictionary={}
	var property_reads:=0
	func _get(key:StringName)->Variant:
		property_reads+=1
		return properties.get(key)

func run()->void:
	var baseline:bool="--baseline" in OS.get_cmdline_user_args()
	var mesh:=ArrayMesh.new();var arrays:=BoxMesh.new().get_mesh_arrays()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();mesh.surface_set_material(0,material)
	var scene:=world();var service:Node=scene.get_node("Proxy")
	for house in 31:
		for part in 7:
			var node:=source(scene,mesh,Vector3(140+house%8*6,0,house/8*8+part*.1),"house_"+str(house),part<4)
			node.layers=1 if part<3 else 2
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part==6 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var times:Array=[]
	for i in 64:
		var began:=Time.get_ticks_usec();service.tick(Vector3.ZERO);times.append(Time.get_ticks_usec()-began)
	var measured:Dictionary=service.profile.duplicate(true)
	check(service._rows.is_empty() and service._job.is_empty(),"mixed near render cohorts create no geometry tasks")
	check(not mesh.has_meta("ground_cpu_cache"),"coarse proof never captures geometry")
	if not baseline:
		check(measured.cohort_key_builds==0,"near buildings need no layer/shadow cohort keys")
		check(int(measured.get("building_near_skips",0))==31*64,"each current building has a fresh conservative proof")
	times.sort();result.building_admission={"profile":measured,"ticks":64,"sources":217,"tick_total_us":times.reduce(func(a,b):return a+b,0),"tick_median_us":times[32],"tick_max_us":times[-1]}
	await discard(scene)
	# A previous positive proof must never be reused after a source moves.
	scene=world();service=scene.get_node("Proxy")
	var a:=source(scene,mesh,Vector3(150,0,0),"moving",true)
	var b:=source(scene,mesh,Vector3(152,0,0),"moving")
	service.tick(Vector3.ZERO)
	check(service._job.is_empty(),"native near bounds reject before cohort construction")
	a.position.x=250;b.position.x=252
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"same-camera source motion immediately creates far work")
	await discard(scene)
	# An unsupported near part must not conceal the far eligible subset.
	scene=world();service=scene.get_node("Proxy")
	a=source(scene,mesh,Vector3(250,0,0),"mixed",true)
	b=source(scene,mesh,Vector3(252,0,0),"mixed")
	var near:=source(scene,mesh,Vector3(150,0,0),"mixed")
	near.material_override=material
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"near override does not conceal far native sources")
	if not service._job.is_empty():check(service._job.row.visuals.size()==2,"far preparation retains exactly the eligible sources")
	await discard(scene)
	# Interleaved source order determines the same first cohort to prepare.
	scene=world();service=scene.get_node("Proxy")
	a=source(scene,mesh,Vector3(250,0,0),"first",true)
	var other:=source(scene,mesh,Vector3(270,0,0),"second",true)
	b=source(scene,mesh,Vector3(252,0,0),"first",true)
	source(scene,mesh,Vector3(272,0,0),"second",true)
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty() and service._job.id==Proxy._cohort(a.get_meta("ground_batch_record"),a),"coarse buckets preserve first-source scheduling order")
	if not service._job.is_empty():
		check(service._job.row.visuals[0].get_ref()==a and service._job.row.visuals[1].get_ref()==b,"coarse buckets preserve source order inside the chosen cohort")
	check(is_instance_valid(other),"unselected far source remains independently owned")
	await discard(scene)
	# Property overrides remain meaningful for scripted native subclasses.
	scene=world();service=scene.get_node("Proxy")
	var scripted:=ScriptedVisual.new();scripted.mesh=mesh;scripted.position=Vector3(250,0,0)
	scripted.set_meta("ground_batch_record",{"building":{"id":"scripted"},"house_prefab":{}})
	scene.add_child(scripted);scene.get_meta("stream_meshes")[str(scripted.name)]=scripted
	b=source(scene,mesh,Vector3(252,0,0),"scripted")
	scripted.properties.material_override=material;service.tick(Vector3.ZERO)
	check(service._job.is_empty() and scripted.property_reads>0,"scripted material getter keeps its original admission semantics")
	scripted.properties={"layers":2};service.tick(Vector3.ZERO)
	check(service._job.is_empty(),"scripted layer getter still separates singleton cohorts")
	scripted.properties={"global_position":Vector3.ZERO};service.tick(Vector3.ZERO)
	check(service._job.is_empty(),"scripted position getter still applies the original early-distance rule")
	scripted.properties.clear();service.tick(Vector3.ZERO)
	check(not service._job.is_empty(),"restoring scripted properties admits current far sources")
	await discard(scene)
	# Non-string author IDs keep the original typed cohort representation.
	scene=world();service=scene.get_node("Proxy")
	a=source(scene,mesh,Vector3(250,0,0),"integer",true)
	b=source(scene,mesh,Vector3(252,0,0),"integer")
	a.get_meta("ground_batch_record").building.id=42;b.get_meta("ground_batch_record").building.id=42
	service.tick(Vector3.ZERO)
	check(not service._job.is_empty() and service._job.id==Proxy._cohort(a.get_meta("ground_batch_record"),a),"non-string IDs retain original cohort identity")
	await discard(scene)
	# Base suite additionally covers current material changes, hysteresis,
	# immediate hide withdrawal, height and offset bounds in the fallback stage.
	await super.run()
