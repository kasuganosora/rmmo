extends SceneTree
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
class DecodeSpy:
	extends RefCounted
	static var calls:=0
	static func decode_dependency_uri(uri:String)->String:
		calls+=1
		return preload("res://scripts/world3d/gltf_map_io.gd").decode_dependency_uri(uri)
var failed:=0
var directory:String
var parent:String
var map_path:String
var original_model:Dictionary
var records:Array
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func write_json(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data));file.close()
func restore_model()->void:write_json(parent,original_model)
func fixed_mtime()->bool:
	var output:Array=[]
	return OS.execute("python",["-c","import os,sys; os.utime(sys.argv[1], (1700000000,1700000000))",parent],output,true)==0
func seed_map()->Dictionary:
	restore_model()
	var sources:=Pose.source_files(records,Paths.external_root(),Io)
	var node:Dictionary={"name":"piece"};Pose._set_pose(node,Pose.pose(records[0]))
	var data:Dictionary={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"world","children":[1],"extras":Pose.extras(records.duplicate(true),{})},node]}
	Pose.install_manifest(data,map_path,sources,Paths.external_root(),Io)
	check(data.get("extras",{}).has(Pose.MANIFEST),"fresh export installs verified manifest")
	var file:=FileAccess.open(map_path,FileAccess.WRITE);file.store_buffer(Pose.serialize_bytes(data));file.close()
	return sources
