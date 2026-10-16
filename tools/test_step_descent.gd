extends SceneTree
## Real capsule physics regression, including failure cases and authority gates.
const Authority=preload("res://scripts/world3d/world_authority.gd")
const Descent=preload("res://scripts/world3d/step_descent.gd")
class NoDescent extends RefCounted:
	func clear()->void:pass
	func supported(_body)->bool:return false
	func follow(_body,_supported,_jumped)->bool:return false
class Body extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface()->void:pass
var host:Node3D
var body:Body
var authority
var checks:Array=[]
var cases:Array=[]
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks.append({"name":label,"passed":ok});print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(size:Vector3,at:Vector3,concave:bool=false)->StaticBody3D:
	var solid:=StaticBody3D.new();var shape:Shape3D
	if concave:
		var mesh:=BoxMesh.new();mesh.size=size;shape=mesh.create_trimesh_shape()
	else:
		var s:=BoxShape3D.new();s.size=size;shape=s
	var collider:=CollisionShape3D.new();collider.shape=shape;solid.add_child(collider);host.add_child(solid);solid.position=at
	return solid
func setup()->void:
	host=Node3D.new();root.add_child(host)
	body=Body.new();var capsule:=CapsuleShape3D.new();capsule.height=1.9;capsule.radius=.3
	var shape:=CollisionShape3D.new();shape.name="CollisionShape3D";shape.shape=capsule;shape.position.y=.05;body.add_child(shape)
	host.add_child(body);body.floor_snap_length=.2
	authority=Authority.new();authority.mount(body,null,"test/descent")
	authority.traversal_guard=func(_bounds):return {"ok":true,"physics_published_frame":0}
