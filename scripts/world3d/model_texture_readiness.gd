extends RefCounted
## Runtime completion only. Reading the root's scalar table identity never walks
## materials/pixels. Native readers clear completion on each new file allocation.
const TABLE_META:=&"rmmo_model_texture_table_v1"
const READY_META:=&"_rmmo_model_textures_bound_v1"
const GEOMETRY_ONLY_META:=&"_rmmo_geometry_query_only_v1"

static func table(packed:PackedScene)->String:
	if packed==null:return ""
	var state:=packed.get_state()
	if state.get_node_count()==0:return ""
	for index:int in state.get_node_property_count(0):
		if state.get_node_property_name(0,index)==StringName("metadata/"+str(TABLE_META)):
			return str(state.get_node_property_value(0,index))
	return ""

static func packed_ready(packed:PackedScene)->bool:
	if packed==null:return false
	var required:=table(packed)
	return required.is_empty() or packed.get_meta(READY_META,"")==required

static func scene_ready(scene:Node)->bool:
	if scene==null:return false
	if scene.get_meta(GEOMETRY_ONLY_META,false):return false
	var required:String=scene.get_meta(TABLE_META,"")
	return required.is_empty() or scene.get_meta(READY_META,"")==required

static func inherit_instance(packed:PackedScene,scene:Node)->void:
	# An authored scalar flag is not evidence of a runtime binding operation.
	# The actual root already has the scalar identity; do not rescan SceneState
	# for every placement of an immutable cached template.
	var required:String=scene.get_meta(TABLE_META,"")
	if not required.is_empty() and packed.get_meta(READY_META,"")==required:
		if scene.get_meta(READY_META,"")!=required:scene.set_meta(READY_META,required)
	elif scene.has_meta(READY_META):scene.remove_meta(READY_META)

static func inherit_pack(scene:Node,packed:PackedScene)->bool:
	if not scene_ready(scene) or packed==null:return false
	var required:String=scene.get_meta(TABLE_META,"")
	if table(packed)!=required:return false
	if not required.is_empty():packed.set_meta(READY_META,required)
	return true

static func matches(packed:PackedScene,candidate:Dictionary)->bool:
	if packed==null:return false
	var required:=table(packed)
	return required==str(candidate.get("texture_table",{}).get("sha256","")) and (required.is_empty() or packed.get_meta(READY_META,"")==required)
