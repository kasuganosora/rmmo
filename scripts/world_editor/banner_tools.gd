extends RefCounted
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")

static func apply(editor:Node,ids:Array,changes:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	var error:=Banner.Schema.validate(changes,Banner.schema())
	if not error.is_empty():return {"ok":false,"error":error}
	if ids.is_empty() or ids.size()>256:return {"ok":false,"error":"请选择 1～256 盏路灯"}
	var updates:Dictionary={}
	for id in ids:
		var record:Dictionary=editor._doc._find(str(id))
		if record.is_empty() or not editor._record_editable(record) or record.get("prefab_locked",false):return {"ok":false,"error":"路灯不存在、隐藏、锁定或不在当前楼层"}
		var view:Node=editor._view.get_node_or_null(NodePath(str(id)))
		if view==null or Banner.slot(view)==null:return {"ok":false,"error":"所选模型没有可更换旗帜插槽，请使用新版旗幡路灯预制件"}
		var value:=Banner.settings(record).merged(changes,true)
		if value.shape!="pointed" and value.design=="original":value.design="plain"
		if value.design in ["original","plain"]:value.texture_path=""
		var candidate:=record.duplicate(true);candidate.banner=Banner.store(value)
		if not Paint.valid(candidate):return {"ok":false,"error":"旗帜配置无效；贴图必须在资源根目录内"}
		if value.design in ["flag","emblem"] and Paint.texture(candidate.banner.material)==null:return {"ok":false,"error":"请选择可以读取的 PNG/JPG/WebP 旗帜或透明图案"}
		if candidate.banner!=record.get("banner",{}):updates[id]=candidate.banner
	if updates.is_empty():return {"ok":true,"changed_ids":[]}
	editor._doc.checkpoint()
	for id in updates:editor._doc._find(str(id)).banner=updates[id]
	editor._dirty=true;editor._rebuild()
	return {"ok":true,"changed_ids":updates.keys()}
