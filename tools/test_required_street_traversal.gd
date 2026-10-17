extends SceneTree
const DEST="D:/code/rmmo_runtime/review_artifacts/required_street_assets_20261013"
const Authority=preload('res://scripts/world3d/world_authority.gd')
const Paint=preload('res://scripts/world3d/surface_materials.gd')
var results:Array=[]
class Pawn extends CharacterBody3D:
	var surface_id:='stone'
	func _sense_surface()->void:pass
func _initialize()->void:run.call_deferred()
func ground(size:Vector3,pos:Vector3,parent:Node)->void:
	var b:=StaticBody3D.new();var sh:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;sh.shape=box;b.add_child(sh);parent.add_child(b);b.position=pos
func run_case(id:String,start:Vector3,goal:Vector3,kind:String)->void:
	var holder:=Node3D.new();root.add_child(holder)
	var packed:PackedScene=load(DEST+'/'+id+'/asset.scn');var model:Node=packed.instantiate();holder.add_child(model)
	for mesh:MeshInstance3D in Paint.meshes(model):
		if mesh.get_meta('extras',{}).get('rmmo_collision','none')=='none':continue
		var b:=StaticBody3D.new();var sh:=CollisionShape3D.new();sh.shape=mesh.mesh.create_trimesh_shape();b.add_child(sh);mesh.add_child(b)
	if kind=='stones':
		ground(Vector3(9,.2,4),Vector3(1.8,-.10,0),holder)
		ground(Vector3(1.1,.6,2),Vector3(-1.02,.30,0),holder)
		ground(Vector3(1.1,.6,2),Vector3(4.86,.30,0),holder)
	else:ground(Vector3(12,.2,12),Vector3(0,-.1,0),holder)
	var body:=Pawn.new();var sh:=CollisionShape3D.new();sh.name='CollisionShape3D';var cap:=CapsuleShape3D.new();cap.radius=.30;cap.height=1.8;sh.shape=cap;body.add_child(sh);holder.add_child(body);body.position=start+Vector3.UP*.9;body.floor_snap_length=.2;body.collision_layer=2;body.collision_mask=1
	for k in 5:await physics_frame
	var authority:=Authority.new();authority.mount(body,null,'isolated_asset_review')
	var published:=Engine.get_physics_frames()-2
	authority.traversal_guard=func(_bounds:AABB):return {'ok':true,'physics_published_frame':published}
	var min_feet:=100.;var seq:=0;var trace:Array=[]
	for target in [goal,start]:
		var reached:=false
		for k in 540:
			await physics_frame;seq+=1
			var delta:Vector3=target-body.position;delta.y=0
			if delta.length()<.05:reached=true;break
			var result:Dictionary=authority.move_intent(seq,delta.normalized(),minf(1.6,delta.length()*60))
			min_feet=minf(min_feet,body.position.y-.9)
			if k%30==0:trace.append([body.position.x,body.position.y-.9,body.position.z,result.get('ok',false)])
		results.append({'id':id,'to':[target.x,target.y,target.z],'reached':reached,'feet':[body.position.x,body.position.y-.9,body.position.z],'minimum_feet_height':min_feet,'trace':trace})
	authority.release();holder.queue_free();await process_frame;await physics_frame
func run()->void:
	Engine.max_fps=120
	await run_case('s12_projecting_arch',Vector3(0,.03,3),Vector3(0,0,-1),'arch')
	await run_case('s12_landing_steps_3',Vector3(.18,.03,.7),Vector3(.18,.48,-1.20),'stairs')
	await run_case('s12_landing_steps_4',Vector3(.18,.03,.7),Vector3(.18,.64,-1.60),'stairs')
	await run_case('s12_water_steps_four',Vector3(-.85,.63,0),Vector3(4.65,.60,0),'stones')
	var ok:=results.all(func(r):return r.reached)
	FileAccess.open(DEST+'/traversal.json',FileAccess.WRITE).store_string(JSON.stringify({'passed':ok,'cases':results,'capsule_height':1.8,'capsule_radius':.30,'controller':'production world_authority.gd','scope':'Physical step/capsule traversal in isolated loaded collision fixture; creek bed and banks are test supports, no formal water or navigation map.'},'  '))
	print('REQUIRED_STREET_TRAVERSAL ',ok);quit(0 if ok else 1)
