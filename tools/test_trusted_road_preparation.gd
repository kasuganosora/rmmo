extends "res://tools/test_native_road_preparation.gd"
func run()->void:
	var cases:Array=[road()]
	var graded:=road();graded.road_mesh.grade=[.035,-.02];cases.append(graded)
	var followed:=road();followed.road_mesh.elevations=[[.1,.15,.21,.18]];cases.append(followed)
	for caps:Array in [[false,false],[true,false],[false,true],[true,true]]:
		var kerbed:=road();kerbed.road_mesh.kerbs=[part(caps[0],caps[1])];cases.append(kerbed)
	for record:Dictionary in cases:
		var original:=var_to_bytes(record)
		var strict:=Prepare.prepare(record);var trusted:=Prepare.prepare(record,null,true)
		check(strict.error.is_empty() and trusted.error.is_empty() and var_to_bytes(strict.arrays)==var_to_bytes(trusted.arrays),"trusted geometry exactly preserves every channel and surface")
		check(strict.estimated_bytes==trusted.estimated_bytes and strict.output_bytes==trusted.output_bytes and Prepare.estimate(record)==Prepare.estimate(record,true),"trusted preparation retains identical admission estimates")
		check(var_to_bytes(record)==original,"author record remains unchanged")
	var stress:=road();stress.road_mesh.kerbs=[]
	for i:int in 512:stress.road_mesh.kerbs.append(part(i%2==0,i%3==0))
	var reports:Array=[];var expected:=var_to_bytes(Road.arrays(stress))
	for trusted:bool in [false,true,true,false]:
		var started:=Time.get_ticks_usec();var geometry_us:=0
		for i:int in 8:
			var result:=Prepare.prepare(stress,null,trusted)
			geometry_us+=result.elapsed_us
			check(result.error.is_empty() and var_to_bytes(result.arrays)==expected,"stress emits identical kerb geometry")
		reports.append({"trusted":trusted,"elapsed_us":Time.get_ticks_usec()-started,"geometry_us":geometry_us,"jobs":8})
	for at:int in [1,2,3]:
		var token:=Token.new();token.after=at
		var result:=Prepare.prepare(stress,token,true)
		check(result.cancelled and result.arrays.is_empty(),"trusted cancellation boundary exposes no partial geometry")
	var ordinary:=road();ordinary.erase("road_mesh")
	check(not Prepare.estimate(ordinary,true).ok,"non-road cannot acquire a road budget")
	var invalid:=road();invalid.road_mesh.polygons[0].reverse()
	check(not Prepare.estimate(invalid).ok and not Prepare.prepare(invalid).error.is_empty(),"explicit diagnostic path still validates authored geometry")
	var helper:=Fixtures.new();helper.content_root=Paths.external_root();helper.folder=Paths.cache_directory("trusted_road_preparation_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(helper.folder)
	var source:=helper.fixture("road",[stress]);var index:=Index.build(source.path,helper.content_root,[stress])
	check(index.ok,"temporary authored road snapshot builds")
	var before:=FileAccess.get_file_as_bytes(source.path)
	var result:=Chunk.prepare(index,entry(index),source.path,helper.content_root,null,null,{},{},0,true)
	check(result.error.is_empty() and result.read_profile.road_instances==1 and var_to_bytes(result.surface_arrays[stress.uuid])==expected,"actual trusted chunk route keeps exact published road arrays")
	var mutator:=MutationToken.new();mutator.path=source.path;mutator.bytes=before+" ".to_utf8_buffer()
	result=Chunk.prepare(index,entry(index),source.path,helper.content_root,mutator,null,{},{},0,true)
	check(not result.error.is_empty() and result.surface_arrays.is_empty(),"mutable map replacement still rejects the obsolete transaction")
	helper.write_bytes(source.path,before)
	var smaller:=index.duplicate(true);smaller.rows[0].memory_bytes=1
	result=Chunk.prepare(smaller,entry(smaller),source.path,helper.content_root,null,null,{},{},0,true)
	check(result.error.contains("内存预算") and result.surface_arrays.is_empty(),"trusted route retains the actual road memory admission bound")
	for path:String in helper.created:
		if Paths.allowed(path,helper.content_root) and FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(helper.folder);helper.free()
	print("TRUSTED_ROAD_PREPARATION ",JSON.stringify({"passed":passed,"failures":failures,"trials":reports}));quit(1 if failures else 0)
