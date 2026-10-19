extends "res://tools/test_chunk_reference_preparation.gd"
func run()->void:
	var helper:=Fixtures.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("trusted_chunk_snapshot_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(helper.folder)
	var records:Array=[]
	for i:int in 128:records.append(helper.box("box%d"%i,i*8.))
	var fixture:Dictionary=helper.fixture("map",records,{"author_notes":"x".repeat(4*1024*1024)})
	var index:=Index.build(fixture.path,helper.content_root,records)
	check(index.ok,"large mounted source snapshot builds")
	var request:=entries(index,[2,0,1]);var expected:Dictionary={};var reports:Array=[]
	for mounted:bool in [false,true,true,false]:
		Prepare.trusted_directory_snapshot_enabled=mounted
		var started:=Time.get_ticks_usec();var hashes:=0;var recomputed:=0;var terrain_scans:=0
		for i:int in 16:
			var result:=Prepare.prepare(index,request,fixture.path,helper.content_root,null,null,{},{},0,true)
			check(result.error.is_empty(),"trusted selected request completes")
			var value:Dictionary={"records":result.records,"positions":result.record_indices,"dependencies":result.dependencies,"arrays":result.surface_arrays,"contexts":result.terrain_contexts}
			if expected.is_empty():expected=value
			check(value==expected,"same selected record order, dependency closure and geometry")
			hashes+=int(result.read_profile.map_authentications);recomputed+=int(result.read_profile.directory_rows_recomputed);terrain_scans+=int(result.read_profile.terrain_context_source_rows)
		reports.append({"mounted":mounted,"us":Time.get_ticks_usec()-started,"map_authentications":hashes,"recomputed_rows":recomputed,"terrain_scanned_rows":terrain_scans})
	Prepare.trusted_directory_snapshot_enabled=true
	var original:=FileAccess.get_file_as_bytes(fixture.path);var mutation:=MutationToken.new();mutation.path=fixture.path;mutation.bytes=original+" ".to_utf8_buffer()
	var held:=Prepare.prepare(index,request,fixture.path,helper.content_root,mutation,null,{},{},0,true)
	check(held.error.is_empty() and held.records==expected.records,"a disk save cannot mix a new map revision into mounted chunk data")
	check(not Prepare.prepare(index,request,fixture.path,helper.content_root).error.is_empty(),"explicit diagnostic read still detects a changed map")
	for when:int in [1,3,7]:
		var token:=Token.new();token.after=when
		var result:=Prepare.prepare(index,request,fixture.path,helper.content_root,token,null,{},{},0,true)
		check(result.cancelled and result.records.is_empty(),"map reload/exit cancellation drops the mounted task at boundary %d"%when)
	check(not Prepare.prepare(index,entries(index,[0,0]),fixture.path,helper.content_root,null,null,{},{},0,true).error.is_empty(),"duplicate scheduling requests still fail")
	# A non-terrain request must not inspect unrelated rows at all.
	check(reports.all(func(row):return row.terrain_scanned_rows==0),"ordinary requests do no full-map terrain-neighbor scan")
	var terrain_records:Array=[]
	for i:int in 2:
		var tile:=helper.box("tile%d"%i,i*8.);tile.size=[8,1,8]
		var heights:Array=[]
		for z:int in 5:
			for x:int in 5:heights.append(.002*pow(i*8+x*2-4,2)+.01*z)
		var holes:Array=[];holes.resize(16);holes.fill(false)
		tile.terrain_mesh={"version":1,"columns":4,"rows":4,"floor":-1.,"heights":heights,"holes":holes};terrain_records.append(tile)
	var terrain:=helper.fixture("terrain",terrain_records);var terrain_index:=Index.build(terrain.path,helper.content_root,terrain_records)
	var strict:=Prepare.prepare(terrain_index,entries(terrain_index,[0]),terrain.path,helper.content_root)
	var mounted:=Prepare.prepare(terrain_index,entries(terrain_index,[0]),terrain.path,helper.content_root,null,null,{},{},0,true)
	var strict_context:Dictionary=strict.terrain_contexts.tile0.duplicate();var mounted_context:Dictionary=mounted.terrain_contexts.tile0.duplicate()
	strict_context.image=strict_context.image.get_data();mounted_context.image=mounted_context.image.get_data()
	check(strict.error.is_empty() and mounted.error.is_empty() and strict.surface_arrays==mounted.surface_arrays and strict_context==mounted_context,"requested terrain retains exact neighboring halo geometry and context pixels")
	check(mounted.surface_arrays.size()==1 and mounted.dependencies.size()==2 and mounted.read_profile.terrain_context_source_rows==2,"terrain-only path still reads its unrequested seam neighbor")
	for path:String in helper.created:
		if Paths.allowed(path,helper.content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(fixture.path+".resources");DirAccess.remove_absolute(terrain.path+".resources");DirAccess.remove_absolute(helper.folder);helper.free()
	print("TRUSTED_CHUNK_SNAPSHOT ",JSON.stringify({"trials":reports,"failures":failures}));quit(1 if failures else 0)
