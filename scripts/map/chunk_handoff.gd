extends RefCounted
## Owns detached chunks between Loading and World. If a transfer is cancelled,
## releasing the session payload also releases the nodes and joins the worker.
var root: Node2D
var chunks: Dictionary = {}
var worker: RefCounted
var stats: Dictionary = {}
var pending_upload: Dictionary = {}
var texture_pool: RefCounted

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if worker!=null:worker.shutdown()
		if is_instance_valid(root):root.free()

func adopt(field: Node2D) -> void:
	field._clear_chunks()
	if is_instance_valid(field._chunk_root):field._chunk_root.free()
	field._chunk_root=root;root=null
	field.add_child(field._chunk_root)
	field._chunks=chunks;chunks={}
	field._chunk_stream_module_logic.worker=worker;worker=null
	if texture_pool!=null:
		field._chunk_stream_module_logic.texture_pool=texture_pool;texture_pool=null
	field._chunk_stream_module_logic.stream_stats=stats
	field._chunk_stream_module_logic.pending_upload=pending_upload;pending_upload={}
	field._surface_materials.profile=field.pack.render_profile
	field._refresh_chunk_set()
