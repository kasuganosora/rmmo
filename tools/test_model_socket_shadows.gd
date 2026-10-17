extends SceneTree
## CPU regression: derived fixture self-shadow suppression is narrowly scoped.
const Components=preload('res://scripts/world3d/model_components.gd')
const Stream=preload('res://scripts/world3d/world_stream.gd')
var checks:Array=[]
var failures:Array=[]
var socket:Dictionary={'position':[0,0,0],'color':[1,0.9,0.8],'range':5.0,'energy':1.0,'flame':false,'indoor':true}
func _initialize()->void:call_deferred('run')
func check(condition:bool,label:String)->void:
 checks.append({'label':label,'passed':condition})
 if not condition:failures.append(label);push_error(label)
func material(emits:bool=true)->StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.emission_enabled=emits;m.emission=Color.WHITE;m.emission_energy_multiplier=2
 return m
func mesh(parent:Node,name_:String,emits:bool=true)->MeshInstance3D:
 var n:=MeshInstance3D.new();n.name=name_;var box:=BoxMesh.new();box.size=Vector3.ONE;box.material=material(emits);n.mesh=box
 n.set_meta('extras',{'uuid':name_,'rmmo_collision':'none'});parent.add_child(n);return n
func fixture(opted:bool=true,socket_:Dictionary=socket)->Node3D:
 var n:=Node3D.new();n.name='Fixture';n.set_meta('extras',{'asset_id':'test','rmmo_light_socket':socket_.duplicate(true)})
 if opted:n.get_meta('extras').delivery_stage='textured_repair_v2'
 root.add_child(n);return n
