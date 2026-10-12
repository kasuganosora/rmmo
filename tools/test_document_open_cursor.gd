extends SceneTree
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failed:=0
var directory:String
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func write(name_:String,data:Variant)->String:
	var path:=directory.path_join(name_+".gltf")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close();return path
func fixture(count_:int)->Dictionary:
	var records:Array=[]
	for i in count_:records.append({"uuid":"obj_%d"%[i+1],"kind":"box","surface_id":"block","position":[i,1,0],"size":[1,1,1],"rotation":[0,0,0]})
	return {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"rmmo_world","extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":records}}]}
func cursor(path:String,data:Variant,mcp:bool=true)->RefCounted:
	var result:=Cursor.new();result.begin_document(path,{"data":data,"signature":FileAccess.get_sha256(path)},mcp);return result
func drain(value:RefCounted)->void:
	while not value.done:value.advance(1)
func run()->void:
	directory=Paths.cache_directory("open_cursor_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var data:=fixture(120);var path:=write("valid",data);var before:=JSON.stringify(data)
	var sliced:=cursor(path,data)
	var calls:=0
	while not sliced.done:sliced.advance(1);calls+=1
	var sync=Doc.open_file(path,{"data":data,"signature":FileAccess.get_sha256(path)})
	check(sliced.document!=null and sync!=null and sliced.document.records==sync.records and sliced.document.map_meta==sync.map_meta,"sliced and synchronous documents are equivalent")
	check(calls>120 and sliced.metrics.common_records==120 and sliced.metrics.document_records==120,"slices validate each authoritative record once")
	check(JSON.stringify(data)==before,"prepared input stays immutable")
	sliced.document.records[0].position[0]=999;sliced.document.map_meta.audit="private"
	check(data.nodes[0].extras.rmmo_records[0].position[0]==0 and not data.nodes[0].extras.has("audit"),"published records and metadata have no input aliases")
	var bad:=fixture(120);bad.nodes[0].extras.rmmo_records[119].uuid="obj_1"
	var invalid:=cursor(write("duplicate",bad),bad);drain(invalid)
	check(invalid.document==null and "UUID" in invalid.error,"duplicate UUID remains rejected across slices")
	bad=fixture(1);bad.nodes.append({"extras":{"rmmo_records":[{"kind":"asset","asset_path":"C:/outside.glb"}]}})
	invalid=cursor(write("other_node",bad),bad);drain(invalid)
	check(invalid.document==null,"invalid record in a later non-root node is never skipped")
	bad=fixture(1);bad.nodes.append({"extras":{"rmmo_records":bad.nodes[0].extras.rmmo_records.duplicate(true)}})
	invalid=cursor(write("repeated_records",bad),bad);drain(invalid)
	check(invalid.document!=null and invalid.metrics.common_records==2 and invalid.document.records.size()==1,"other node records get MCP checks without joining authoritative UUID scope")
	bad=fixture(1);bad.nodes[0].extras.rmmo_records[0].kind="asset";bad.nodes[0].extras.rmmo_records[0].asset_path="C:/outside.glb"
	var mode_path:=write("modes",bad)
	check(Doc.open_file(mode_path)!=null,"Doc-only keeps original acceptance without adding MCP asset-root rule")
	invalid=cursor(mode_path,bad);drain(invalid)
	check(invalid.document==null,"editor mode retains mandatory MCP asset-root rule")
	for value in [[],null,7]:
		invalid=cursor(write("invalid_type",value),value);drain(invalid);check(invalid.document==null,"invalid JSON root type rejects")
	bad=fixture(1);bad.buffers=[{"uri":"absent.bin","byteLength":10}]
	invalid=cursor(write("missing",bad),bad);drain(invalid)
	check(invalid.document==null,"native dependency existence is preserved")
	var bin_path:=directory.path_join("short.bin");FileAccess.open(bin_path,FileAccess.WRITE).store_8(0)
	bad.buffers[0].uri="short.bin";invalid=cursor(write("short",bad),bad);drain(invalid)
	check(invalid.document==null,"native buffer length check is preserved")
	bad=fixture(1)
	bad.nodes[0].extras.rmmo_records[0].building={"id":"absent","part":"wall","floor":0,"floor_y":0.,"role":"wall"}
	invalid=cursor(write("ownership",bad),bad);drain(invalid)
	check(invalid.document==null and "ownership" in invalid.error,"invalid ownership metadata rejects")
	var race:=cursor(path,data)
	while race._phase!="signature" and not race.done:race.advance(1)
	var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
	drain(race);check(race.document==null and "changed" in race.error,"late external map change fails before publication")
	path=write("valid",data);var callbacks:=[]
	var final:=Cursor.new()
	final.begin_document(path,{"data":data,"signature":FileAccess.get_sha256(path)},true,func(_phase,_done,_total):callbacks.append(true))
	while final._phase!="signature" and not final.done:final.advance(1)
	var callback_count:=callbacks.size();drain(final)
	check(final.document!=null and callbacks.size()==callback_count,"no callback occurs after the final signature check")
	var scene:=Node3D.new();scene.name="rmmo_world";scene.set_meta("extras",{"rmmo_format":"rmmo_gltf_map","rmmo_version":1})
	var block:=MeshInstance3D.new();block.name="obj_1";block.mesh=BoxMesh.new();block.set_meta("extras",{"uuid":"obj_1","kind":"box","surface_id":"block"});scene.add_child(block)
	var legacy:=directory.path_join("legacy.gltf");check(Io.save_scene(scene,legacy)==OK,"legacy fixture exported");scene.free()
	var legacy_doc=Doc.open_file(legacy)
	check(legacy_doc!=null and legacy_doc.records.size()==1,"legacy box-only document still opens")
	bad=fixture(1);bad.nodes[0].translation=[3,0,0];var transformed:=write("transformed",bad)
	var legacy_cursor:=cursor(transformed,bad);drain(legacy_cursor)
	check(Cursor.native_root(bad)<0 and legacy_cursor.metrics.units.has("legacy"),"transformed root retains the legacy importer path")
	bad=fixture(0);bad.nodes=[];bad.scenes[0].nodes=[]
	invalid=cursor(write("empty_root",bad),bad);drain(invalid)
	check(invalid.document==null,"empty unsupported root cannot silently become an empty editor document")
	print("DOCUMENT_CURSOR_FINISHED ",failed," ",sliced.metrics)
	Io._remove_tree(directory);quit(0 if failed==0 else 1)
