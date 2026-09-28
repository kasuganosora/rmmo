extends RefCounted
## Shared facial semantics; per-actor weights live on the body, never in this cache.
const LABELS={"eye_smile":"笑い","eye_surprise":"びっくり","eye_squeeze":"ぎゅっ","brow_smile":"にこり","brow_serious":"真面目","blink":"まばたき","wink_left":"ウィンク","wink_right":"ウィンク右","smile":"微笑（組合せ）","brow_up":"上","brow_down":"下","brow_worried":"困る","brow_angry":"怒り","mouth_smile":"にやり","mouth_frown":"口角下げ","a":"あ","i":"い","u":"う","e":"え","o":"お","heart_eyes":"ハート","star_eyes":"星","circle_eyes":"丸目","blush":"照れ"}
const NAMES={"eye_smile":"闭眼笑","eye_surprise":"惊讶眼","eye_squeeze":"挤眼","brow_smile":"笑眉","brow_serious":"认真","blink":"闭眼","wink_left":"左眼眨眼","wink_right":"右眼眨眼","smile":"微笑","brow_up":"抬眉","brow_down":"压眉","brow_worried":"困扰","brow_angry":"皱眉","mouth_smile":"嘴角微笑","mouth_frown":"撇嘴","a":"啊 · あ","i":"衣 · い","u":"乌 · う","e":"诶 · え","o":"哦 · お","heart_eyes":"爱心眼","star_eyes":"星星眼","circle_eyes":"圆圈眼","blush":"脸红"}
const GROUPS={"眼睛":["eye_smile","eye_surprise","eye_squeeze","blink","wink_left","wink_right","smile"],"眉毛":["brow_smile","brow_serious","brow_up","brow_down","brow_worried","brow_angry"],"口型":["mouth_smile","mouth_frown","a","i","u","e","o"],"瞳孔效果":["heart_eyes","star_eyes","circle_eyes"],"肤色效果":["blush"]}
static func group_for(id:String)->String:
 for group:String in GROUPS:
  if id in GROUPS[group]:return group
 return ""
const SOURCE_SCALES={"eye_smile":{"PHMCheekEyeFlexL":.3,"PHMCheekEyeFlexR":.3},"eye_squeeze":{"PHMEyesSquintL":.35,"PHMEyesSquintR":.35},"eye_surprise":{"PHMEyeLidsBottomDownL":.4,"PHMEyeLidsBottomDownR":.4},"brow_smile":{"PHMBrowOuterDownL":.5,"PHMBrowOuterDownR":.5},"brow_serious":{"PHMBrowInnerDownL":.5,"PHMBrowInnerDownR":.5}}
const CHANNELS={
 "eye_smile":["PHMEyesClosedL","PHMEyesClosedR","PHMCheekEyeFlexL","PHMCheekEyeFlexR"],
 "eye_squeeze":["PHMEyesClosedL","PHMEyesClosedR","PHMEyesSquintL","PHMEyesSquintR"],
 "eye_surprise":["PHMEyeLidsTopUpL","PHMEyeLidsTopUpR","PHMEyeLidsBottomDownL","PHMEyeLidsBottomDownR"],
 "brow_smile":["PHMBrowOuterDownL","PHMBrowOuterDownR"],"brow_serious":["PHMBrowInnerDownL","PHMBrowInnerDownR"],
 "heart_eyes":[],"star_eyes":[],"circle_eyes":[],"blush":[],
 "a":["VSMAA"],"i":["VSMIY"],"u":["VSMUW"],"e":["VSMEH"],"o":["VSMOW"],
 "blink":["PHMEyesClosedL","PHMEyesClosedR"],
 "wink_left":["PHMEyesClosedL"],"wink_right":["PHMEyesClosedR"],
 "smile":["PHMEyesSquintL","PHMEyesSquintR","PHMMouthSmileSimpleL","PHMMouthSmileSimpleR"],
 "brow_up":["PHMBrowUpL","PHMBrowUpR"],"brow_down":["PHMBrowDownL","PHMBrowDownR"],
 "brow_worried":["PHMBrowInnerUpL","PHMBrowInnerUpR"],"brow_angry":["PHMBrowSqueeze"],
 "mouth_smile":["PHMMouthSmileSimpleL","PHMMouthSmileSimpleR"],"mouth_frown":["PHMMouthFrown"]}
static var sources:Dictionary={}
static func normalize(values:Dictionary)->Dictionary:
 var result:Dictionary={}
 for key in values:
  if not CHANNELS.has(key):return {"invalid":true}
  var value:Variant=values[key]
  if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)):return {"invalid":true}
  if float(value)>0:result[key]=clampf(float(value),0,1)
 var vowels:=0.0
 for key in ["a","i","u","e","o"]:vowels+=float(result.get(key,0))
 if vowels>1:
  for key in ["a","i","u","e","o"]:
   if result.has(key):result[key]/=vowels
 return result
static func evaluate(base:PackedVector3Array,values:Dictionary)->PackedVector3Array:
 if values.is_empty():return base.duplicate()
 if sources.is_empty():
  var path:String=preload("res://scripts/asset/art_paths.gd").path("characters/expressions/female_base_v2/native_face_01.json")
  if not FileAccess.file_exists(path):return PackedVector3Array()
  var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
  if not data is Dictionary or int(data.get("vertex_count",0))!=base.size():return PackedVector3Array()
  sources=data.morphs
 var weights:Dictionary={}
 for key in values:
  if not CHANNELS.has(key):return PackedVector3Array()
  for source:String in CHANNELS[key]:weights[source]=minf(1.0,float(weights.get(source,0))+float(values[key])*float(SOURCE_SCALES.get(key,{}).get(source,1.0)))
 var result:=base.duplicate()
 for source:String in weights:
  if not sources.has(source):return PackedVector3Array()
  for formula:Dictionary in sources[source].formulas:
   if int(formula.targetType) not in [13,14,15]:return PackedVector3Array()
  for delta:Array in sources[source].deltas:
   var index:=int(delta[0])
   if index<0 or index>=base.size():return PackedVector3Array()
   result[index]+=Vector3(delta[1],delta[2],delta[3])*float(weights[source])
 return result

static func bone_offsets(values:Dictionary)->Dictionary:
 var weights:Dictionary={};var result:Dictionary={}
 for key in values:
  for source:String in CHANNELS[key]:weights[source]=minf(1.0,float(weights.get(source,0))+float(values[key])*float(SOURCE_SCALES.get(key,{}).get(source,1.0)))
 for source:String in weights:
  for formula:Dictionary in sources.get(source,{}).get("formulas",[]):
   var axis:int=int(formula.targetType)-13
   if axis<0 or axis>2:continue
   var bone:String=formula.target
   var angles:Vector3=result.get(bone,Vector3.ZERO)
   angles[axis]+=deg_to_rad(float(formula.multiplier)*float(weights[source]))
   result[bone]=angles
 return result

# Names are a supported mapping, not a claim that every PMX morph is universal.
static func from_mmd(weights:Dictionary)->Dictionary:
 var values:Dictionary={}
 for tag in weights:
  var id:String=str(LABELS.find_key(tag)) if LABELS.values().has(tag) else ""
  if id.is_empty():return {"invalid":true}
  values[id]=weights[tag]
 return normalize(values)
