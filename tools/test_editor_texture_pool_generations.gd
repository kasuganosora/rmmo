extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prepare=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func texture(digest:String,representation:String)->Texture2D:
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	var result:=ImageTexture.create_from_image(image)
	result.set_meta("runtime_source_sha256",digest);result.set_meta("runtime_texture_representation",representation)
	return result
func material(path:String,value:Texture2D)->StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_texture=value
	result.set_meta("runtime_paint_definition",{"texture_path":path})
	return result
func run()->void:
	var a:=texture("original","source");var other:=texture("other","source")
	var target:=material("color",a);var unrelated:=material("other",other)
	var schema:={"test":true};var pool:={"target":target,"alias":target,"other":unrelated,"schema":schema};var sources:Dictionary={}
	var packet:={"owners":{"color":a},"images":{},"failed":[]}
	check(Prepare.reconcile_pool(packet,pool,sources)==2 and pool.size()==4,"initial generation checks unique materials and preserves matching aliases/schema")
	var inspected:=0
	for i in 1000:inspected+=Prepare.reconcile_pool(packet,pool,sources)
	check(inspected==0 and pool.size()==4,"1000 ordinary records cause no repeated material-pool scans")
	var new_owner:=texture("original","dds:new")
	packet.owners.color=new_owner
	check(Prepare.reconcile_pool(packet,pool,sources)==2 and not pool.has("target") and not pool.has("alias"),"same pixels with a new representation invalidate every old material alias")
	check(pool.other==unrelated and is_same(pool.schema,schema) and target.albedo_texture==a,"unrelated pool entries and already published old material remain unchanged")
	var updated:=material("color",new_owner);pool.target=updated
	check(Prepare.reconcile_pool(packet,pool,sources)==0 and pool.target==updated,"newly restored current material needs no whole-pool recheck")
	var prepared:=Image.create(2,2,false,Image.FORMAT_RGBA8);prepared.set_meta("runtime_source_sha256","changed");prepared.set_meta("runtime_texture_representation","source")
	packet={"images":{"color":prepared},"owners":{},"failed":[]}
	check(Prepare.reconcile_pool(packet,pool,sources)==2 and not pool.has("target"),"worker-prepared changed pixels also invalidate the old per-load material")
	pool.target=updated;packet={"images":{},"owners":{},"failed":["color"]}
	check(Prepare.reconcile_pool(packet,pool,sources)==2 and not pool.has("target") and not sources.has("color"),"failure removes dependent pool entries and permits a later source repair")
	check(pool.size()==2 and pool.other==unrelated,"failure preserves unrelated entries and schema")
	print("EDITOR_TEXTURE_LIVE_OWNERS ",JSON.stringify({"checks":checks,"failures":failures,"repeat_pool_scans":inspected}))
	quit(0 if failures.is_empty() else 1)
