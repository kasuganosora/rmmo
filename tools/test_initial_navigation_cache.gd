extends SceneTree
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Cache=preload("res://scripts/world3d/navigation_cache.gd")
var failures:=0
var specs:Array=[]
var identity:=""
var paths:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func load_nav(origin:Vector3,height:float=1.8)->Node:
	var nav:=Navigation.new();nav.runtime_geometry_key=identity;nav.agent_height=height;root.add_child(nav)
	nav.build(specs,origin)
	while not nav.ready_for_queries:await process_frame
	paths.append(Cache.path(nav._initial_cache_key));paths.append(Cache.path(nav._cache_key))
	return nav
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	identity="initial_navigation_test_%d"%Time.get_ticks_usec()
	var ground:=BoxMesh.new();ground.size=Vector3(240,.2,32)
	var wall:=BoxMesh.new();wall.size=Vector3(3,5,10)
	specs=[{"mesh":ground,"transform":Transform3D(Basis.IDENTITY,Vector3(0,-.1,0)),"extras":{"rmmo_collision":"walk"}},{"mesh":wall,"transform":Transform3D(Basis.IDENTITY,Vector3(20,2.5,0)),"extras":{"rmmo_collision":"block"}}]
	var first=await load_nav(Vector3.ZERO)
	check(not first._initial_cache_hit and first._staged and not first.fully_ready,"cold spawn navigation publishes locally and writes its own cache")
	var vertices:PackedVector3Array=first.mesh.get_vertices();var polygons:Array=[]
	for i in first.mesh.get_polygon_count():polygons.append(first.mesh.get_polygon(i))
	var cache_path:String=Cache.path(first._initial_cache_key);first.free()
	var warm=await load_nav(Vector3.ZERO)
	check(warm._initial_cache_hit and not warm.fully_ready,"warm spawn cache never masquerades as full-map navigation")
	var equal_:bool=vertices==warm.mesh.get_vertices() and polygons.size()==warm.mesh.get_polygon_count()
	for i in mini(polygons.size(),warm.mesh.get_polygon_count()):equal_=equal_ and polygons[i]==warm.mesh.get_polygon(i)
	check(equal_,"cached local vertices and polygons match exact initial bake")
	var route:Dictionary=warm.find_path(Vector3(5,.05,0),Vector3(35,.05,0))
	check(route.ok and route.path.size()>2,"cached local route still goes around the wall")
	check(not warm._inside_local(Vector3(100,0,0),2),"local cache retains its clip boundary")
	warm.free()
	var moved=await load_nav(Vector3(32,0,0));check(not moved._initial_cache_hit,"changed spawn clip cannot reuse old initial region");moved.free()
	var taller=await load_nav(Vector3.ZERO,2.0);check(not taller._initial_cache_hit,"changed agent height invalidates initial region");taller.free()
	FileAccess.open(cache_path,FileAccess.WRITE).store_string("truncated")
	var repaired=await load_nav(Vector3.ZERO);check(not repaired._initial_cache_hit and repaired.mesh.get_polygon_count()>0,"corrupt spawn cache safely rebakes");repaired.free()
	for path:String in paths:DirAccess.remove_absolute(path)
	print("INITIAL_NAVIGATION_CACHE_FINISHED failures=",failures);quit(1 if failures else 0)
