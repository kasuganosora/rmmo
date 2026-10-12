extends SceneTree
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Cache=preload("res://scripts/world3d/navigation_cache.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	create_timer(45).timeout.connect(func():quit(2))
	var nav:=Navigation.new();root.add_child(nav)
	nav.runtime_geometry_key="surface_cache_test_%d"%Time.get_ticks_usec()
	var floor_:=BoxMesh.new();floor_.size=Vector3(20,.2,20)
	nav.build([{"mesh":floor_,"transform":Transform3D(Basis.IDENTITY,Vector3(0,-.1,0)),"extras":{}}])
	while not nav.fully_ready:await process_frame
	while nav._surface_index==null:await process_frame
	nav.near_surface(Vector3(0,.1,0),.35,.65)
	check(nav.take_surface_profile().queries.is_empty(),"surface detail diagnostics are disabled by default")
	nav._surface_map=RID()
	nav.set_meta("profile_surface_details",true)
	check(nav.near_surface(Vector3(0,.1,0),.35,.65),"initial surface query succeeds")
	check(nav.surface_index_hits>0 and nav.surface_query_count==0,"published triangle index certifies interior support without a global query")
	var count:=nav.surface_query_count
	check(nav.near_surface(Vector3(.1,.1,.1),.35,.65) and nav.surface_query_count==count,"nearby support uses a proven point without another global query")
	count=nav.surface_query_count
	check(nav.near_surface(Vector3(.3,.6,0),.35,.65) and nav.surface_query_count>count,"tolerance-box corners still use exact nearest-point query")
	check(not nav.near_surface(Vector3(.1,3,.1),.35,.65) and nav.surface_query_count>count,"cached support cannot validate another floor")
	check(not nav.near_surface(Vector3(11,.1,0),.35,.65),"cached support cannot cross unsupported map edge")
	check(not nav.near_surface(Vector3.INF),"non-finite coordinates stay rejected")
	var details:Dictionary=nav.take_surface_profile()
	check(details.dropped==0 and details.queries.size()==6,"surface diagnostics retain every query, including rejected support")
	check(details.queries.map(func(row):return row.route)==["triangle_index","point_cache","nearest","nearest","nearest","rejected"],"surface diagnostics distinguish index, point cache, nearest and guard paths")
	check(details.queries.all(func(row):return row.begin_us<=row.iteration_us and row.iteration_us<=row.index_us and row.index_us<=row.end_us),"surface diagnostic intervals are ordered")
	check(nav.take_surface_profile().queries.is_empty() and details.queries.size()==6,"draining diagnostics does not mutate previously captured samples")
	for i in 65:nav.near_surface(Vector3.INF)
	var bounded:Dictionary=nav.take_surface_profile()
	check(bounded.queries.size()==64 and bounded.dropped==1 and nav.take_surface_profile().dropped==0,"surface diagnostics are bounded and reset dropped counts")
	nav.remove_meta("profile_surface_details")
	# Cache writer finishes asynchronously and restores the exact published mesh.
	while nav._cache_writer!=null:await process_frame
	var cached:=NavigationMesh.new()
	check(Cache.restore(nav._cache_key,cached) and cached.get_vertices()==nav.mesh.get_vertices() and cached.get_polygon_count()==nav.mesh.get_polygon_count(),"asynchronous cache write restores exact navigation geometry")
	DirAccess.remove_absolute(Cache.path(nav._cache_key));nav._cache_key=""
	var replacement:NavigationMesh=nav.mesh.duplicate();var vertices:=replacement.get_vertices()
	for i in vertices.size():vertices[i]+=Vector3(100,0,0)
	replacement.set_vertices(vertices)
	nav.near_surface(Vector3(0,.1,0),.35,.65)
	nav._full_mesh=replacement;nav.fully_ready=false;nav._full_baked()
	while not nav.fully_ready:await process_frame
	check(not nav.near_surface(Vector3(0,.1,0),.35,.65),"new map iteration invalidates old support point")
	check(nav.near_surface(Vector3(100,.1,0),.35,.65),"async region and map publication exposes replacement geometry")
	nav.free();print("NAVIGATION_SURFACE_CACHE failures=",failures);quit(1 if failures else 0)
