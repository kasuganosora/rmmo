extends RefCounted
## Runtime residency owns additions. Keep only potential prefab sources here;
## live mesh, pose, material and visibility checks remain in the proxy service.
## Neither this directory nor its exit callbacks own renderer resources.
const META:=&"stream_distant_proxy_sources"
var sources:Dictionary={}
var owner:WeakRef
var admitted:=0
var removed:=0

static func track(map_root:Node,source:MeshInstance3D)->void:
	var directory:RefCounted=map_root.get_meta(META) if map_root.has_meta(META) else null
	if directory==null:
		directory=new();directory.owner=weakref(map_root);map_root.set_meta(META,directory)
		# Adoption can start after pre-existing sources, including generic callers.
		# Bootstrap once; subsequent publication and tree exits are incremental.
		for node:Variant in map_root.get_meta("stream_meshes",{}).values():
			if is_instance_valid(node) and node is MeshInstance3D:directory.add(node)
	directory.add(source)

func add(node:MeshInstance3D)->void:
	var id:=node.get_instance_id()
	if sources.has(id):return
	var record:Dictionary=node.get_meta("ground_batch_record",{})
	if not record.has("building") or record.has("fixture") or not record.has("house_prefab"):return
	sources[id]=node;admitted+=1
	var leaving:=_remove.bind(id);var entering:=_entered.bind(id)
	if not node.tree_exiting.is_connected(leaving):node.tree_exiting.connect(leaving)
	if not node.tree_entered.is_connected(entering):node.tree_entered.connect(entering)

func _entered(id:int)->void:
	# Temporary map detachment is not residency retirement. Reattach the same
	# live source without retaining a renderer resource or an owner Node here.
	var map_root:Node=owner.get_ref() if owner!=null else null
	var node:Node=instance_from_id(id)
	if is_instance_valid(map_root) and node is MeshInstance3D and node.get_parent()==map_root and map_root.get_meta("stream_meshes",{}).get(str(node.name))==node:add(node)

func _remove(id:int)->void:
	if sources.erase(id):removed+=1
