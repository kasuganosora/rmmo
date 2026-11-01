extends "res://tools/test_stream_entry_scope.gd"
## Complete post-entry visual residency, independent of authored object category.
## Only temporary in-memory meshes; no source maps or imported assets changed.
const CandidatePlan=preload("res://scripts/world3d/stream_candidate_plan.gd")
const CellQuery=preload("res://scripts/world3d/stream_cell_query.gd")
const EXPECTED_VISUAL_RADIUS:=126 # Existing 4000m camera far + one orbit cell.

func run()->void:
	var core:=box("core",Vector3(4,1,4))
	var tree:=box("ordinary_tree",Vector3(384,6,8),Vector3(8,12,8))
	tree.extras.rmmo_wind={"profile":"foliage"}
	var prop:=box("ordinary_prop",Vector3(640,1,8))
	var house:=box("untagged_house",Vector3(800,3,8),Vector3(12,6,10))
	# The object's centre is outside the view; its actual bounds still cross it.
	var edge:float=(EXPECTED_VISUAL_RADIUS+1)*32.
	var long_object:=box("crossing_long_object",Vector3(edge+64.,1,8),Vector3(256,2,2))
	var leaving:=box("leaving_edge",Vector3(-EXPECTED_VISUAL_RADIUS*32.+16.,1,8))
	var entering:=box("entering_edge",Vector3(edge+16.,1,8))
	var outside:=box("outside_view",Vector3(edge+512.,1,8))
	var world:=scene([core,tree,prop,house,long_object,leaving,entering,outside])
	var entry:=AABB(Vector3(0,-5,0),Vector3(12,20,12))
	Stream.set_entry_scope(world.map,entry)
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(world.map.get_meta("stream_meshes").keys()==["core"],"minimum entry still limits the first presentation")
	var original:Node=world.map.get_meta("stream_meshes").core
	Stream.clear_entry_scope(world.map)
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	var meshes:Dictionary=world.map.get_meta("stream_meshes")
	for id:String in ["ordinary_tree","ordinary_prop","untagged_house","crossing_long_object","leaving_edge"]:
		check(meshes.has(id),"post-entry visual scope includes "+id)
	check(not meshes.has("outside_view") and not meshes.has("entering_edge"),"objects wholly beyond the visual boundary remain deferred")
	check(meshes.core==original,"expanding visual scope preserves the entry instance")
	check(world.map.get_meta("stream_bodies").keys()==["core"],"far visual demand never expands the physical residency ring")
	var pending:Array=[prop]
	var stationary:=CandidatePlan.new(world.map,Vector2i.ZERO,Vector2i.ZERO,pending,Stream)
	while not stationary.advance(2000):pass
	check(ids(stationary.selected.values())==["ordinary_prop"] and stationary.groups.is_empty() and stationary.landscape.is_empty(),"stationary publication only examines its pending objects")
	var crossed:=CandidatePlan.new(world.map,Vector2i.ZERO,Vector2i(1,0),[],Stream)
	while not crossed.advance(2000):pass
	var crossing_ids:=ids(crossed.selected.values())
	check("entering_edge" in crossing_ids and "leaving_edge" in crossing_ids,"a one-cell move selects both far visual boundary strips")
	check(not "ordinary_prop" in crossing_ids and not "untagged_house" in crossing_ids,"a one-cell move does not rescan interior visuals")
	for i in 200:
		Stream.sync(world.map,world.host,Vector3(36,0,4),1)
		if world.map.has_meta("stream_chunk"):break
	check(world.map.has_meta("stream_chunk"),"budgeted boundary change converges")
	check(meshes.has("entering_edge") and not meshes.has("leaving_edge"),"budgeted boundary change attaches and retires the correct far objects")
	check(world.map.get_meta("stream_bodies").keys()==["core"],"boundary transition still retains only nearby physics")
	Stream.sync(world.map,world.host,Vector3(10000,0,4))
	check(not meshes.has("ordinary_tree") and not meshes.has("ordinary_prop") and not meshes.has("untagged_house"),"leaving the visual region retires ordinary categories")
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(meshes.has("ordinary_tree") and meshes.has("ordinary_prop") and meshes.has("untagged_house") and meshes.has("crossing_long_object"),"return restores every category and crossing-boundary geometry")
	check(world.map.get_meta("stream_bodies").keys()==["core"],"return does not attach distant collision")
	range_changes(world)
	world.host.free()
	cell_queries()
	print("VISIBLE_OBJECT_RESIDENCY checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func range_changes(world:Dictionary)->void:
	var revision:int=world.map.get_meta("stream_source_revision",0)
	check(not Stream.set_render_radius(world.map,-1) and world.map.get_meta("stream_source_revision",0)==revision,"invalid view radius does not mutate residency")
	check(Stream.set_render_radius(world.map,2),"a smaller camera projection requests a residency update")
	Stream.sync(world.map,world.host,Vector3(4,0,4),1)
	check(Stream.set_render_radius(world.map,EXPECTED_VISUAL_RADIUS),"view expansion interrupts a partial shrink safely")
	for i in 200:
		Stream.sync(world.map,world.host,Vector3(4,0,4),1)
		if world.map.has_meta("stream_chunk"):break
	var meshes:Dictionary=world.map.get_meta("stream_meshes")
	check(world.map.has_meta("stream_chunk") and meshes.has("ordinary_tree") and meshes.has("untagged_house") and meshes.has("leaving_edge"),"stationary projection change converges without dropping unfinished visual work")
	check(world.map.get_meta("stream_bodies").keys()==["core"],"camera projection never changes physical range")
	Stream.set_render_radius(world.map,2)
	Stream.sync(world.map,world.host,Vector3(4,0,4))
	check(not meshes.has("ordinary_tree") and meshes.has("core"),"stationary projection shrink releases out-of-view visuals")
	var settled_revision:int=world.map.get_meta("stream_source_revision")
	check(not Stream.set_render_radius(world.map,2) and world.map.get_meta("stream_source_revision")==settled_revision,"unchanged projection does not trigger another scan")

func cell_queries()->void:
	var sparse:Dictionary={Vector2i.ZERO:[{"uuid":"inside"}],Vector2i(999,999):[{"uuid":"outside"}]}
	var all:=CellQuery.new(sparse,Vector2i.ZERO,Vector2i.ZERO,EXPECTED_VISUAL_RADIUS,false)
	all.finish()
	check(all.visited_cells==2 and all.bins.size()==1 and all.bins[0][0].uuid=="inside","a sparse full camera query visits occupied keys instead of 64009 empty cells")
	var dense:Dictionary={}
	for z in range(-130,131):
		for x in range(-130,131):dense[Vector2i(x,z)]=[{"uuid":"%d,%d"%[x,z]}]
	var edge:=CellQuery.new(dense,Vector2i.ZERO,Vector2i(1,0),EXPECTED_VISUAL_RADIUS)
	edge.finish()
	check(edge.visited_cells==2*(2*EXPECTED_VISUAL_RADIUS+1) and edge.bins.size()==edge.visited_cells,"dense one-cell movement visits only its entering and leaving strips")
	var jumped:=CellQuery.new(dense,Vector2i.ZERO,Vector2i(1000,1000),EXPECTED_VISUAL_RADIUS)
	var done:=jumped.advance(1)
	check(not done and jumped.visited_cells<dense.size(),"large-jump bucket selection itself is split across frame budgets")
	jumped.finish()
	check(jumped.bins.size()==(2*EXPECTED_VISUAL_RADIUS+1)*(2*EXPECTED_VISUAL_RADIUS+1),"large jump selects exact old occupied cells after bounded completion")
	# Compare diagonal and partial-overlap strips against an independent key test.
	for target:Vector2i in [Vector2i(2,-3),Vector2i(-126,126),Vector2i(252,0)]:
		var query:=CellQuery.new(dense,Vector2i.ZERO,target,EXPECTED_VISUAL_RADIUS)
		query.finish()
		var actual:Dictionary={}
		for bucket:Array in query.bins:actual[bucket[0].uuid]=true
		var expected:Dictionary={}
		for key:Vector2i in dense:
			var old_inside:=absi(key.x)<=EXPECTED_VISUAL_RADIUS and absi(key.y)<=EXPECTED_VISUAL_RADIUS
			var new_inside:=absi(key.x-target.x)<=EXPECTED_VISUAL_RADIUS and absi(key.y-target.y)<=EXPECTED_VISUAL_RADIUS
			if old_inside!=new_inside:expected[dense[key][0].uuid]=true
		check(actual==expected,"spatial delta matches independent coverage at "+str(target))