func apply(n:Node3D)->void:Components.apply(n,{'kind':'asset','uuid':'socket_test'})
func append_faces(result:ArrayMesh,faces:PackedVector3Array,mat:Material)->void:
 var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=faces
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(result.get_surface_count()-1,mat)
func run()->void:
 var n:=fixture();n.rotation=Vector3(.2,.7,-.1);n.scale=Vector3(2,3,.6)
 var emitter:=mesh(n,'emitter');var frame:=mesh(n,'frame',false)
 var original_mesh:Mesh=emitter.mesh;var original_material:Material=emitter.get_active_material(0)
 apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,'enclosed luminous solid no longer shadows its own light under rotated/scaled parents')
 check(frame.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'enclosing non-emissive frame retains shadow')
 check(emitter.mesh==original_mesh and emitter.get_active_material(0)==original_material,'shared mesh and material remain immutable')
 var batch_before:int=n.get_meta('model_component_batch_sources').size();var extra_before:Dictionary=emitter.get_meta('extras').duplicate(true)
 apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and frame.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'apply is shadow-idempotent')
 check(n.get_meta('model_component_batch_sources').size()==batch_before and emitter.get_meta('extras')==extra_before,'apply preserves source count and socket extras on repeat')
 var spec:=Stream._spec(emitter);var spawned:=Stream._spawn(spec)
 check(spec.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and spawned.cast_shadow==spec.cast_shadow,'stream flatten and respawn preserve disabled emitter shadow')
 spawned.free();n.free()
 n=fixture(false);emitter=mesh(n,'no_optin');apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'unopted asset is unchanged');n.free()
 var bad:Dictionary=socket.duplicate(true);bad.range=-1
 n=fixture(true,bad);emitter=mesh(n,'bad_socket');apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'invalid socket is unchanged');n.free()
 for position:Vector3 in [Vector3(.5,0,0),Vector3(2,0,0)]:
  var at:Dictionary=socket.duplicate(true);at.position=[position.x,position.y,position.z]
  n=fixture(true,at);emitter=mesh(n,'boundary_or_outside');apply(n)
  check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'boundary/outside socket remains shadowed '+str(position));n.free()
 n=fixture();emitter=mesh(n,'missing_material');emitter.mesh.material=null;apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'missing material is conservative');n.free()
 n=fixture();emitter=mesh(n,'opaque_override');emitter.material_override=material(false);apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'active non-emissive material override wins');n.free()
 n=fixture();emitter=mesh(n,'opaque_surface');emitter.set_surface_override_material(0,material(false));apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'active non-emissive surface override wins');n.free()
 n=fixture();emitter=mesh(n,'mixed');var mixed:=ArrayMesh.new();var box:=BoxMesh.new();box.size=Vector3.ONE
 var faces:=box.get_faces();append_faces(mixed,faces.slice(0,18),material());append_faces(mixed,faces.slice(18),material(false));emitter.mesh=mixed;apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'mixed emitting/opaque surfaces keep shadow');n.free()
 n=fixture();emitter=mesh(n,'open_shell');var open:=ArrayMesh.new();append_faces(open,faces.slice(3),material());emitter.mesh=open;apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'open non-manifold emitter is conservative');n.free()
 n=fixture();emitter=mesh(n,'hollow');var hollow:=ArrayMesh.new();var inner:=PackedVector3Array()
 for v in faces:inner.append(v*.4)
 append_faces(hollow,faces,material());append_faces(hollow,inner,material());emitter.mesh=hollow;apply(n)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'socket inside hollow cavity does not count as inside luminous solid');n.free()
 # A closed tetrahedron supplies a sloping face boundary inside its AABB.
 n=fixture();emitter=mesh(n,'sloped_boundary');var tetra:=ArrayMesh.new()
 var a:=Vector3(0,0,1);var b:=Vector3(-1,-1,-1);var c:=Vector3(1,-1,-1);var d:=Vector3(0,1,-1)
 append_faces(tetra,PackedVector3Array([a,b,c,a,c,d,a,d,b,b,d,c]),material());emitter.mesh=tetra
 check(not Components._encloses_emitting_socket(emitter,(a+b+c)/3),'socket on sloping triangle boundary is conservative');n.free()
 var model:=Node3D.new();root.add_child(model);model.set_meta('extras',{'delivery_stage':'textured_repair_v2'})
 var owner:=Node3D.new();model.add_child(owner);owner.set_meta('extras',{'rmmo_light_socket':socket.duplicate(true)})
 emitter=mesh(owner,'inside_fixture');var sibling:=mesh(model,'outside_fixture');apply(model)
 check(emitter.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and sibling.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,'valid socket only changes its own subtree');model.free()
 var actual:Array=[]
 for aid:String in ['guild_hall_lantern','guild_facade_wall_lantern']:
  var path:='D:/code/rmmo_runtime/review_artifacts/guild_reference_recheck_20261013/accepted_library/'+aid+'/asset.scn'
  var packed:PackedScene=load(path);model=packed.instantiate();root.add_child(model)
  var shadow_before:Dictionary={}
  for part:MeshInstance3D in model.find_children('*','MeshInstance3D',true,false):shadow_before[part.get_instance_id()]=part.cast_shadow
  apply(model);var changed:Array=[]
  for part:MeshInstance3D in model.find_children('*','MeshInstance3D',true,false):
   if part.cast_shadow!=shadow_before[part.get_instance_id()]:changed.append(str(part.name))
  check(changed.size()==1,'actual '+aid+' changes only the enclosing magic stone')
  actual.append({'asset_id':aid,'changed_meshes':changed,'native_sha256':FileAccess.get_sha256(path)});model.free()
 var report:={'passed':failures.is_empty(),'checks':checks,'failures':failures,'actual_assets':actual,
  'implementation_sha256':FileAccess.get_sha256('res://scripts/world3d/model_components.gd'),
  'scope':'headless logic and actual Native nodes only; no GPU visual assertion'}
 var out:=FileAccess.open('D:/code/rmmo_runtime/review_artifacts/guild_reference_recheck_20261013/socket_shadow_regression.json',FileAccess.WRITE)
 out.store_string(JSON.stringify(report,'  '));print('SOCKET_SHADOW_TEST ',JSON.stringify(report));quit(0 if failures.is_empty() else 1)
