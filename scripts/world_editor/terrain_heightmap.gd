extends RefCounted
## Bounded, lossless-sample heightmap ingestion into editable native heightfields.
const T=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Geometry=preload("res://scripts/world_editor/selection_geometry.gd")
const DIMENSIONS=[17,33,65,129,257,513]
const MAX_BYTES:=4*1024*1024
var editor:Node3D
var candidate:Dictionary={}
static func schema()->Dictionary:
	return City.object({"path":City.text(2048),"format":{"type":"string","enum":["png8","r16le"]},"samples_x":{"type":"integer","minimum":17,"maximum":513},"samples_z":{"type":"integer","minimum":17,"maximum":513},"center":T.S.vector(-100000,100000),"width":T.S.number(2,2048),"depth":T.S.number(2,2048),"height_scale":T.S.number(.01,900),"bedrock_depth":T.S.number(1,100),"name":City.text(64),"flip_z":{"type":"boolean"}},["path","format","center","width","depth","height_scale"])
static func fail(message:String,code:String="heightmap_constraint")->Dictionary:return {"ok":false,"code":code,"error":message}
static func digest(bytes:PackedByteArray)->String:
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
static func big32(bytes:PackedByteArray,offset:int)->int:return (int(bytes[offset])<<24)|(int(bytes[offset+1])<<16)|(int(bytes[offset+2])<<8)|int(bytes[offset+3])
static func decode(args:Dictionary)->Dictionary:
	if not Paths.allowed(args.path) or not FileAccess.file_exists(args.path):return fail("高度图必须是资源根内的现有文件，不能使用链接或外部路径","heightmap_source_invalid")
	var file:=FileAccess.open(args.path,FileAccess.READ)
	if file==null:return fail("高度图无法读取")
	if file.get_length()>MAX_BYTES:return fail("高度图文件超过 4 MiB 输入预算")
	var bytes:=file.get_buffer(file.get_length());file.close()
	var width:int=args.get("samples_x",0);var height:int=args.get("samples_z",0);var values:Array=[];var bits:=16
	if args.format=="png8":
		if bytes.size()<33 or bytes.slice(0,8).hex_encode()!="89504e470d0a1a0a" or bytes.slice(12,16).get_string_from_ascii()!="IHDR":return fail("需要有效的灰度 PNG 文件")
		width=big32(bytes,16);height=big32(bytes,20);bits=int(bytes[24])
		if bits!=8 or bytes[25]!=0:return fail("PNG 首版只接受 8 位单通道灰度；16 位请使用无头小端 R16，避免静默降精度","heightmap_format_unsupported")
		if width not in DIMENSIONS or height not in DIMENSIONS:return fail("图像宽高须为 17、33、65、129、257 或 513 像素")
		if args.get("samples_x",width)!=width or args.get("samples_z",height)!=height:return fail("提供的采样尺寸与 PNG 头不一致")
		var image:=Image.new()
		if image.load_png_from_buffer(bytes)!=OK or image.get_width()!=width or image.get_height()!=height:return fail("PNG 数据损坏或尺寸不一致")
		for z in height:
			for x in width:values.append(roundi(image.get_pixel(x,z).r*255.)/255.)
	else:
		if width not in DIMENSIONS or height not in DIMENSIONS:return fail("R16 必须填写有效的 samples_x 与 samples_z")
		if bytes.size()!=width*height*2:return fail("R16 字节数必须恰好为 samples_x × samples_z × 2，无头、无尾部数据")
		for i in width*height:values.append((int(bytes[i*2])|(int(bytes[i*2+1])<<8))/65535.)
	return {"ok":true,"values":values,"width":width,"height":height,"bits":bits,"source_sha256":digest(bytes),"source_bytes":bytes.size()}

func version()->String:
	return City.token([str(editor._doc.get_instance_id()),editor._doc.authoring_revision,editor._authoring.settings,editor._path])
