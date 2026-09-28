extends RefCounted
## Lifecycle adapter for the existing GPU cloth backend; no solver tuning here.
const Adapter=preload("res://scripts/char/garment_candidate_cloth.gd")
var body:Node3D
var wardrobe:Node3D
var entries:Dictionary={}
var requested:Array=[]
var error:=""
var scene_colliders:Array[MeshInstance3D]=[]
func set_scene_colliders(objects:Array)->void:
 var selected:Array[MeshInstance3D]=[]
 for object in objects:
  if not is_instance_valid(object) or not object is MeshInstance3D:continue
  if object.mesh==null:continue
  if (object.global_transform*object.get_aabb()).grow(2.0).has_point(body.global_position):selected.append(object)
 selected.sort_custom(func(a,b):return a.get_instance_id()<b.get_instance_id())
 if selected==scene_colliders:return
 scene_colliders=selected
 # GPU external triangle capacity is fixed at initialization.
 invalidate()
func configure(target:Node3D,clothes:Node3D)->void:
 body=target;wardrobe=clothes
func clear()->void:
 for entry:Dictionary in entries.values():
  if is_instance_valid(entry.adapter):entry.adapter.free()
 entries.clear()
func reconcile(slots:Array)->void:
 requested=slots.duplicate()
 for slot:String in entries.keys():
  var entry:Dictionary=entries[slot]
  if slot not in slots or not is_instance_valid(entry.garment) or wardrobe.garments.get(slot)!=entry.garment:
   if is_instance_valid(entry.adapter):entry.adapter.free()
   entries.erase(slot)
 for slot in slots:
  if entries.has(slot) or not wardrobe.garments.has(slot):continue
  var garment:Node3D=wardrobe.garments[slot]
  if not garment.cloth_enabled:continue
  var adapter:=Adapter.new();garment.add_child(adapter)
  if not adapter.initialize(garment,scene_colliders):
   error=adapter.frame_error;adapter.free();continue
  entries[slot]={"adapter":adapter,"garment":garment,"prepared_frames":0}
func invalidate()->void:
 clear();reconcile(requested)
func is_ready()->bool:
 for entry:Dictionary in entries.values():
  if int(entry.prepared_frames)<65:return false
 return error.is_empty()
func advance(delta:float)->void:
 if entries.is_empty():return
 # Only final blended angles are observed. Temporary preparation solves are
 # synchronous, signal-suppressed, and restored before any rendered frame.
 var current:Dictionary={}
 for node:Dictionary in body.nodes:current[node.name]=node.angles*180.0/PI
 var old_recipe:Dictionary=body.angles_by_name.duplicate(true)
 var offset:Vector3=body.root_offset
 var blocked:bool=body.is_blocking_signals()
 for slot:String in entries.keys():
  var entry:Dictionary=entries[slot];var adapter:Node3D=entry.adapter
  if not adapter.solver._gpu_init_done:continue
  var preparing:bool=int(entry.prepared_frames)<65
  if preparing:
   var temporary:Dictionary={};var fraction:float=minf(float(entry.prepared_frames)/45.0,1.0)
   for bone:String in current:temporary[bone]=current[bone]*fraction
   body.set_block_signals(true);body.set_angles(temporary,offset)
  var success:bool=adapter.advance(1.0/60.0 if preparing else delta)
  if preparing:
   body.set_angles(current,offset);body.angles_by_name=old_recipe
   body.set_block_signals(blocked)
   entry.prepared_frames+=1
   for i in entry.garment.mesh_instance.mesh.get_surface_count():
    entry.garment.mesh_instance.mesh.surface_get_material(i).set_shader_parameter("candidate_simulate",success and int(entry.prepared_frames)>=65)
  if not success:
   error=adapter.frame_error;adapter.free();entries.erase(slot)
