extends SceneTree
const Fixture=preload("res://tools/test_native_road_preparation.gd")
const Road=preload("res://scripts/world3d/road_surface.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prep=preload("res://scripts/world3d/surface_paint_preparation.gd")
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func entries(arrays:Array)->Array:
	var topology:=Paint.geometry_arrays(arrays,false,true)
	var result:Array=[]
	for face:Variant in topology.surfaces[0].faces:
		result.append({"mesh":".","surface":0,"face":face,"geometry":topology.surfaces[0].signature,"mapping":"uv","scale":[.5,.75],"offset":[0.,0.],"rotation":0.,"material":{"name":"paint","color":[.6,.5,.4,1.],"roughness":.8}})
	return result
func run()->void:
	Prep.enabled=true
	var strict:bool="--expect-reuse" in OS.get_cmdline_user_args()
	var fixture:=Fixture.new();var record:=fixture.road();record.road_mesh.grade=[.025,-.015]
	record.road_mesh.polygons=[[[ -.48,-.4],[-.2,-.4],[-.2,.4],[-.48,.4]],[[-.1,-.4],[.1,-.4],[.1,.4],[-.1,.4]]]
	record.road_mesh.kerbs=[]
	for i:int in 2048:record.road_mesh.kerbs.append(fixture.part(i%2==0,i%3==0))
	var source:Array=Road.arrays(record)
	var budget:Dictionary=fixture.Prepare.estimate(record)
	var original:=var_to_bytes(source);var expected:=Bounds.bounds(source)
	record.surface_paint=entries(source)
	for normal:bool in [false,true]:
		for partial:bool in [false,true]:
			var current:Dictionary=record.duplicate(true)
			if partial:current.surface_paint.resize(1)
			if normal:current.surface_paint[0].material.normal_path="preparation_only_no_texture_read.png"
			var reference:=Prep.prepare(source,current.surface_paint)
			var worker:=Thread.new();worker.start(Prep.for_road.bind(current,source,budget))
			var packet:Dictionary=worker.wait_to_finish()
			check(packet.get("ok",false) and reference.get("ok",false),"road private preparation succeeds")
			check(var_to_bytes(packet.fragments)==var_to_bytes(reference.fragments),"reuse preserves every fragment channel, surface order and paint entry")
			check(packet.bounds.is_equal_approx(expected),"paint keeps the complete unindexed source extent")
			if strict:check(packet.has("source_bounds") and packet.source_bounds==expected,"road producer grants the exact original bound")
	# Generic indexed meshes can contain unused positions. Their source extent
	# must never be borrowed as proof of the painted fragment extent.
	var indexed:Array=source.duplicate(true)
	var vertices:PackedVector3Array=indexed[0][Mesh.ARRAY_VERTEX]
	var indices:=PackedInt32Array();indices.resize(vertices.size())
	for i:int in indices.size():indices[i]=i
	vertices.append(Vector3(10000,10000,10000));indexed[0][Mesh.ARRAY_VERTEX]=vertices;indexed[0][Mesh.ARRAY_INDEX]=indices
	check(Prep.for_road(record,indexed,budget).is_empty(),"indexed input keeps generic preparation; unused vertices cannot share painted bounds")
	var indexed_entries:=entries(indexed)
	for entry:Dictionary in indexed_entries:entry.mapping="planar"
	var indexed_packet:=Prep.prepare(indexed,indexed_entries)
	check(indexed_packet.get("ok",false) and not indexed_packet.bounds.is_equal_approx(Bounds.bounds(indexed)),"generic indexed output still excludes its unused distant position")
	check(var_to_bytes(source)==original,"parallel preparation leaves borrowed geometry immutable")
	if strict:
		var cached:=Prep.for_road(record,source,budget,null,expected)
		check(cached.source_bounds_scans==0 and cached.bounds==expected and cached.source_bounds==expected,"native cached bound removes both scans")
		var trailing:Array=source.duplicate(true)
		trailing[0][Mesh.ARRAY_VERTEX].append(Vector3(10000,10000,10000))
		check(Prep.for_road(record,trailing,budget).is_empty(),"incomplete triangle streams cannot claim complete-source bounds")
	var times:Array=[];var shared:=false
	for sample:int in 5:
		var began:=Time.get_ticks_usec()
		for i:int in 16:
			var packet:=Prep.for_road(record,source,budget)
			shared=packet.has("source_bounds")
			# This is the original source-bounds stage in Chunk.prepare.
			var box:AABB=packet.source_bounds if shared else Bounds.bounds(source)
			check(box==expected,"source bounds consumed without changing result")
		times.append(Time.get_ticks_usec()-began)
	if strict:check(shared,"chunk may reuse only a road producer's complete-source proof")
	var paired:Array=[]
	if strict:
		# Same process, same input, actual legacy two-scan kernel; exclude source
		# generation/authoring from both arms. Keep slow samples and their order.
		for use_shared:bool in [false,true,true,false]:
			var began:=Time.get_ticks_usec()
			for i:int in 16:
				var packet:=Prep.for_road(record,source,budget) if use_shared else Prep.prepare(source,record.surface_paint)
				var box:AABB=packet.source_bounds if use_shared else Bounds.bounds(source)
				check(packet.ok and box==expected,"paired scan kernel preserves source extent")
			paired.append({"shared":use_shared,"us":Time.get_ticks_usec()-began})
	print("ROAD_PAINT_BOUNDS ",JSON.stringify({"checks":checks,"failures":failures,"rounds_us":times,"paired_abba":paired,"calls_per_round":16,"shared_source_bounds":shared,"vertices":fixture.vertices(source),"source_sha256":FileAccess.get_sha256("res://scripts/world3d/surface_paint_preparation.gd")}))
	fixture.free();quit(1 if failures else 0)
