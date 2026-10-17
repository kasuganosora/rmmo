extends "res://tools/test_stream_index_retire.gd"
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Chunk=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Neighbors=preload("res://scripts/world3d/terrain_neighbors.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/runtime_completion_20261017/"
func reject_owned(data:Dictionary,library:Array,ids:Array,label:String)->void:
	var before:=data.duplicate(true);var original:=library.duplicate(true)
	check(not Index.retire_owned(data,library,ids).ok and data==before and library==original,label+" atomic refusal")
func run()->void:
	var r:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(16)
	var ground:=spec("terrain",Vector2i.ZERO,Vector2i(2,2),r)
	var building:={"id":"house","part":"wall","role":"wall","floor":0,"floor_y":0.}
	var wall:=spec("wall",Vector2i.ONE,Vector2i.ONE,{"kind":"box","building":building})
	var roof:=spec("roof",Vector2i.ONE,Vector2i.ONE,{"kind":"box","building":building})
	var keep:=spec("keep",Vector2i(20,0),Vector2i(20,0),{"kind":"asset"})
	var library:Array=[ground,wall,roof,keep];var data:=Index.build(library)
	reject_owned(data,library,["wall"],"partial building")
	reject_owned(data,library,["terrain"],"surviving building terrain dependency")
	reject_owned(data,library,["wall","roof","missing"],"late unknown identity")
	reject_owned(data,library,["wall","roof","wall"],"duplicate identity")
	var result:=Index.retire_owned(data,library,["wall","roof"])
	check(result.ok and library==[ground,keep],"whole native building retires while preserving independent survivors")
	check(ground.render_dependents.is_empty() and result.data.stream_building_groups.is_empty(),"removed ownership cannot pin terrain through stale derived dependencies")
	check(is_same(result.data.stream_by_id.keep,keep),"surviving spec identities remain stable")
	data=result.data;result=Index.retire_owned(data,library,["terrain"])
	check(result.ok and library==[keep] and result.data.stream_landscape.is_empty(),"last terrain owner and full spatial bookkeeping retire together")
	var rebuilt:=Index.append(result.data,[ground,wall,roof]);library.append_array([ground,wall,roof])
	check(rebuilt.ok and same_contents(result.data,Index.build(library.duplicate(true))),"exact whole building and support can be republished under original UUIDs")
	var protected:=spec("event",Vector2i.ZERO,Vector2i.ZERO,{"event_template":{"template":"transfer"}});library=[protected];data=Index.build(library)
	reject_owned(data,library,["event"],"live gameplay owner")
	var directory:=Paths.cache_directory("native_context_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var doc:=Doc.new();var records:Array=[]
	for i in 2:
		var tile:Dictionary=preload("res://tools/test_terrain_incremental.gd").fixture(16);tile.uuid="tile_%d"%i;tile.position=[i*64.,0.,0.]
		for z in 17:
			for x in 17:tile.terrain_mesh.heights[z*17+x]=sin((x+i*16)*.13)+cos(z*.17)
		records.append(tile)
	doc.records=records;var path:=directory.path_join("map.gltf")
	check(doc.save(path)==OK,"save two continuous isolated terrain records")
	var built:=Directory.build(path,Paths.external_root(),records);var current:=Directory.read_for_loading(path,Paths.external_root())
	check(built.ok and current.ok,"build verified complete native ownership directory")
	var row:Dictionary=current.index.rows[1];var compact:Dictionary=current.index.extras.rmmo_records[1]
	var request:={"record_index":1,"compact_record":compact,"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}
	var prepared:=Chunk.prepare(current.index,[request],path,Paths.external_root(),null,current.proof)
	check(prepared.error.is_empty() and prepared.records.size()==1 and prepared.terrain_contexts.size()==1,"retired terrain reconstruction hydrates the render record plus private seam closure")
	if prepared.error.is_empty():
		var full:=Neighbors.new();full.update(records)
		check(prepared.surface_arrays.tile_1==Terrain.arrays(records[1],full.data.tile_1),"restored CPU vertex, index, UV and tangent arrays equal full original terrain context")
		check(prepared.terrain_contexts.tile_1.image.get_data()==full.data.tile_1.image.get_data() and prepared.terrain_contexts.tile_1.normals==full.data.tile_1.normals,"restored height/material halo and seam normals match complete map")
		check(prepared.dependencies.size()==2 and prepared.terrain_contexts.tile_1.signature.is_empty(),"neighbor SHA is verified without retaining neighbor decoded geometry in the result")
	DirAccess.make_dir_recursive_absolute(OUT)
	FileAccess.open(OUT+"native_contract.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"path":path,"sha256":FileAccess.get_sha256(path)},"  "))
	print("NATIVE_RETIREMENT_CONTRACT checks=",checks," failures=",failures);quit(1 if failures else 0)
