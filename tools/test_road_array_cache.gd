extends "res://tools/test_native_road_preparation.gd"
const Cache=preload("res://scripts/world3d/road_array_cache.gd")
func run()->void:
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.discard_map_textures=true;controls.enable_white_materials()
	var root_path:=Paths.cache_directory("road_array_test").path_join(str(OS.get_process_id()))
	var cases:Array=[road()]
	var graded:=road();graded.road_mesh.grade=[.035,-.02];cases.append(graded)
	var followed:=road();followed.road_mesh.elevations=[[.1,.15,.21,.18]];followed.terrain_grade=[.01,-.01];cases.append(followed)
	for caps:Array in [[false,false],[true,false],[false,true],[true,true]]:
		var kerbed:=road();kerbed.road_mesh.kerbs=[part(caps[0],caps[1])];cases.append(kerbed)
	for record:Dictionary in cases:
		var expected:=var_to_bytes(Road.arrays(record));var before:=var_to_bytes(record)
		check(Cache.build(record,root_path).ok,"offline road product builds")
		var hit:=Cache.read(record,root_path,Prepare.estimate(record,true).output_bytes)
		check(not hit.is_empty() and var_to_bytes(hit.arrays)==expected,"every vertex, normal, UV, tangent and surface exactly matches the original generator")
		check(hit.get("bounds")==preload("res://scripts/world3d/procedural_surface_bounds.gd").bounds(Road.arrays(record)),"persisted bounds exactly match the unchanged generated channels")
		check(var_to_bytes(record)==before,"source shape and editable metadata remain unchanged")
		var moved:=record.duplicate(true);moved.uuid="other";moved.position=[999,1,-999];moved.rotation=[0,80,0];moved.color=[.3,.4,.5,1]
		check(Cache.identity(moved)==Cache.identity(record),"placement and material changes reuse local geometry")
		var changed:=record.duplicate(true);changed.road_mesh.uv_origin[0]+=1
		check(Cache.read(changed,root_path,Prepare.estimate(changed,true).output_bytes).is_empty(),"changed geometry input cannot reuse the prior product")
	var stress:=road();stress.road_mesh.kerbs=[]
	for i:int in 512:stress.road_mesh.kerbs.append(part(i%2==0,i%3==0))
	check(Cache.build(stress,root_path).ok,"stress road product builds")
	var budget:=Prepare.estimate(stress,true);var reports:Array=[];var expected:=var_to_bytes(Road.arrays(stress))
	for cached:bool in [false,true]:
		var began:=Time.get_ticks_usec();var result:Array=[]
		for i:int in 12:
			result=Cache.read(stress,root_path,budget.output_bytes).arrays if cached else Road.arrays(stress)
		reports.append({"cached":cached,"calls":12,"elapsed_us":Time.get_ticks_usec()-began})
		check(var_to_bytes(result)==expected,"stress output preserves exact original channels")
	var prepared:=Prepare.prepare(stress,null,true,root_path)
	check(prepared.error.is_empty() and prepared.cache_hit and var_to_bytes(prepared.arrays)==expected,"production preparation consumes the exact offline product")
	check(prepared.bounds==preload("res://scripts/world3d/procedural_surface_bounds.gd").bounds(prepared.arrays),"production passes cached bounds without rescanning")
	for cached:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec();var measured:=AABB()
		for i:int in 48:measured=prepared.bounds if cached else preload("res://scripts/world3d/procedural_surface_bounds.gd").bounds(prepared.arrays)
		reports.append({"bounds_cached":cached,"calls":48,"elapsed_us":Time.get_ticks_usec()-began})
		check(measured==prepared.bounds,"fixed 48 bound queries are bit-exact")
	Cache.prepared_bounds_enabled=false
	check(not Prepare.prepare(stress,null,true,root_path).has("bounds"),"diagnostic control requests the original vertex scan")
	Cache.prepared_bounds_enabled=true
	var strict:=Prepare.prepare(stress,null,false,root_path)
	check(strict.error.is_empty() and not strict.cache_hit and var_to_bytes(strict.arrays)==expected,"diagnostic preparation still independently generates geometry")
	for at:int in [1,2,3]:
		var token:=Token.new();token.after=at
		var cancelled:=Prepare.prepare(stress,token,true,root_path)
		check(cancelled.cancelled and cancelled.arrays.is_empty(),"cached preparation cancellation exposes no partial output")
	var workers:Array=[]
	for i:int in 2:
		var worker:=Thread.new();worker.start(Prepare.prepare.bind(stress,null,true,root_path));workers.append(worker)
	for worker:Thread in workers:
		var value:Dictionary=worker.wait_to_finish()
		check(value.error.is_empty() and value.cache_hit and var_to_bytes(value.arrays)==expected,"concurrent cached jobs retain independent exact arrays")
	var digest:="1".repeat(64)
	check(Cache.build(stress,root_path,digest).ok,"mounted identity product builds separately from standalone geometry hash")
	var referenced:=Prepare.prepare(stress,null,true,root_path,budget,digest)
	check(referenced.cache_hit and var_to_bytes(referenced.arrays)==expected,"mounted content identity reads the exact same geometry without a repeated geometry hash")
	var resized:=stress.duplicate(true);resized.size[0]*=2
	check(Cache.identity(stress,digest)!=Cache.identity(resized,digest),"instance size remains part of the geometry key")
	check(Cache.identity(stress,digest)!=Cache.identity(stress,"2".repeat(64)),"a new authored definition cannot reuse the old road projection")
	var began:=Time.get_ticks_usec()
	for i:int in 12:Cache.read(stress,root_path,budget.output_bytes,digest)
	reports.append({"cached":true,"mounted_identity":true,"calls":12,"elapsed_us":Time.get_ticks_usec()-began})
	var path:=Cache.product_path(Cache.identity(stress),root_path);var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("partial");file.close()
	check(Cache.read(stress,root_path,budget.output_bytes).is_empty(),"incomplete offline product falls back without exposing partial arrays")
	check(not Prepare.prepare(stress,null,true,root_path).cache_hit,"missing product returns to the original production generator")
	print("ROAD_ARRAY_CACHE ",JSON.stringify({"failures":failures,"trials":reports}));quit(1 if failures else 0)
