extends "res://tools/test_stream_index_retire.gd"
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func run()->void:
	var preparation:Script=load("res://scripts/world3d/final_index_preparation.gd")
	var directory:=Paths.cache_directory("final_index_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");write(path,"{\"nodes\":[]}".to_utf8_buffer())
	var records:Array=[]
	for i:int in 16:records.append({"uuid":"item%d"%i,"kind":"box","surface_id":"block","position":[i,0,0],"rotation":[0,0,0],"size":[i+1,1,1],"color":[i/20.,.3,.4]})
	var stored:=Store.write_records(records,path,Paths.external_root())
	check(stored.ok and stored.dependencies.size()==16,"prepare real independent immutable resource definitions outside the project")
	var source:RefCounted=Snapshot.read_file(path);var loader:=Loader.new();loader._source_snapshot=source
	var library:Array=[];var shared:=BoxMesh.new()
	for i:int in 256:
		var item:=spec("part%d"%i,Vector2i(i%32,0),Vector2i(i%32,0),{"kind":"asset"});item.mesh=shared;library.append(item)
	Trace.start();var worker:=Thread.new()
	check(worker.start(preparation.prepare.bind(library,stored.dependencies,path,Paths.external_root(),4))==OK,"existing index worker runs complete spatial and resource verification")
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();var trace:=Trace.stop()
	var ordinary:Dictionary=result.index.duplicate();ordinary.stream_collision_neighborhood=null
	check(result.dependencies_valid and same_contents(ordinary,Index.build(library.duplicate(true))),"worker result matches the complete reference index and original resource SHA checks")
	var nearby:RefCounted=result.index.stream_collision_neighborhood
	check(nearby!=null and nearby.members.size()==256 and nearby.matches(result.index.stream_collision_index,result.index.stream_collision_revision),"existing worker also prepares the complete fine collision index")
	check(is_same(result.index.stream_by_id.part0,library[0]),"worker preparation preserves original runtime source identity")
	check(trace.stats.any(func(row):return row.label=="game.final_reference_dependencies" and row.thread_id!=OS.get_main_thread_id()),"full resource hashing executes away from the scene thread")
	check(loader._final_index_integrity(result),"final main-thread map byte observation accepts an unchanged source")
	var leaf:=directory.path_join(stored.records[0].rmmo_ref.uri);var original:=FileAccess.get_file_as_bytes(leaf);var changed:=original.duplicate();changed[-1]=changed[-1]^1;write(leaf,changed)
	var corrupt:Dictionary=preparation.prepare(library,stored.dependencies,path,Paths.external_root(),4)
	check(not corrupt.dependencies_valid and not loader._final_index_integrity(corrupt),"same-size resource corruption rejects publication even after warming decode caches")
	write(leaf,original)
	var repaired:Dictionary=preparation.prepare(library,stored.dependencies,path,Paths.external_root(),4)
	check(repaired.dependencies_valid and loader._final_index_integrity(repaired),"repaired exact resource bytes can be verified again")
	write(path,"{\"nodes\":{}}".to_utf8_buffer())
	check(not loader._final_index_integrity(repaired),"map changed after worker completion still fails the final synchronous source observation")
	write(path,"{\"nodes\":[]}".to_utf8_buffer());DirAccess.remove_absolute(leaf)
	check(not preparation.prepare(library,stored.dependencies,path,Paths.external_root(),4).dependencies_valid,"missing immutable definition cannot be hidden by an earlier proof")
	loader.free();result.clear();corrupt.clear();repaired.clear();library.clear()
	print("FINAL_INDEX_PREPARATION checks=",checks," failures=",failures);quit(1 if failures else 0)
