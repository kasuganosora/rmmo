extends RefCounted
## Main-thread, bounded delta selection. No scene/record mutation while selecting.
var previous:Vector2i
var unfinished:Array
var bins:Array=[]
var groups:Array=[]
var landscape:Array=[]
var selected:Dictionary={}
var old_draw:Dictionary
var next_draw:Dictionary
var draws:Callable
var stage:=0
var cursor:=0
var bin_cursor:=0
var cell_queries:Array=[]
var cell_query_cursor:=0
var visited_cells:=0

func _init(root:Node,from:Vector2i,to:Vector2i,pending:Array,stream:Script)->void:
	previous=from;unfinished=pending;draws=stream._draws
	bins.append(pending)
	# Publication can add records without changing the focus cell. The old
	# and new residency rings are then identical: only unfinished/new records
	# can change. Do not compare every building and landscape item to itself.
	if from==to:return
	var visual_radius:int=stream.render_radius(root)
	for field:StringName in [&"stream_prop_index",&"stream_collision_index"]:
		var radius:int=visual_radius if field==&"stream_prop_index" else stream.COLLISION_RADIUS
		cell_queries.append(preload("res://scripts/world3d/stream_cell_query.gd").new(root.get_meta(field,{}),from,to,radius))
	old_draw=stream._ring_at(from,visual_radius);next_draw=stream._ring_at(to,visual_radius)
	groups=root.get_meta("stream_building_groups",{}).values()
	landscape=root.get_meta("stream_landscape",[])

func advance(budget_usec:int)->bool:
	if budget_usec<=0:return false
	var deadline:=Time.get_ticks_usec()+budget_usec
	var advanced:=false
	while not advanced or Time.get_ticks_usec()<deadline:
		advanced=true
		if cell_query_cursor<cell_queries.size():
			var query:RefCounted=cell_queries[cell_query_cursor]
			if not query.advance(maxi(1,deadline-Time.get_ticks_usec())):return false
			bins.append_array(query.bins);visited_cells+=query.visited_cells;cell_query_cursor+=1
			continue
		if stage==0:
			if bin_cursor>=bins.size():stage=1;cursor=0;continue
			var bin:Array=bins[bin_cursor]
			if cursor>=bin.size():bin_cursor+=1;cursor=0;continue
			var spec:Dictionary=bin[cursor];selected[spec.uuid]=spec;cursor+=1
		elif stage==1:
			if cursor>=groups.size():stage=2;cursor=0;continue
			var members:Array=groups[cursor];cursor+=1
			if draws.call(members[0],old_draw)!=draws.call(members[0],next_draw):bins.append(members)
		elif stage==2:
			if cursor>=landscape.size():stage=3;cursor=0;continue
			var spec:Dictionary=landscape[cursor];cursor+=1
			if draws.call(spec,old_draw)!=draws.call(spec,next_draw):selected[spec.uuid]=spec
		else:
			# Newly visible whole-building members share the same bounded cursor.
			if bin_cursor>=bins.size():return true
			var bin:Array=bins[bin_cursor]
			if cursor>=bin.size():bin_cursor+=1;cursor=0;continue
			var spec:Dictionary=bin[cursor];selected[spec.uuid]=spec;cursor+=1
	return false
