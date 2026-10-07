extends RefCounted
## Explicit per-opening design changes. Existing holes, fixed surrounds and hinges stay put.
const H=preload("res://scripts/world3d/house_prefab.gd")
const F=preload("res://scripts/world3d/building_fixtures.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const STYLES=["casement","cross_lattice","diamond_lattice"]

static func list_windows(editor:Node,building:String)->Dictionary:
	if not editor._buildings.instances().has(building):return {"ok":false,"error":"建筑不存在"}
	var groups:Dictionary={}
	for record in editor._doc.records:
		if record.get("building",{}).get("id")!=building or record.get("fixture",{}).get("kind")!="window":continue
		var id:String=str(record.fixture.id).get_slice("/casement",0)
		if not groups.has(id):groups[id]={"id":id,"members":[],"style":record.get("window_design","original"),"floor":record.building.floor}
		groups[id].members.append(record.uuid)
	return {"ok":true,"building_id":building,"windows":groups.values(),"styles":STYLES,"scope":"one complete opening; retains fixed surround, opening dimensions and all hinge states"}

static func add_box(builders:Array,slot:int,position:Vector3,size:Vector3,basis:Basis=Basis.IDENTITY)->void:
	var box:=BoxMesh.new();box.size=size
	builders[slot].append_from(Cpu.capture(box),0,Transform3D(basis,position))

static func prepare(record:Dictionary,style:String)->Dictionary:
	if not record.has("house_prefab") or record.has("surface_paint"):return {"ok":false,"error":"此窗扇不是标准烘焙窗，或窗扇已单面刷材质；请先恢复窗扇面材质，墙面不受影响"}
	var geometry:=H.geometry(record)
	if geometry.is_empty():return {"ok":false,"error":"窗扇数据无效"}
	var wood:StandardMaterial3D;var glass:StandardMaterial3D;var iron:StandardMaterial3D
	for material in geometry.mesh.materials:
		if not material is StandardMaterial3D:continue
		var c:Color=material.albedo_color
		if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or (c.b>c.r*1.1 and c.b>c.g):glass=material
		elif material.has_meta("runtime_paint_definition") or c.r>c.b*1.2:wood=material
		elif iron==null:iron=material
	if wood==null or glass==null:return {"ok":false,"error":"此窗材质无法可靠识别，保留原窗"}
	if iron==null:iron=StandardMaterial3D.new();iron.albedo_color=Color(.12,.13,.14);iron.metallic=.6
	var bounds:AABB=geometry.mesh.get_aabb();var axis_x:bool=bounds.size.x>=bounds.size.z
	var w:float=bounds.size.x if axis_x else bounds.size.z;var h:float=bounds.size.y
	if w<.15 or h<.3:return {"ok":false,"error":"窗扇尺寸过小"}
	var basis:=Basis.IDENTITY if axis_x else Basis(Vector3.UP,PI/2)
	var center:=bounds.get_center();var builders:Array=[SurfaceTool.new(),SurfaceTool.new(),SurfaceTool.new()]
	var frame:float=minf(.05,w*.12);var depth:float=minf(.065,minf(bounds.size.x,bounds.size.z))
	for side in [-1,1]:
		add_box(builders,0,center+basis*Vector3(side*(w-frame)/2,0,0),Vector3(frame,h,depth),basis)
		add_box(builders,0,center+basis*Vector3(0,side*(h-frame)/2,0),Vector3(w-frame*2,frame,depth),basis)
	add_box(builders,1,center,Vector3(w-frame*2,h-frame*2,.025),basis)
	add_box(builders,0,center,Vector3(w-frame*2,.035,depth*.75),basis)
	if style=="casement":
		for side in [-1,1]:add_box(builders,0,center+Vector3(0,side*h/6,0),Vector3(w-frame*2,.025,depth*.6),basis)
	else:
		var half_w:float=(w-frame*2)/2
		for row in 2:
			var low:float=-h/2+frame+row*(h-frame*2)/2;var high:float=low+(h-frame*2)/2
			var edges:Array=[]
			if style=="cross_lattice":edges=[[Vector2(-half_w,low),Vector2(half_w,high)],[Vector2(half_w,low),Vector2(-half_w,high)]]
			else:
				var points:Array=[Vector2(0,low),Vector2(half_w,(low+high)/2),Vector2(0,high),Vector2(-half_w,(low+high)/2)]
				for j in 4:edges.append([points[j],points[(j+1)%4]])
			for edge in edges:
				var a:Vector3=basis*Vector3(edge[0].x,edge[0].y,0);var b:Vector3=basis*Vector3(edge[1].x,edge[1].y,0)
				add_box(builders,0,center+(a+b)/2,Vector3(.028,a.distance_to(b),.032),Basis(Quaternion(Vector3.UP,(b-a).normalized())))
	# Reuse authored hinges/handles rather than replacing functional hardware.
	var hardware_found:=false
	for slot in geometry.mesh.get_surface_count():
		if geometry.mesh.materials[slot]==iron:
			builders[2].append_from(geometry.mesh,slot,Transform3D.IDENTITY);hardware_found=true
	if not hardware_found:
		var pivot:Vector3=F.vec(record.fixture.pivot)
		for side in [-1,1]:add_box(builders,2,Vector3(pivot.x,center.y+side*(h/2-.07),pivot.z),Vector3(.032,.065,.032))
	var mesh:=Cpu.new();mesh.bounds=bounds
	for i in 3:
		builders[i].index();mesh.surfaces.append(builders[i].commit_to_arrays());mesh.materials.append([wood,glass,iron][i])
	var cache:Dictionary={};cache[[0]]={"mesh":mesh,"source":geometry.source}
	var data:=H.Cook.pack(cache,"","window_design_v1")
	if data.entries.size()!=1:return {"ok":false,"error":"窗材质无法打包"}
	var bytes:=var_to_bytes(data);var next:=record.duplicate(true)
	next.house_prefab={"version":1,"sha256":H.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	next.prefab_materials=[]
	for mat:Dictionary in data.materials:
		if mat.has("paint") and not next.prefab_materials.has(mat.paint):next.prefab_materials.append(mat.paint)
	next.window_design=style
	return {"ok":H.valid(next),"record":next,"error":"新窗验证失败"}

static func replace(editor:Node,building:String,window:String,style:String)->Dictionary:
	var ready:Dictionary=editor._gameplay.guard()
	if not ready.ok:return ready
	if style not in STYLES:return {"ok":false,"error":"不支持的窗扇样式"}
	var found:=list_windows(editor,building)
	if not found.ok:return found
	var matches:Array=found.windows.filter(func(row):return row.id==window)
	if matches.size()!=1:return {"ok":false,"error":"窗户不存在"}
	var replacements:Array=[];var ids:Array[String]=[]
	for id in matches[0].members:
		var old:Dictionary=editor._doc._find(id)
		if not editor._record_editable(old):return {"ok":false,"error":"窗户被锁定、隐藏或在当前楼层外"}
		if old.get("window_design","")==style:continue
		var prepared:=prepare(old,style)
		if not prepared.ok:return prepared
		replacements.append(prepared.record);ids.append(id)
	if ids.is_empty():return {"ok":true,"changed":false}
	editor._doc.checkpoint_recovery()
	for next in replacements:
		var old:Dictionary=editor._doc._find(next.uuid);old.clear();old.merge(next)
	editor._dirty=true;editor._refresh_records(ids)
	editor._selection_tools.invalidate_pivot();editor._selection_tools.refresh()
	return {"ok":true,"changed":true,"building_id":building,"window_id":window,"style":style,"affected_ids":ids}