func preview(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	var error:=T.S.validate(args,schema())
	if not error.is_empty():return fail(error,"invalid_arguments")
	var base:=version();var request_id:=digest(var_to_bytes(args))
	if not candidate.is_empty() and candidate.request_id==request_id and candidate.base_version==base and Paths.allowed(args.path) and FileAccess.get_sha256(args.path)==candidate.summary.source_sha256:return candidate.summary.duplicate(true)
	candidate={};var source:=decode(args)
	if not source.ok:return source
	var columns:int=source.width-1;var rows:int=source.height-1
	var step_x:float=args.width/columns;var step_z:float=args.depth/rows
	if step_x<.25 or step_x>4 or step_z<.25 or step_z>4:return fail("每轴实际格距须为 0.25–4 米；本工具不重采样，请调整米制尺寸")
	if absf(args.center[1])>1000 or args.center[1]+args.height_scale>2000:return fail("垂直基准或最高可能标高超出范围")
	var terrains:Array=[];var ids:Array=[];var prefix:="heightmap_"+Crypto.new().generate_random_bytes(8).hex_encode()
	for z0 in range(0,rows,64):
		for x0 in range(0,columns,64):
			var nx:=mini(64,columns-x0);var nz:=mini(64,rows-z0);var heights:Array=[];var holes:Array=[]
			for z in nz+1:
				var source_z:int=rows-(z0+z) if args.get("flip_z",false) else z0+z
				for x in nx+1:heights.append(float(source.values[source_z*source.width+x0+x])*args.height_scale)
			holes.resize(nx*nz);holes.fill(false)
			var id:=prefix+"_%d_%d"%[x0/64,z0/64]
			var record:Dictionary={"uuid":id,"editor_name":str(args.get("name","导入高度图"))+" %d/%d"%[x0/64,z0/64],"kind":"box","surface_id":"ground","position":[args.center[0]-args.width*.5+(x0+nx*.5)*step_x,args.center[1],args.center[2]-args.depth*.5+(z0+nz*.5)*step_z],"rotation":[0.,0.,0.],"size":[nx*step_x,1.,nz*step_z],"color":[.38,.43,.29],"collision":"walk","terrain_mesh":{"version":1,"columns":nx,"rows":nz,"floor":-float(args.get("bedrock_depth",16.)),"heights":heights,"holes":holes}}
			if not T.valid(record) or not editor._authoring.Settings.contains(record,editor._authoring.settings):return fail("导入结果无效或超出隔离楼层")
			terrains.append(record);ids.append(id)
	if terrains.size()>64 or editor._doc.records.size()+terrains.size()>100000:return fail("导入超过 64 块或地图记录预算")
	# New land uses the native creation overlap rule, including hidden/locked
	# content. Never overwrite old ground, fill bridge openings or move objects.
	var bounds:=Geometry.bounds(terrains)
	for old:Dictionary in editor._doc.records:
		if not bounds.intersects(Geometry.bounds([old])):continue
		var occupied:=Foot.record_shapes(old)
		for terrain:Dictionary in terrains:
			if Foot.batches_overlap([Foot.record_shape(terrain)],occupied):return fail("新地形与既有内容重叠；请选择空白区域，不会覆盖原图","heightmap_overlap").merged({"conflicts":[old.uuid]})
	var stage:=Doc.new();stage.apply_recovery(editor._doc.recovery_snapshot());stage.records.append_array(terrains)
	if stage.validate_save()!=OK:return fail("导入候选未通过完整原生保存校验")
	if version()!=base or not Paths.allowed(args.path) or FileAccess.get_sha256(args.path)!=source.source_sha256:return fail("地图或源文件在准备期间已变化，请重新预览","source_changed")
	var summary:Dictionary={"ok":true,"plan_token":Crypto.new().generate_random_bytes(24).hex_encode(),"base_version":base,"source_sha256":source.source_sha256,"source_bytes":source.source_bytes,"format":args.format,"bit_depth":source.bits,"samples":[source.width,source.height],"cell_size":[step_x,step_z],"tile_count":terrains.size(),"cell_count":columns*rows,"terrain_ids":ids,"height_range":[args.center[1]+float(source.values.min())*args.height_scale,args.center[1]+float(source.values.max())*args.height_scale],"quantization_step":args.height_scale/(255. if source.bits==8 else 65535.),"orientation":"rows increase toward +Z" if not args.get("flip_z",false) else "rows increase toward -Z","bounds":{"position":City.xyz(bounds.position),"size":City.xyz(bounds.size)},"precision":"source samples retained without resampling or gamma conversion; native render/collision vertices use float32","publication":"single authoring transaction; native terrain refresh and shared derived batching"}
	candidate={"request_id":request_id,"base_version":base,"path":args.path,"summary":summary,"records":terrains,"after":stage.recovery_snapshot()}
	candidate.integrity=digest(var_to_bytes(candidate.after))
	return summary.duplicate(true)
func visual(token:String)->Array:return candidate.records.duplicate(true) if not candidate.is_empty() and candidate.summary.plan_token==token else []
func discard(token:String)->Dictionary:
	if not candidate.is_empty() and candidate.summary.plan_token==token:candidate={}
	return {"ok":true}
func apply(args:Dictionary)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if args.size()!=1 or not args.get("plan_token") is String:return fail("应用只接受 plan_token","invalid_arguments")
	if candidate.is_empty() or candidate.summary.plan_token!=args.plan_token:return fail("候选不存在，请重新预览","candidate_missing")
	if version()!=candidate.base_version:candidate={};return fail("地图已变化，请重新预览","base_changed")
	if not Paths.allowed(candidate.path) or not FileAccess.file_exists(candidate.path) or FileAccess.get_sha256(candidate.path)!=candidate.summary.source_sha256:candidate={};return fail("高度图源文件已变化，请重新预览","source_changed")
	var stage:=Doc.new();stage.apply_recovery(candidate.after)
	if digest(var_to_bytes(candidate.after))!=candidate.integrity or stage.validate_save()!=OK:candidate={};return fail("候选发布前校验失败","candidate_invalid")
	var before:Dictionary=editor._doc.recovery_snapshot();var result:Dictionary=candidate.summary.duplicate(true)
	editor._doc.apply_recovery(candidate.after);editor._doc.commit_recovery_change(before);candidate={}
	editor._commit_records(result.terrain_ids);editor._selection_tools.set_ids(result.terrain_ids);result.changed=true
	return result
