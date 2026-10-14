extends SceneTree
const DEST="D:/code/rmmo/review_artifacts/required_street_recheck_20261013"
const Authority=preload('res://scripts/world3d/world_authority.gd')
const Paint=preload('res://scripts/world3d/surface_materials.gd')
var results:Array=[]
var manifest:Dictionary
var native_mode:=false
const Compile=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
class Pawn extends CharacterBody3D:
	var surface_id:='stone'
	func _sense_surface()->void:pass
func _initialize()->void:run.call_deferred()
func ground(size:Vector3,pos:Vector3,parent:Node)->void:
	var b:=StaticBody3D.new();var sh:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;sh.shape=box;b.add_child(sh);parent.add_child(b);b.position=pos
func run_case(id:String,start:Vector3,goal:Vector3,kind:String)->void:
	var holder:=Node3D.new();root.add_child(holder)
	var row:Dictionary=manifest.assets.filter(func(r):return r.id==id)[0]
	assert(FileAccess.get_sha256(row.path)==row.sha256)
	var model:Node
	var native_sha:=""
	if native_mode:
		var imports:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DEST+'/editor_http.json'))
		assert(imports.get('passed',false) and imports.get('completed',false))
		var product_row:Dictionary=imports.items.filter(func(r):return r.id==id)[0]
		assert(product_row.input_sha==row.sha256 and product_row.passed)
		assert(FileAccess.get_sha256(product_row.output_path)==product_row.output_sha)
		var product:Dictionary=Compile.read(product_row.output_path)
		assert(product.get('hit',false),'current production native identity must validate')
		var native_path:=Compile.directory().path_join(str(product_row.native_manifest.payload_sha)+'.scn')
		native_sha=FileAccess.get_sha256(native_path)
		assert(native_sha==str(product_row.native_manifest.payload_sha))
		model=Compile.instantiate(product.packed)
	else:
		var gltf:=GLTFDocument.new();var state:=GLTFState.new();assert(gltf.append_from_file(row.path,state)==OK)
		model=Io.generate_scene(gltf,state)
	assert(model!=null);holder.add_child(model)
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
		results.append({'id':id,'sha256':row.sha256,'native_sha':native_sha,'to':[target.x,target.y,target.z],'reached':reached,'feet':[body.position.x,body.position.y-.9,body.position.z],'minimum_feet_height':min_feet,'trace':trace})
	authority.release();holder.queue_free();await process_frame;await physics_frame
func run()->void:
	if '--syntax-only' in OS.get_cmdline_user_args():print('STREET_TRAVERSAL syntax only');quit();return
	Engine.max_fps=120
	DirAccess.make_dir_recursive_absolute(DEST)
	var args:=OS.get_cmdline_user_args();var path:String=args[0] if args.size()>0 else "D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json"
	native_mode='--native' in args
	if native_mode:
		var imports:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DEST+'/editor_http.json'))
		var recorded_root:String=str(imports.get('content_root',''))
		var paths=preload('res://scripts/world3d/map_paths.gd')
		assert(imports.get('passed',false) and imports.get('completed',false))
		assert(not recorded_root.is_empty() and paths.allowed(recorded_root) and recorded_root.get_file().begins_with('required_street_native_scope_'),'native replay requires the verified isolated content root')
		assert(DirAccess.dir_exists_absolute(recorded_root))
		root.get_node('AssetManager').content_root_override=recorded_root
		assert(paths.external_root()==recorded_root and Compile.directory()==imports.native_cache_directory)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(path))
	await run_case('s12_projecting_arch',Vector3(0,.03,3),Vector3(0,0,-1),'arch')
	await run_case('s12_landing_steps_3',Vector3(.18,.03,.7),Vector3(.18,.48,-1.20),'stairs')
	await run_case('s12_landing_steps_4',Vector3(.18,.03,.7),Vector3(.18,.64,-1.60),'stairs')
	await run_case('s12_water_steps_four',Vector3(-.85,.63,0),Vector3(4.65,.60,0),'stones')
	var ok:=results.all(func(r):return r.reached)
	var output:='/traversal_native.json' if native_mode else '/traversal.json'
	FileAccess.open(DEST+output,FileAccess.WRITE).store_string(JSON.stringify({'passed':ok,'cases':results,'mode':'validated production native' if native_mode else 'current exported GLB','capsule_height':1.8,'capsule_radius':.30,'controller':'production world_authority.gd','scope':'Physical step/capsule traversal in isolated loaded collision fixture; creek bed and banks are test supports, no formal water or navigation map.'},'  '))
	print('REQUIRED_STREET_TRAVERSAL ',ok);quit(0 if ok else 1)

