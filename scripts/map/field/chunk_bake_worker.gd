extends RefCounted
## One isolated, detached painter. Only immutable sheet Images and copied map
## buffers cross threads. SceneTree nodes and GPU uploads stay on the main thread.
var painter: Node2D
var task_id: int = -1
var coordinate: Vector2i
var result: Dictionary = {}
var source_pack: RefCounted

func start(owner: Node2D, c: Vector2i) -> void:
	assert(task_id == -1)
	if painter == null:
		painter=owner.get_script().new()
		painter.skip_ready_rebuild=true
	if source_pack != owner.pack:
		source_pack=owner.pack
		painter.pack=owner.pack.get_script().new()
		for key in ["sheets","flags","render_profile","pack_dir","ext"]:
			painter.pack.set(key,owner.pack.get(key))
	# Streaming collision dictionaries can be evicted by the next camera move.
	# Packed arrays use copy-on-write; a shallow dictionary copy pins our snapshot.
	var col=owner.collision.get_script().new()
	for key in ["width","height","data","flags","void_tile_id","ext","streaming","chunk_cells"]:
		col.set(key,owner.collision.get(key))
	col._stream_chunks=owner.collision._stream_chunks.duplicate()
	painter.collision=col
	painter.tile_size=owner.tile_size
	painter.grid_width=owner.grid_width
	painter.grid_height=owner.grid_height
	painter._cached_void_id=owner._cached_void_id
	# Table loading and source format conversion must complete before sharing.
	owner.TileBlit.ensure_tables()
	coordinate=c
	result={}
	task_id=WorkerThreadPool.add_task(_bake,false,"Map chunk %s"%c)

func _bake() -> void:
	var started=Time.get_ticks_usec()
	var x0=coordinate.x*16;var y0=coordinate.y*16
	var cw=mini(16,painter.grid_width-x0);var ch=mini(16,painter.grid_height-y0)
	var ts: int=painter.tile_size
	var images={}
	for bucket in ["Below","Ground","Upper","Roof","Fx"]:
		var img=Image.create(cw*ts,ch*ts,false,Image.FORMAT_RGBA8)
		img.fill(Color(0,0,0,0));images[bucket]=img
	painter._begin_anim_bake()
	for y in range(ch):
		for x in range(cw):
			painter._paint_cell(images.Ground,images.Upper,painter.collision,painter.pack.sheets,painter.pack.flags,painter._cached_void_id,x0+x,y0+y,x*ts,y*ts)
			painter._paint_ext_cell(images.Below,images.Ground,images.Upper,images.Roof,images.Fx,painter.collision,painter.pack.sheets,painter.pack.flags,x0+x,y0+y,x*ts,y*ts)
	var painted=Time.get_ticks_usec()
	var material_images=painter._surface_materials.bake_images(x0,y0,cw,ch)
	# The shader multiplies emission RGB by alpha. An entirely transparent
	# channel is exactly a constant zero, not a 768x768 GPU allocation.
	if not material_images.is_empty():
		for bucket in material_images.emissions:
			if material_images.emissions[bucket].is_invisible():
				var empty_glow=Image.create(1,1,false,Image.FORMAT_RGBA8)
				empty_glow.fill(Color(0,0,0,0))
				material_images.emissions[bucket]=empty_glow
	# Scan transparency off-thread too (Image.get_used_rect visits every pixel).
	var empty=[]
	for key in images:
		if images[key].get_used_rect().size == Vector2i.ZERO:empty.append(key)
	for key in empty:images.erase(key)
	result={"images":images,"materials":material_images,"jobs":painter._bake_anim_jobs,
		"shadows":painter._bake_anim_shadows,"anim_images":painter._bake_anim_imgs,
		"cw":cw,"ch":ch,"paint_ms":(painted-started)/1000.0,"worker_ms":(Time.get_ticks_usec()-started)/1000.0}
	painter._bake_anim=false

func ready() -> bool:
	return task_id>=0 and WorkerThreadPool.is_task_completed(task_id)

func take() -> Dictionary:
	assert(ready())
	WorkerThreadPool.wait_for_task_completion(task_id)
	task_id=-1
	var out=result;result={}
	return out

func shutdown() -> void:
	if task_id>=0:WorkerThreadPool.wait_for_task_completion(task_id)
	task_id=-1;result={}
	if painter!=null:painter.free();painter=null
	source_pack=null
