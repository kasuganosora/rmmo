extends RefCounted
## Stable partition of one pending plan. The caller keeps its current job and
## residency fixed until commit; cancellation leaves the original Array intact.
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
const EMPTY:Dictionary={}
var stream:Script
var jobs:Array
var cursor:int
var origin:Vector3
var bodies:Dictionary
var draw:Dictionary
var meshes:Dictionary
var at:int
var count:int
var area:Rect2
var low:Vector2i
var high:Vector2i
var bins:Array=[[],[],[],[]]
var groups:Dictionary={}
var cells:Dictionary={}
var reuse:bool
var complete:=false
var previous_classes:Dictionary={}
var changed:Dictionary={}
var classifications:Dictionary={}
var partition:Dictionary={}
var _range_classes:Dictionary={}
var profile:Dictionary={"rows":0,"classified_rows":0,"reused_rows":0,"bulk_reused_rows":0,"setup_us":0,"mesh_bounds":0,"chunk_rejections":0,"slices":0,"elapsed_us":0,"max_slice_us":0}
func _init(api:Script,values:Array,active:int,point:Vector3,live_bodies:Dictionary,envelope:Dictionary,live_meshes:Dictionary,previous:Dictionary={},dirty:Dictionary={},previous_partition:Dictionary={})->void:
	var began:=Time.get_ticks_usec()
	previous_classes=previous;changed=dirty
	stream=api;jobs=values;cursor=active;origin=point;bodies=live_bodies;draw=envelope;meshes=live_meshes
	at=cursor+1;count=jobs.size();area=Rect2(origin.x-6.,origin.z-6.,12.,12.)
	low=stream.chunk_key(Vector3(area.position.x,0,area.position.y));high=stream.chunk_key(Vector3(area.end.x,0,area.end.y))
	reuse=stream.collision_priority_reuse_enabled and not stream._draw_uses_exact_geometry(draw)
	_seed_ranges(previous_partition)
	profile.setup_us=Time.get_ticks_usec()-began

func _seed_ranges(previous:Dictionary)->void:
	# A completed stable partition already describes the untouched old tail.
	# Only append-only arrivals with the same owner/origin may reuse its ranges;
	# changed old support falls back to the ordinary bounded repair below.
	if previous.is_empty() or previous_classes.is_empty() or previous_classes.is_read_only() or not is_same(previous.get("classes"),previous_classes) or not is_same(previous.get("jobs"),jobs) or previous.get("origin")!=origin:return
	var old_count:int=int(previous.get("count",0));var old_cursor:int=int(previous.get("cursor",-1))
	var cuts:Variant=previous.get("cuts")
	if old_cursor<0 or cursor<old_cursor or old_count>count or not cuts is PackedInt32Array or cuts.size()!=5 or cuts[0]!=old_cursor+1 or cuts[4]!=old_count:return
	for id:String in changed:
		if previous_classes.has(id):return
	for i:int in 4:
		if cuts[i]>cuts[i+1]:return
	# This serial planner owns the previous classification table. Accumulate only
	# new entries privately; transfer that owner at commit, after cancellation can
	# no longer leave a half-written table. A native full Dictionary copy still
	# scales with the old queue even when the GDScript row loop has disappeared.
	_range_classes=previous_classes
	for i:int in 4:
		var begin:=maxi(cursor+1,cuts[i]);var end:int=cuts[i+1]
		if begin<end:
			bins[i]=jobs.slice(begin,end)
			profile.bulk_reused_rows+=end-begin;profile.reused_rows+=end-begin
	at=maxi(at,old_count)
func advance(budget_usec:int)->bool:
	var began:=Time.get_ticks_usec()
	while at<count:
		var spec:Dictionary=jobs[at];at+=1;profile.rows+=1
		var id:String=spec.uuid;var priority:int
		if previous_classes.has(id) and not changed.has(id):
			priority=previous_classes[id];profile.reused_rows+=1
		else:
			priority=_classify(spec);profile.classified_rows+=1
		classifications[id]=priority;bins[priority].append(spec)
		if budget_usec>0 and Time.get_ticks_usec()-began>=budget_usec:break
	if at==count:
		# Four native appends replace thousands of script-level Array writes.
		jobs.resize(cursor+1)
		var cuts:=PackedInt32Array([cursor+1])
		for bin:Array in bins:jobs.append_array(bin);cuts.append(jobs.size())
		if not _range_classes.is_empty():
			_range_classes.merge(classifications,true);classifications=_range_classes
		partition={"jobs":jobs,"classes":classifications,"count":count,"cursor":cursor,"origin":origin,"cuts":cuts}
		complete=true
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(profile.max_slice_us,elapsed)
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.collision_priority_slice",began,{"rows":profile.rows,"classified_rows":profile.classified_rows,"reused_rows":profile.reused_rows,"complete":complete,"chunk_rejections":profile.chunk_rejections,"mesh_bounds":profile.mesh_bounds})
	return complete

func _classify(spec:Dictionary)->int:
	var extra:Dictionary=spec.get("extras",EMPTY);var id:String=spec.uuid
	var ground:bool=spec.has("ground_batch_record") and Landscape.ground(spec)
	if not draw.is_empty() and ground and (stream._priority_draws(spec,draw,groups) if reuse else stream._draws(spec,draw)):return 0
	var eligible:bool=not extra.get("hostile",false) and not extra.get("ally",false) and not spec.get("native_visual",false)
	var near:bool=eligible and not bodies.has(id) and extra.get("rmmo_collision","")!="none"
	if near and not spec.has("collision_mesh") and spec.has("chunk_min") and spec.has("chunk_max"):
		var a:Vector2i=spec.chunk_min;var b:Vector2i=spec.chunk_max
		if a.x>high.x or b.x<low.x or a.y>high.y or b.y<low.y:near=false;profile.chunk_rejections+=1
	if near:
		var mesh:Mesh=spec.get("collision_mesh",spec.get("mesh"));profile.mesh_bounds+=1
		var bounds:AABB=spec.transform*(AABB(-mesh.size*.5,mesh.size) if mesh is BoxMesh else mesh.get_aabb())
		near=area.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true)
	if near:return 0 if ground else 1
	if eligible and not draw.is_empty() and not meshes.has(id) and (stream._priority_overlaps(spec,draw,cells) if reuse else stream._overlaps(spec,draw)) and (stream._priority_draws(spec,draw,groups) if reuse else stream._draws(spec,draw)):return 2
	return 3
