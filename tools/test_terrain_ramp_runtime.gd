extends "res://tools/test_physical_traversal.gd"
const Doc=preload("res://scripts/world3d/world_document.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Ramp=preload("res://scripts/world_editor/terrain_ramp_tools.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/terrain_ramp_20261017"
var walks:Array=[]
func walk(authority:RefCounted,doc,first:Vector3,last:Vector3,label:String)->void:
	var initial:=Ramp.height_at(doc,[first.x,first.z]);body.position=Vector3(first.x,initial.height+.91,first.z);body.velocity=Vector3.ZERO
	for i in 12:await move(authority,Vector3.ZERO)
	var ticks:=0;var rejected:=0;var airborne:=0;var max_floor_error:=0.
	while Vector2(body.position.x-last.x,body.position.z-last.z).length()>.12 and ticks<600:
		var wish:=last-body.position;wish.y=0.;var result:=await move(authority,wish.normalized());ticks+=1
		if not result.ok:rejected+=1
		if not body.is_on_floor():airborne+=1
		var ground:=Ramp.height_at(doc,[body.position.x,body.position.z])
		if not ground.ok:rejected+=1;break
		max_floor_error=maxf(max_floor_error,absf(body.position.y-.9-ground.height))
	var distance:=Vector2(body.position.x-last.x,body.position.z-last.z).length()
	var passed_:bool=distance<=.12 and rejected==0 and airborne==0 and max_floor_error<.06
	check(passed_,label+" reaches destination on continuous physical ground, with no unsupported/rejected ticks")
	walks.append({"case":label,"passed":passed_,"ticks":ticks,"distance":distance,"rejected":rejected,"airborne":airborne,"max_floor_error":max_floor_error})
func run()->void:
	create_timer(180).timeout.connect(func():print("TERRAIN_RAMP_RUNTIME_TIMEOUT");quit(2));Engine.max_fps=60
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/http.json"))
	check(report.failures==0 and FileAccess.get_sha256(report.map)==report.map_sha256,"reopened native map matches HTTP evidence SHA")
	if failures:quit(1);return
	var doc=Doc.open_file(report.map);host=Node3D.new();root.add_child(host)
	var scene:Node3D=doc.build(true);host.add_child(scene);var collisions:=0
	for mesh:MeshInstance3D in Doc.SurfaceMaterials.meshes(scene):
		var spec:={"uuid":str(mesh.get_path()),"mesh":mesh.get_meta("collision_solid",mesh.get_meta("paint_source",mesh.mesh)),"transform":mesh.global_transform,"extras":mesh.get_meta("extras",{})}
		if Stream._make_body(host,spec)!=null:collisions+=1
	check(collisions>=2,"saved native terrain and road use production collision builder")
	body=Body.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;collider.shape=capsule;body.add_child(collider);host.add_child(body);body.floor_snap_length=.2
	var nav:=NavStub.new();host.add_child(nav);var authority:=Authority.new();authority.mount(body,nav,report.map)
	var published:=Engine.get_physics_frames();authority.traversal_guard=func(_bounds:AABB)->Dictionary:return {"ok":true,"physics_published_frame":published}
	await physics_frame;await physics_frame
	var a:Array=report.preview.start;var b:Array=report.preview.end
	var start:=Vector3(a[0],a[1],a[2]);var end:=Vector3(b[0],b[1],b[2]);var direction:=(end-start)*Vector3(1,0,1);direction=direction.normalized()
	# Offset from the road: the capsule traverses the native ramp itself.
	var side:=Vector3(-direction.z,0,direction.x)*1.15
	await walk(authority,doc,start+side,end+side,"uphill across mixed-resolution seam")
	await walk(authority,doc,end+side,start+side,"downhill across mixed-resolution seam")
	FileAccess.open(OUT+"/runtime.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"passed":passed,"map":report.map,"map_sha256":report.map_sha256,"collisions":collisions,"walks":walks,"scope":"production native mesh/collider and WorldAuthority movement; no avatar renderer, no formal map edits"},"\t"))
	authority.release();host.free();print("TERRAIN_RAMP_RUNTIME failures=",failures);quit(1 if failures else 0)
