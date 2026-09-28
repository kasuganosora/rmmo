extends RefCounted
## Identity deltas for the approved control topology, before axis deformation.
const Art=preload("res://scripts/asset/art_paths.gd")
const RANGES={"bust_size":Vector2(0,1),"hip_size":Vector2(-.75,1),"waist_width":Vector2(-1,1),"nose_width":Vector2(-.75,1),"height":Vector2(-1,1)}
static var sources:Dictionary={}
static func normalize(value:Variant)->Dictionary:
 var result:Dictionary={}
 if not value is Dictionary:return result
 for key:String in RANGES:
  var number:Variant=value.get(key,0.0)
  if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)):continue
  var bounded:float=clampf(float(number),RANGES[key].x,RANGES[key].y)
  if bounded!=0.0:result[key]=bounded
 return result

static func load_source(key:String)->Dictionary:
 if sources.has(key):return sources[key]
 var path:String=Art.path("characters/morphs/female_base_v2/source_native_01/"+key+".json")
 var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not parsed is Dictionary or parsed.get("id","")!=key:return {}
 var centers:Dictionary={}
 for formula:Dictionary in parsed.formulas:
  var type:=int(formula.targetType)
  if type not in [1,2,3] or not is_finite(float(formula.multiplier)):
   push_error("Shape requires unsupported joint formula: "+key);return {}
  var target:String=formula.target
  if not centers.has(target):centers[target]=Vector3.ZERO
  var center:Vector3=centers[target];center[type-1]+=float(formula.multiplier);centers[target]=center
 if not is_equal_approx(parsed.source.min,RANGES[key].x) or not is_equal_approx(parsed.source.max,RANGES[key].y):return {}
 var indices:=PackedInt32Array();var deltas:=PackedVector3Array();var seen:Dictionary={}
 for entry:Dictionary in parsed.deltas:
  var index:=int(entry.vertex);var delta:=Vector3(entry.delta.x,entry.delta.y,entry.delta.z)
  if index<0 or index>=21556 or seen.has(index) or not delta.is_finite():return {}
  seen[index]=true;indices.append(index);deltas.append(delta)
 sources[key]={"indices":indices,"deltas":deltas,"centers":centers}
 return sources[key]

static func evaluate(base:PackedVector3Array,values:Dictionary)->PackedVector3Array:
 if base.size()!=21556:return PackedVector3Array()
 var result:=base.duplicate()
 # Always start from the immutable baseline; never accumulate editing history.
 for key:String in RANGES:
  var weight:float=values.get(key,0.0)
  if weight==0.0:continue
  var source:=load_source(key)
  if source.is_empty():return PackedVector3Array()
  for i in source.indices.size():result[source.indices[i]]+=source.deltas[i]*weight
 return result

static func evaluate_rests(base:Dictionary,values:Dictionary)->Dictionary:
 var result:Dictionary=base.duplicate()
 for key:String in RANGES:
  var weight:float=values.get(key,0.0)
  if weight==0.0:continue
  var source:=load_source(key)
  if source.is_empty():return {}
  for bone:String in source.centers:
   if not result.has(bone):return {}
   var transform:Transform3D=result[bone]
   transform.origin+=source.centers[bone]*weight
   result[bone]=transform
 return result