func run()->void:
	directory=Paths.cache_directory("pose_source_recheck_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	parent=directory.path_join("parent.gltf");map_path=directory.path_join("map.gltf")
	var buffers:Array=[]
	for index in 4:
		var bytes:=PackedByteArray();bytes.resize(2*1024*1024);bytes.fill(index+1)
		var path:=directory.path_join("part%d.bin"%index)
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		buffers.append({"uri":path.get_file(),"byteLength":bytes.size()})
	original_model={"asset":{"version":"2.0","generator":"test_a"},"buffers":buffers}
	var extra:=FileAccess.open(directory.path_join("extra.bin"),FileAccess.WRITE);extra.store_8(7);extra.close()
	restore_model()
	records=[{"uuid":"piece","kind":"asset","asset_path":parent,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}]
	DecodeSpy.calls=0
	var sources:=Pose.source_files(records,Paths.external_root(),DecodeSpy)
	check(sources.ok and sources.files.size()==5 and DecodeSpy.calls==4,"initial discovery parses all four external buffer URIs")
	DecodeSpy.calls=0
	check(Pose.verify_source_files(sources,Paths.external_root()) and DecodeSpy.calls==0,"final recheck retains complete SHA closure without parsing dependency URIs")
	var previous:=Pose.source_files(records,Paths.external_root(),Io)
	check(previous.ok and Pose.same(previous.files,sources.files),"new closure recheck agrees with old rediscovery result")
	var invalid:=sources.duplicate(true);invalid.generator="different_generator"
	check(not Pose.verify_source_files(invalid,Paths.external_root()),"different generator is rejected")
	invalid=sources.duplicate(true);invalid.ok=false
	check(not Pose.verify_source_files(invalid,Paths.external_root()),"failed initial discovery cannot be trusted")
	invalid=sources.duplicate(true);invalid.files[directory.path_join("absent.bin")]="0".repeat(64)
	check(not Pose.verify_source_files(invalid,Paths.external_root()),"missing closure path fails")
	invalid=sources.duplicate(true);invalid.files["C:/Windows/win.ini"]="0".repeat(64)
	check(not Pose.verify_source_files(invalid,Paths.external_root()),"outside-root closure path fails")
	check(fixed_mtime(),"fixture sets known timestamp using Python os.utime")
	var timestamp:=FileAccess.get_modified_time(parent)
	var length:=FileAccess.get_file_as_bytes(parent).size()
	var modified:=original_model.duplicate(true);modified.asset.generator="test_b";write_json(parent,modified)
	check(fixed_mtime() and FileAccess.get_modified_time(parent)==timestamp and FileAccess.get_file_as_bytes(parent).size()==length,"changed parent really retains original mtime and byte length")
	check(not Pose.verify_source_files(sources,Paths.external_root()),"same-mtime same-length parent change is rejected by SHA")
	restore_model()
	var first_buffer:String=directory.path_join(buffers[0].uri)
	var original_bytes:=FileAccess.get_file_as_bytes(first_buffer)
	var changed_bytes:=original_bytes.duplicate();changed_bytes[0]^=1
	var binary:=FileAccess.open(first_buffer,FileAccess.WRITE);binary.store_buffer(changed_bytes);binary.close()
	check(not Pose.verify_source_files(sources,Paths.external_root()),"changed existing dependency is rejected")
	DirAccess.remove_absolute(first_buffer)
	check(not Pose.verify_source_files(sources,Paths.external_root()),"removed existing dependency is rejected")
	binary=FileAccess.open(first_buffer,FileAccess.WRITE);binary.store_buffer(original_bytes);binary.close()
	var edits:Array=[]
	modified=original_model.duplicate(true);modified.buffers.append({"uri":"extra.bin","byteLength":1});edits.append(["added dependency URI",modified])
	modified=original_model.duplicate(true);modified.buffers.pop_back();edits.append(["removed dependency URI",modified])
	for uri in ["missing.bin","../escape.bin","C:/Windows/win.ini"]:
		modified=original_model.duplicate(true);modified.buffers[0].uri=uri;edits.append(["redirected URI "+uri,modified])
	for entry:Array in edits:
		seed_map()
		var original_sha:=FileAccess.get_sha256(map_path)
		var changed_model:Dictionary=entry[1]
		Io.save_fault=func(stage):
			if stage=="before_publish":write_json(parent,changed_model)
			return false
		var moved:=records.duplicate(true);moved[0].position[0]=1
		var result:=Pose.attempt(map_path,original_sha,moved,{},Paths.external_root(),Io)
		Io.save_fault=Callable()
		check(result.get("handled",false) and result.get("error")==ERR_BUSY and FileAccess.get_sha256(map_path)==original_sha,"late "+entry[0]+" rejects publication and preserves map")
		if entry[0]=="added dependency URI":
			var expanded:=Pose.source_files(records,Paths.external_root(),Io)
			check(expanded.ok and expanded.files.has(directory.path_join("extra.bin")) and expanded.files.size()==6,"added dependency really expands the closure with a new valid file")
		# First discovery still validates changed dependency paths independently.
		if "redirected" in entry[0]:check(not Pose.source_files(records,Paths.external_root(),Io).ok,"initial discovery rejects "+entry[0])
	seed_map()
	var moved:=records.duplicate(true);moved[0].position[0]=2
	var accepted:=Pose.attempt(map_path,FileAccess.get_sha256(map_path),moved,{},Paths.external_root(),Io)
	check(accepted.get("error")==OK and accepted.get("mode")=="pose_reuse" and accepted.get("updated_nodes")==1,"unchanged dependency closure still publishes moved pose")
	var reopened:=Pose._json(map_path)
	check(Pose.same(reopened.nodes[0].extras.rmmo_records,moved) and Pose.valid_content(FileAccess.get_file_as_string(map_path),reopened.extras[Pose.MANIFEST]),"published authoring pose and content checksum agree")
	# Synthetic, bounded CPU fixture: compare identical hash work with/without
	# rescanning 4372 records. This is not an actual-town performance claim.
	var many:Array=[];var values:Array=[]
	for index in 128:values.append(float(index))
	for index in 4372:many.append({"asset_path":parent,"geometry":{"samples":values,"label":"fixture_%d"%index}})
	var baseline:=Pose.source_files(many,Paths.external_root(),Io)
	for round_ in 2:
		var start:=Time.get_ticks_usec()
		var rediscovered:=Pose.source_files(many,Paths.external_root(),Io)
		var old_ms:float=(Time.get_ticks_usec()-start)/1000.0;start=Time.get_ticks_usec()
		var checked:=Pose.verify_source_files(baseline,Paths.external_root())
		var new_ms:float=(Time.get_ticks_usec()-start)/1000.0
		check(checked and rediscovered.ok and Pose.same(rediscovered.files,baseline.files),"benchmark old/new verification hashes agree %d"%round_)
		print("SOURCE_RECHECK_BENCH ",JSON.stringify({"round":round_,"records":many.size(),"files":baseline.files.size(),"old_ms":old_ms,"new_ms":new_ms}))
	Io._remove_tree(directory)
	print("POSE_SOURCE_RECHECK_FAILED=",failed);quit(0 if failed==0 else 1)
