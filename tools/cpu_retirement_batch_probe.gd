extends RefCounted
## Pure-data prototype. Main only transfers array roots; each queue has one reader.
const Size=preload("res://scripts/world3d/cpu_geometry_size.gd")
const LIMIT:=1024
var batches:Array=[]
var current:Array=[]
func append(surfaces:Array,lods:Array,faces:PackedVector3Array,key:String)->void:
	if current.size()>=LIMIT*4 or current.is_empty():
		current=[];batches.append(current)
	current.append(surfaces);current.append(lods);current.append(faces);current.append(key)
static func release(values:Array,sizes:RefCounted)->Dictionary:
	var count:=values.size()/4;var began:=Time.get_ticks_usec()
	# Once all pure arrays are transferred, measuring a release threshold has no
	# purpose. No byte estimate is needed to return the original admission lease.
	values.clear()
	return {"bytes":0,"count":count,"us":Time.get_ticks_usec()-began,"thread":OS.get_thread_caller_id()}
