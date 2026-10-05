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

func _init(root:Node,from:Vector2i,to:Vector2i,pending:Array,stream:Script)->void:
	previous=from;unfinished=pending;draws=stream._draws
	bins.append(pending)
	for radius in [stream.RENDER_RADIUS,stream.COLLISION_RADIUS]:
		var index:Dictionary=root.get_meta("stream_prop_index" if radius==stream.RENDER_RADIUS else "stream_collision_index",{})
		var old:Dictionary=stream._ring_at(from,radius);var next:Dictionary=stream._ring_at(to,radius)
		for center in [from,to]:
			for z in range(center.y-radius,center.y+radius+1):
				for x in range(center.x-radius,center.x+radius+1):
					var inside_old:bool=x>=old.low.x and x<=old.high.x and z>=old.low.y and z<=old.high.y
					var inside_next:bool=x>=next.low.x and x<=next.high.x and z>=next.low.y and z<=next.high.y
					if inside_old!=inside_next:bins.append(index.get(Vector2i(x,z),[]))
	old_draw=stream._ring_at(from,stream.RENDER_RADIUS);next_draw=stream._ring_at(to,stream.RENDER_RADIUS)
	groups=root.get_meta("stream_building_groups",{}).values()
	landscape=root.get_meta("stream_landscape",[])

func advance(budget_usec:int)->bool:
	var deadline:=Time.get_ticks_usec()+budget_usec
	while Time.get_ticks_usec()<deadline:
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
