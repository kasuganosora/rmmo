extends SceneTree
## CPU-only policy boundaries with tiny topology fixtures; no readback/cooking.
const Policy=preload("res://scripts/world_editor/picking_lod_policy.gd")
var failed:=0
var records:Dictionary={}

func check(ok:bool,label:String)->void:
	print("%s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:failed+=1

func allowed(node:Node)->bool:
	return not node.get_meta("editor_floor_excluded",false) and not node.get_meta("editor_shadow_proxy",false) and (not node is Node3D or node.visible)

func lookup(uuid:String)->Dictionary:return records.get(uuid,{})

func asset(uuid:String)->Node3D:
	var holder:=Node3D.new();holder.set_meta("asset_uuid",uuid)
	records[uuid]={"uuid":uuid,"kind":"asset"}
	return holder

func mesh(parent:Node,role:String,group:String="foliage")->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new()
	node.set_meta("extras",{"rmmo_collision":"none","rmmo_editor_picking":{"version":1,"group":group,"role":role}})
	parent.add_child(node);return node

func plan(holder:Node)->Dictionary:return Policy.build(holder,allowed,lookup)

func triangle_mesh()->ArrayMesh:
	var source:=ArrayMesh.new()
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return source

func _initialize()->void:
	var previous:=Policy.enabled
	var holder:=asset("a")
	var canonical:=mesh(holder,"canonical");canonical.name="NotNamedLOD0"
	var alternate:=mesh(holder,"render_lod");alternate.name="NotNamedLOD1"
	var last:=mesh(holder,"render_lod");last.name="IndependentName"
	Policy.enabled=false
	check(plan(holder).is_empty(),"default/control switch preserves all bodies")
	Policy.enabled=true
	var result:=plan(holder)
	check(result.size()==2 and result.has(alternate.get_instance_id()) and result.has(last.get_instance_id()) and not result.has(canonical.get_instance_id()),"explicit closed group removes only alternate bodies; canonical none remains pickable")
	var original:Dictionary=canonical.get_meta("extras").duplicate(true)
	plan(holder)
	check(canonical.get_meta("extras")==original and not canonical.has_meta("picking_lod_skip"),"planning never mutates or serializes runtime metadata")
	canonical.visibility_range_begin=200.;canonical.visibility_range_end=300.
	check(plan(holder).size()==2,"render distance does not alter canonical editor geometry")
	canonical.hide();check(plan(holder).is_empty(),"hidden canonical fails entire group closed");canonical.show()
	var hidden_parent:=Node3D.new();holder.add_child(hidden_parent)
	canonical.reparent(hidden_parent,false);hidden_parent.hide()
	check(plan(holder).is_empty(),"inherited canonical visibility rejects suppression even when canonical local visible remains true")
	hidden_parent.show();canonical.reparent(holder,false);hidden_parent.free()
	holder.set_meta("editor_floor_excluded",true);check(plan(holder).is_empty(),"isolation excludes canonical even when local visible is true");holder.remove_meta("editor_floor_excluded")
	canonical.scale=Vector3(0,1,1);check(plan(holder).is_empty(),"singular canonical transform cannot suppress alternatives");canonical.scale=Vector3.ONE
	canonical.mesh=ArrayMesh.new();check(plan(holder).is_empty(),"empty canonical cannot suppress the only pickable alternatives");canonical.mesh=BoxMesh.new()
	canonical.set_meta("paint_source",ArrayMesh.new())
	check(plan(holder).is_empty(),"picking validity follows paint_source instead of a replacement display mesh")
	canonical.remove_meta("paint_source")
	var mixed:=triangle_mesh();canonical.mesh=mixed
	check(plan(holder).size()==2,"real unindexed triangle canonical accepts native topology descriptors")
	var lines:Array=[];lines.resize(Mesh.ARRAY_MAX);lines[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.UP])
	mixed.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,lines)
	check(plan(holder).is_empty(),"later line surface cannot hide behind a valid first triangle surface")
	var points:Array=[];points.resize(Mesh.ARRAY_MAX);points[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.UP,Vector3.RIGHT])
	var mixed_points:=triangle_mesh();mixed_points.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS,points);canonical.mesh=mixed_points
	check(plan(holder).is_empty(),"point surface with divisible-by-three count still rejects canonical suppression")
	var indexed:=ArrayMesh.new();var indexed_arrays:Array=[];indexed_arrays.resize(Mesh.ARRAY_MAX)
	indexed_arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD,Vector3(1,0,-1)])
	indexed_arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,3,2]);indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,indexed_arrays);canonical.mesh=indexed
	check(plan(holder).size()==2,"indexed canonical validates triangle index count rather than unique vertex count")
	canonical.mesh=BoxMesh.new()
	last.set_meta("editor_shadow_proxy",true)
	check(plan(holder).size()==2,"hidden alternate remains group member and never prunes unrelated geometry")
	var hidden_extras:Dictionary=last.get_meta("extras").duplicate(true)
	hidden_extras.rmmo_editor_picking.role="unknown";last.set_meta("extras",hidden_extras)
	check(plan(holder).is_empty(),"hidden malformed member still invalidates its whole group")
	hidden_extras.rmmo_editor_picking.role="render_lod";last.set_meta("extras",hidden_extras)
	last.remove_meta("editor_shadow_proxy")
	records.a.collision="none"
	var nonphysical:=plan(holder)
	check(nonphysical.size()==2 and nonphysical.has(alternate.get_instance_id()) and nonphysical.has(last.get_instance_id()) and not nonphysical.has(canonical.get_instance_id()),"record none keeps exact canonical picking while removing redundant nonphysical LOD bodies")
	check(canonical.get_meta("extras")==original and records.a.collision=="none","record none optimization leaves source metadata and authored collision unchanged")
	for override in ["walk","block","invalid",null,true,7]:
		records.a.collision=override
		check(plan(holder).is_empty(),"physical or unknown record collision override retains all authored geometry: "+str(override))
	records.a.erase("collision")
	var extras:Dictionary=alternate.get_meta("extras")
	extras.rmmo_collision="block";alternate.set_meta("extras",extras)
	check(plan(holder).is_empty(),"authored blocking alternate retains all physical bodies")
	extras.rmmo_collision="none";alternate.set_meta("extras",extras)
	for bad in [{"version":true,"group":"foliage","role":"render_lod"},{"version":2,"group":"foliage","role":"render_lod"},{"version":1,"group":"foliage","role":"guess"},{"version":1,"group":"foliage","role":"render_lod","unknown":true},{"group":"foliage","role":"render_lod"}]:
		extras.rmmo_editor_picking=bad;alternate.set_meta("extras",extras)
		check(plan(holder).is_empty(),"invalid declaration poisons its entire known group: "+str(bad))
	extras.rmmo_editor_picking={"version":1.0,"group":"foliage","role":"canonical"};alternate.set_meta("extras",extras)
	check(plan(holder).is_empty(),"duplicate canonical never guessed from names or bounds")
	check(plan(canonical).is_empty(),"partial-subtree rebuild still checks duplicate canonical in full asset scope")
	extras.rmmo_editor_picking.role="render_lod";alternate.set_meta("extras",extras)
	check(plan(holder).size()==2,"JSON numeric version remains valid")
	var child:=mesh(alternate,"canonical","other")
	var child_alt:=mesh(alternate,"render_lod","other")
	check(plan(holder).size()==3 and not plan(holder).has(child.get_instance_id()) and plan(holder).has(child_alt.get_instance_id()),"skipped parent does not swallow independent child group")
	var unmarked:=MeshInstance3D.new();unmarked.mesh=ArrayMesh.new();alternate.add_child(unmarked)
	unmarked.set_meta("extras",{"rmmo_collision":"block"})
	check(not plan(holder).has(unmarked.get_instance_id()),"unmarked physical child remains independently eligible")
	var nested:=asset("b");holder.add_child(nested)
	var nested_alt:=mesh(nested,"render_lod")
	check(not plan(holder).has(nested_alt.get_instance_id()),"nested asset cannot borrow another UUID canonical")
	mesh(nested,"canonical")
	check(plan(holder).has(nested_alt.get_instance_id()),"same group identifier scopes independently to each asset instance")
	var prior:Dictionary=records.b;records.b={"uuid":"different","kind":"asset"}
	check(not plan(holder).has(nested_alt.get_instance_id()),"mismatched document identity cannot suppress a body")
	records.b=prior
	holder.remove_child(canonical)
	var without_canonical:=plan(holder)
	check(not without_canonical.has(alternate.get_instance_id()) and not without_canonical.has(last.get_instance_id()),"new partial-rebuild plan retains alternatives when canonical was removed")
	check(without_canonical.has(child_alt.get_instance_id()) and without_canonical.has(nested_alt.get_instance_id()),"canonical removal leaves independently closed child and nested groups intact")
	holder.add_child(canonical)
	check(plan(holder).has(alternate.get_instance_id()) and plan(holder).has(last.get_instance_id()),"restoring canonical recomputes suppression without cached stale node identities")
	var legacy:=asset("legacy")
	for index in 2:
		var node:=MeshInstance3D.new();node.name="LOD"+str(index);node.mesh=ArrayMesh.new();legacy.add_child(node)
		node.set_meta("extras",{"rmmo_collision":"none","rmmo_visibility_range":{"begin":index*10,"end":(index+1)*10,"bounds":[0,0,0,1,1,1]}})
	check(plan(legacy).is_empty(),"legacy LOD names/equal bounds/ranges are never inferred as picking identity")
	holder.free();legacy.free();Policy.enabled=previous
	print("EDITOR_PICKING_LOD_POLICY_FAILED=",failed);quit(1 if failed else 0)
