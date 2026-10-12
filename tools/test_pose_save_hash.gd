extends SceneTree
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func run()->void:
	var directory:=Paths.cache_directory("pose_hash_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var expected:Dictionary={};var buffers:Array=[]
	for index in 8:
		var bytes:=PackedByteArray();bytes.resize(2*1024*1024);bytes.fill(index+17)
		var path:=directory.path_join("part_%d.bin"%index)
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		expected[path]=FileAccess.get_sha256(path)
		buffers.append({"uri":path.get_file(),"byteLength":bytes.size()})
	var actual:=Pose.hash_files(expected.keys(),Paths.external_root())
	check(actual.ok and Pose.same(actual.files,expected),"bounded parallel SHA equals independent serial SHA for 16 MiB")
	var model:=directory.path_join("依赖.gltf")
	var file:=FileAccess.open(model,FileAccess.WRITE)
	file.store_string(JSON.stringify({"asset":{"version":"2.0"},"buffers":buffers}));file.close()
	expected[model]=FileAccess.get_sha256(model)
	actual=Pose.source_files([{"asset_path":model}],Paths.external_root(),Io)
	check(actual.ok and Pose.same(actual.files,expected),"source closure preserves all external buffer hashes")
	actual=Pose.source_files([{"asset_path":model,"thumbnail_path":directory.path_join("not_generated.png")}],Paths.external_root(),Io)
	check(actual.ok and Pose.same(actual.files,expected),"derived missing thumbnail is not an export dependency")
	check(not Pose.source_files([{"asset_path":model,"material_path":directory.path_join("missing.png")}],Paths.external_root(),Io).ok,"real missing material dependency still fails")
	var missing:=expected.keys();missing.append(directory.path_join("absent.bin"))
	check(not Pose.hash_files(missing,Paths.external_root()).ok,"missing dependency fails without a partial accepted result")
	check(not Pose.hash_files(["C:/Windows/win.ini"],Paths.external_root()).ok,"hash worker enforces resource root")
	var sample:Dictionary={"label":"石桥与木屋é","extras":{Pose.MANIFEST:{"version":1,"sources":{}}},"nodes":[]}
	var encoded:=Pose.serialize_bytes(sample);var text:=encoded.get_string_from_utf8();var parsed:Dictionary=JSON.parse_string(text)
	var manifest:Dictionary=parsed.extras[Pose.MANIFEST];var digest:String=manifest.rmmo_saved_content_sha256
	check(text.replace(digest,"0".repeat(64)).sha256_text()==digest,"serialized UTF-8 checksum agrees with independent textual definition")
	check(Pose.valid_content_bytes(encoded,text,manifest),"byte checksum accepts multibyte labels")
	var late:Dictionary={"label":"石桥与木屋é","nodes":[]};late.extras=parsed.extras
	late.extras[Pose.MANIFEST].rmmo_saved_content_sha256="0".repeat(64)
	text=JSON.stringify(late,"",false,true);digest=text.sha256_text();text=text.replace("0".repeat(64),digest)
	parsed=JSON.parse_string(text)
	check(Pose.valid_content_bytes(text.to_utf8_buffer(),text,parsed.extras[Pose.MANIFEST]),"legacy late checksum handles preceding multibyte text")
	check(not Pose.valid_content_bytes((text+" ").to_utf8_buffer(),text+" ",parsed.extras[Pose.MANIFEST]),"byte checksum rejects changed content")
	Io._remove_tree(directory)
	print("POSE_HASH_TEST_FINISHED ",failed);quit(0 if failed==0 else 1)
