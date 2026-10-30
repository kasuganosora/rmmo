extends SceneTree
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
var failures:Array=[]
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func texture(sha:String)->ImageTexture:
	var image:=Image.create(1,1,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var value:=ImageTexture.create_from_image(image);value.set_meta("runtime_source_sha256",sha)
	return value
func run()->void:
	var original_hot:Dictionary=Paint._textures;var original_weak:Dictionary=Paint._texture_refs
	var original_images:Dictionary=Paint.prepared_images;var original_uploads:Dictionary=Paint.prepared_textures
	Paint._textures={};Paint._texture_refs={};Paint.prepared_images={};Paint.prepared_textures={}
	var a:=texture(SHA_A);var b:=texture(SHA_B)
	var packet:={"resident_textures":{},"sources":{}};var state:={};var record:={}
	for i in 96:
		var path:="D:/texture_publication_fixture/texture_%d.png"%i
		var key:=Paint.texture_key(path,i%2==0,i%2==0)
		packet.resident_textures[key]={"texture":a,"source_sha":SHA_A};packet.sources[path]=SHA_A
		Paint._textures[key]=a;Paint._texture_refs[key]=weakref(a)
	var scope:=Prefab.begin_texture_publication(record,null,packet,state);Prefab.end_texture_publication(scope)
	Prefab.texture_check_profile_enabled=true;Prefab.texture_owner_reads=0;Prefab.texture_catalog_reads=0
	var began:=Time.get_ticks_usec();var successful:=true
	for i in 500:
		scope=Prefab.begin_texture_publication(record,null,packet,state)
		successful=successful and scope.ok;Prefab.end_texture_publication(scope)
	var elapsed:=Time.get_ticks_usec()-began
	var owner_reads:int=Prefab.texture_owner_reads;var catalog_reads:int=Prefab.texture_catalog_reads
	Prefab.texture_check_profile_enabled=false
	check(successful,"repeated publications reuse the same valid resident owners")
	check(owner_reads==500*96 and catalog_reads==0,"one publication reads each identical ticket/catalogue owner only once")
	check(Paint.prepared_images.is_empty() and Paint.prepared_textures.is_empty(),"synchronous scopes restore the previous image and upload context")
	var key:String=packet.resident_textures.keys()[0];var path:=Paint.texture_source_path(key)
	packet.sources[path]=SHA_B
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(not scope.ok,"in-place source proof changes reject the very next publication")
	packet.sources[path]=SHA_A;Paint._textures[key]=b
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(not scope.ok,"a newer hot catalogue owner rejects an old resident ticket immediately")
	Paint._textures[key]=a;a.set_meta("runtime_source_sha256",SHA_B)
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(not scope.ok,"mutating the same resource metadata cannot reuse a previous check")
	a.set_meta("runtime_source_sha256",SHA_A);var alias:=texture(SHA_A);Paint._textures[key]=alias
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(scope.ok,"a distinct current owner with the same source remains compatible");Prefab.end_texture_publication(scope)
	Paint._textures.clear();Paint._texture_refs[key]=weakref(b)
	check(Prefab.tickets_valid(packet.resident_textures,packet.sources),"weak-only replacement retains the established ticket admission contract")
	var before:int=state.initializations
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(scope.ok and state.initializations==before+1,"weak-only replacement re-enters the full publication protocol");Prefab.end_texture_publication(scope)
	Paint._textures.clear();Paint._texture_refs.clear();before=state.initializations
	scope=Prefab.begin_texture_publication(record,null,packet,state)
	check(scope.ok and state.initializations==before+1,"evicted catalogues reinstall retained tickets instead of losing their resources");Prefab.end_texture_publication(scope)
	check(packet.resident_textures.size()==96 and packet.sources.size()==96,"checking never changes borrowed packet membership")
	Paint._textures=original_hot;Paint._texture_refs=original_weak;Paint.prepared_images=original_images;Paint.prepared_textures=original_uploads
	var report:={"checks":checks,"failures":failures,"publication_calls":500,"resident_keys":96,"elapsed_us":elapsed,"owner_reads":owner_reads,"catalog_reads":catalog_reads}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
