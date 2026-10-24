extends RefCounted
## Private parser output, transferred once after joining that parser. The source
## rows must not change between prepare and adoption; live requeue stays on main.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Kinds=preload("res://scripts/world3d/pending_kind_catalogue.gd")
static var enabled:=true
var rows:Array=[]
var count:=0
var owners:Dictionary={}
var cells:Dictionary={}
var native_cells:Dictionary={}
var large:Array=[]
var native_large:Dictionary={}
var kinds:RefCounted
var elapsed_us:=0
var consumed:=false

static func prepare(source:Array)->RefCounted:
	var began:=Time.get_ticks_usec()
	var result:=new()
	result.rows=source;result.count=source.size();result.kinds=Kinds.new()
	for item:Dictionary in source:
		var uuid:String=item.record.uuid
		result.owners[uuid]=item
		var box:AABB=item.bounds
		item.demand_rect=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))
		var low:=Stream.chunk_key(box.position);var high:=Stream.chunk_key(box.end)
		var is_large:bool=(high.x-low.x+1)*(high.y-low.y+1)>64
		result.kinds.add(item,is_large,{})
		if is_large:
			result.large.append(item);result.native_large[uuid]=item;continue
		for z in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell:=Vector2i(x,z)
				if not result.cells.has(cell):result.cells[cell]=[];result.native_cells[cell]={}
				result.cells[cell].append(item);result.native_cells[cell][uuid]=item
	result.kinds.building_count=0
	result.elapsed_us=Time.get_ticks_usec()-began
	return result

func matches(source:Array)->bool:
	return not consumed and is_same(rows,source) and source.size()==count and owners.size()==count

func relinquish()->void:
	# Assign fresh containers: the queue now owns the old ones. Clearing them
	# would mutate the adopted index through its shared Dictionary/Array storage.
	consumed=true;rows=[];owners={};cells={};native_cells={};large=[];native_large={};kinds=null