func route(label:String,legacy:bool=false,concave:bool=false,speed:float=4.,climb:bool=false,edge_jump:bool=false,rate:int=60)->Dictionary:
	Engine.physics_ticks_per_second=rate
	setup()
	box(Vector3(4,.3,3),Vector3(0,3.6-.15,-1.5),concave)
	for i in 20:box(Vector3(4,.3,.3),Vector3(0,3.6-float(i+1)*.18-.15,(i+.5)*.3),concave)
	box(Vector3(4,.3,4),Vector3(0,-.15,8),concave)
	if legacy:authority._descent=NoDescent.new()
	body.position=Vector3(0,.901,6.6) if climb else Vector3(0,4.501,-.6)
	await physics_frame;await physics_frame
	for i in 6:
		await physics_frame;authority.move_intent(i,Vector3.ZERO,0)
	var air:=0;var max_air:=0;var corrections:=0;var jumped:=false;var jump_passed:=false;var start_y:=body.position.y;var last:=body.position;var samples:Array=[];var unsupported:=0;var max_unsupported:=0
	for i in ceili(8.2/speed*rate):
		await physics_frame
		var jump:bool=edge_jump and not jumped and not body.is_on_floor() and authority._descent.supported(body)
		var result:Dictionary=authority.move_intent(i+10,Vector3(0,0,-1 if climb else 1),speed,jump)
		if not result.ok:check(false,label+" accepted authority motion");break
		if jump:jumped=true;jump_passed=body.velocity.y>4. and body.position.y>last.y
		if not legacy and authority._descent._frame==Engine.get_physics_frames():corrections+=1
		air=0 if body.is_on_floor() else air+1;max_air=maxi(max_air,air);last=body.position
		var actual_contact:bool=body.is_on_floor() or (not legacy and authority._descent._frame==Engine.get_physics_frames())
		unsupported=0 if actual_contact else unsupported+1;max_unsupported=maxi(max_unsupported,unsupported)
		if label=="walk":samples.append({"tick":i,"air":air,"last_probe":authority._descent.last_probe_reason,"contact_frame":authority._descent._frame,"frame":Engine.get_physics_frames(),"feet":[body.position.x,body.position.y-.9,body.position.z]})
	var row:={"label":label,"legacy_descent_disabled":legacy,"concave":concave,"speed":speed,"rate":rate,"climb":climb,"max_airborne_ticks":max_air,"corrections":corrections,"end":[body.position.x,body.position.y,body.position.z],"jumped":jumped,"jump_passed":jump_passed,"height_change":body.position.y-start_y}
	row.samples=samples;row.max_unsupported_ticks=max_unsupported;cases.append(row);host.free();await physics_frame;return row
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var old:=await route("legacy_concave",true,true)
	check(old.max_airborne_ticks>20,"original rounded capsule descent failure reproduced without the new helper")
	for rate:int in [30,60,120]:
		var row:=await route("concave_run_%d"%rate,false,true,4.,false,false,rate)
		check(row.max_airborne_ticks<=2 and row.corrections>0,"continuous real concave stair descent at %d physics Hz"%rate)
		check(row.end[2]>7. and absf(row.end[1]-.9)<.01,"normal-speed descent reaches grounded landing at %d Hz"%rate)
	var walk:=await route("walk",false,false,1.6)
	check(walk.max_unsupported_ticks==0 and walk.end[2]>7.,"walking descent keeps real capsule contact through rounded edges")
	var climb:=await route("climb",false,true,4.,true)
	check(climb.end[2]<0 and absf(climb.end[1]-4.5)<.02,"existing step-up still reaches the upper landing")
	var jumping:=await route("edge_jump",false,true,4.,false,true)
	check(jumping.jumped and jumping.jump_passed and jumping.max_airborne_ticks>5,"jump from verified rounded tread contact detaches normally")
	Engine.physics_ticks_per_second=60
	setup();var floor_body:=box(Vector3(8,.2,8),Vector3(0,-.1,0))
	body.position=Vector3(0,1.,0);body.velocity=Vector3.DOWN
	await physics_frame;await physics_frame
	var descent=Descent.new();var before:=body.position
	check(not descent.follow(body,false,false) and body.position==before,"ordinary airborne fall is never attracted to nearby floor")
	check(not descent.follow(body,true,true) and body.position==before,"explicit jump forbids downward following")
	body.velocity=Vector3.UP;check(not descent.follow(body,true,false) and body.position==before,"upward motion remains free")
	body.velocity=Vector3.DOWN;body.floor_snap_length=0
	check(not descent.follow(body,true,false) and body.position==before,"disabled floor snap remains disabled")
	body.floor_snap_length=.2;body.position.y=1.31;before=body.position
	check(not descent.follow(body,true,false) and body.position==before,"drop beyond forty centimetres remains a fall")
	body.position.y=1.;body.collision_mask=2;before=body.position
	check(not descent.follow(body,true,false) and body.position==before,"collision mask cannot be bypassed by tread rays")
	body.collision_mask=1
	body.scale=Vector3(2,1,2);before=body.position
	check(not descent.follow(body,true,false) and body.position==before,"genuinely scaled capsule is not treated as unit geometry")
	body.scale=Vector3(.9999988675,1,.9999988675)
	check(descent.follow(body,true,false),"actual transfer-sized float32 scale drift does not disable tread following")
	check(absf(body.position.y-.9)<.01,"verified shallow downward sweep actually contacts the static floor")
	body.scale=Vector3.ONE
	body.position.x+=.1;await physics_frame
	check(not descent.supported(body),"external relocation invalidates previous tread contact")
	body.position=Vector3(0,3.,0);body.velocity=Vector3.ZERO;body.move_and_slide()
	body.position=Vector3(0,1.,0);body.velocity=Vector3.DOWN
	check(descent.follow(body,true,false),"removed-floor regression starts with a proven capsule contact")
	floor_body.free();await physics_frame
	check(not descent.supported(body),"removed floor invalidates support before another move or jump")
	var slope:=box(Vector3(5,.1,5),Vector3.ZERO);slope.rotation.z=deg_to_rad(55.)
	body.position=Vector3(0,1.1,0);body.velocity=Vector3.DOWN;await physics_frame;before=body.position
	check(not descent.follow(body,true,false) and body.position==before,"continuous steep slope is not reclassified as a tread")
	slope.free();box(Vector3(8,.2,8),Vector3(0,-.1,0));body.position=Vector3(0,1.,0);await physics_frame
	authority._descent=descent;authority.traversal_guard=func(_bounds):return {"ok":false,"reason":"geometry_pending"}
	before=body.position
	check(not authority.move_intent(100,Vector3.FORWARD,4).ok and body.position==before,"unready geometry rejects movement before all descent work")
	authority.release();check(descent._frame<0,"authority release clears contact across map changes")
	host.free()
	var out:="D:/code/rmmo_runtime/review_artifacts/axel_town_followup_20261017"
	DirAccess.make_dir_recursive_absolute(out)
	var f:=FileAccess.open(out+"/step_descent_tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"cases":cases,"authority_sha256":FileAccess.get_sha256("res://scripts/world3d/world_authority.gd"),"helper_sha256":FileAccess.get_sha256("res://scripts/world3d/step_descent.gd")},"  "));f.close()
	print("STEP_DESCENT_TESTS checks=",checks.size()," failures=",failures);quit(0 if failures==0 else 1)
