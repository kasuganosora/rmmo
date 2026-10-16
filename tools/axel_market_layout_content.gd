extends RefCounted
## Layout-only content, with native terrain/road transactions owned by the caller.
## prepare -> apply_terrain_layout -> road_request/update_road_graph -> apply_content.
## The caller must refresh city bounds, validate final roads, undo/save/reopen, and
## review the changed outdoor views before publication. No source asset is altered.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Props=preload("res://tools/axel_house_reference_props.gd")
const Support=preload("res://tools/axel_house_placement_support.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const PLAN=OUT+"/market_functional_layout_plan.json"
const TEMPLATE_INDEX="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/house_templates.json"
static func read(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
static func oriented(loaded:Dictionary,yaw:float)->Dictionary:
	var copy:=loaded.duplicate(true);var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
	for r:Dictionary in copy.records:
		r.position=B.arr(basis*B.vec(r.position));r.rotation=B.arr((basis*Basis.from_euler(B.vec(r.rotation)*PI/180)).get_euler()*180/PI)
	for value:Dictionary in copy.building_instances.values():value.position=[0,0,0];value.yaw=yaw
	return copy
static func bearing_core(doc,rect:Rect2)->Dictionary:
	var core:=Rect2();var found:=false;var seed:="";var cells:=0
	for record:Dictionary in doc.records:
		if not record.has("terrain_mesh"):continue
		var pose:=Terrain.transform(record);var bounds:AABB=pose*Terrain.bounds(record)
		if not rect.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z)):continue
		if absf(float(record.rotation[0]))+absf(float(record.rotation[1]))+absf(float(record.rotation[2]))>.0001:return City.fail("Foundation requires the current axis-aligned terrain grid")
		for z in int(record.terrain_mesh.rows):
			for x in int(record.terrain_mesh.columns):
				var points:Array=Terrain.cell(record,x,z).map(func(p):return pose*p)
				var cell:=Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
				for point:Vector3 in points:cell=cell.expand(Vector2(point.x,point.z))
				if not rect.intersects(cell):continue
				if not Terrain.solid(record.terrain_mesh,x,z):return City.fail("Foundation overlaps an open terrain cell")
				core=core.merge(cell) if found else cell;found=true;cells+=1
		var at:=rect.get_center();var local:=pose.affine_inverse()*Vector3(at.x,0,at.y)
		if is_finite(Terrain.sample(record,local)):seed=record.uuid
	return {"ok":found and not seed.is_empty(),"rect":core,"seed":seed,"cells":cells}
static func stamp(core:Dictionary,height:float,margin:float)->Dictionary:
	var rect:Rect2=core.rect;var center:=rect.get_center()
	return {"id":core.seed,"mode":"flatten","shape":"rectangle","points":[[center.x,center.y]],"plot_width":rect.size.x,"plot_depth":rect.size.y,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":height,"blend_margin":margin,"strength":1.,"cross_tiles":true}
static func prepare(doc)->Dictionary:
	if doc.map_meta.get("town_reference",{}).has("market_functional_layout"):return City.fail("Market layout already exists; do not add duplicate content")
	var plan:=read(PLAN);var templates:Dictionary={};var houses:Array=[];var stalls:Array=[];var strokes:Array=[];var inputs:Dictionary={PLAN:FileAccess.get_sha256(PLAN),TEMPLATE_INDEX:FileAccess.get_sha256(TEMPLATE_INDEX)}
	for template:Dictionary in read(TEMPLATE_INDEX).templates:templates[template.id]=template
	for house:Dictionary in plan.houses:
		var row:=house.duplicate(true);var template:Dictionary=templates.get(row.template_id,{})
		if template.is_empty() or FileAccess.get_sha256(template.loaded_path)!=row.template_sha256:return City.fail("Reviewed template changed: "+row.id)
		inputs[template.loaded_path]=row.template_sha256;row.template=template
		var p:Dictionary=template.parameters;var origin:=Vector3(row.position_xz[0],0,row.position_xz[1]);var basis:=Basis(Vector3.UP,deg_to_rad(row.yaw))
		var entrance:=origin+basis*B.vec(template.entrance);row.entrance_xz=[entrance.x,entrance.z]
		var access_tip:=entrance+basis*Vector3.FORWARD*1.45;row.access_tip_xz=[access_tip.x,access_tip.z]
		var threshold:=origin+basis*B.vec(template.door_threshold);row.threshold_xz=[threshold.x,threshold.z]
		var reference:=entrance
		if row.has("ground_height_reference_xz"):reference=Vector3(row.ground_height_reference_xz[0],0,row.ground_height_reference_xz[1])
		var ground:float=Props.ground(doc,reference)
		if row.has("target_ground_override"):ground=float(row.target_ground_override)
		if not is_finite(ground):return City.fail("Missing entrance terrain "+row.id)
		row.target_ground=ground
		var points:PackedVector2Array=[]
		for x in [-float(p.width)/2,float(p.width)/2]:
			for z in [-float(p.depth)/2,float(p.depth)/2]:
				var point:=origin+basis*Vector3(x,0,z);points.append(Vector2(point.x,point.z))
		var rect:=Rect2(points[0],Vector2.ZERO)
		for point:Vector2 in points:rect=rect.expand(point)
		# Full foundation cells, with a smooth falloff outside the footprint.
		var core:=bearing_core(doc,rect.grow(.20))
		if not core.ok:return core
		row.foundation_rect=[rect.position.x,rect.position.y,rect.size.x,rect.size.y]
		row.terrain_core=[core.rect.position.x,core.rect.position.y,core.rect.size.x,core.rect.size.y]
		strokes.append(stamp(core,ground,4.));houses.append(row)
		if row.has("entry_apron"):
			var a:Array=row.entry_apron;var apron:=bearing_core(doc,Rect2(a[0],a[1],a[2],a[3]))
			if not apron.ok:return apron
			strokes.append(stamp(apron,ground,1.5))
	var catalog:=Props.catalog()
	for stall:Dictionary in plan.stalls:
		var row:=stall.duplicate(true);row.entry=Props.entry(catalog,row.label)
		if row.entry.is_empty():return City.fail("Missing complete market asset "+row.label)
		var loaded:=Library.read(row.entry)
		if not loaded.ok or loaded.records.size()!=1:return City.fail("Unexpected market source structure "+row.label)
		var source:String=loaded.records[0].asset_path
		if FileAccess.get_sha256(source)!=row.asset_sha256:return City.fail("Market asset changed "+row.label)
		inputs[source]=row.asset_sha256;inputs[row.entry.prefab_path]=FileAccess.get_sha256(row.entry.prefab_path)
		row.target_ground=Props.ground(doc,Vector3(row.position_xz[0],0,row.position_xz[1]))
		var core:=bearing_core(doc,Rect2(row.position_xz[0]-1.6,row.position_xz[1]-.97,3.2,1.94))
		if not core.ok or not is_finite(row.target_ground):return City.fail("Stall has no complete ground support "+row.id)
		strokes.append(stamp(core,row.target_ground,2.));stalls.append(row)
	var terrain_request:={"strokes":strokes};var road_nodes:Array=[]
	for house:Dictionary in houses:
		if not house.has("existing_door_node"):continue
		road_nodes.append({"id":house.existing_door_node,"position":[house.access_tip_xz[0],house.target_ground,house.access_tip_xz[1]]})
		var at:=Vector3(house.access_from_xz[0],0,house.access_from_xz[1]);at.y=Props.ground(doc,at)
		road_nodes.append({"id":house.existing_lane_node,"position":B.arr(at)})
	if not road_nodes.is_empty():
		terrain_request.road_nodes=road_nodes;terrain_request.expected_road_token=City.token(City.resolve(doc.map_meta).roads)
	return {"ok":true,"houses":houses,"stalls":stalls,"terrain_request":terrain_request,"inputs":inputs,"plan":plan,"visual":"pending outdoor layout review","source_assets_unchanged":true}
static func road_request(doc,prepared:Dictionary)->Dictionary:
	var graph:Dictionary=City.resolve(doc.map_meta).roads;var nodes:Array=[];var edges:Array=[]
	var node_index:Dictionary={};var cuts:Dictionary={}
	for node:Dictionary in graph.nodes:node_index[node.id]=node
	for house:Dictionary in prepared.houses:
		var entrance:=Vector3(house.access_tip_xz[0],0,house.access_tip_xz[1]);var at:=Vector3(195,0,entrance.z)
		if house.has("access_from_xz"):at=Vector3(house.access_from_xz[0],0,house.access_from_xz[1])
		if house.has("existing_door_node"):
			# The northern lane already has four connected native entry spurs.
			# Reuse their endpoint identities; the smaller fourth cottage needs
			# its spur extended toward its real door, not a duplicate road.
			for pair:Array in [[house.existing_door_node,entrance],[house.existing_lane_node,at]]:
				var matches:Array=graph.nodes.filter(func(n):return n.id==pair[0])
				if matches.size()!=1:return City.fail("Missing existing residential entry node "+str(pair[0]))
				var node:Dictionary=matches[0].duplicate(true);var target:Vector3=pair[1]
				target.y=Props.ground(doc,target);node.position=B.arr(target);nodes.append(node)
			continue
		if not house.get("new_access",false):continue
		var main_id:String="market_access_main_"+house.id;var end_id:String="market_access_door_"+house.id
		var existing:Array=graph.nodes.filter(func(n):return Vector2(n.position[0]-at.x,n.position[2]-at.z).length()<.001)
		if existing.size()>1:return City.fail("Ambiguous coincident commercial junction: "+house.id)
		if existing.size()==1:main_id=existing[0].id
		else:
			var matches:Array=[]
			for edge:Dictionary in graph.edges:
				if edge.kind!="ground" or edge.has("controls") or edge.has("bridge_ref") or edge.has("stone_bridge"):continue
				var a:Vector3=City.vec(node_index[edge.from].position);var b:Vector3=City.vec(node_index[edge.to].position)
				var delta:=Vector2(b.x-a.x,b.z-a.z)
				if delta.length_squared()<1e-8:continue
				var t:=Vector2(at.x-a.x,at.z-a.z).dot(delta)/delta.length_squared()
				if t<=.00001 or t>=.99999 or Vector2(a.x,a.z).lerp(Vector2(b.x,b.z),t).distance_to(Vector2(at.x,at.z))>.001:continue
				matches.append({"edge":edge,"t":t})
			if matches.size()!=1:return City.fail("Commercial entry must join one existing straight ground edge: "+house.id)
			var match_:Dictionary=matches[0];var source:Dictionary=match_.edge
			if not cuts.has(source.id):cuts[source.id]={"source":source,"points":[{"t":0.,"id":source.from},{"t":1.,"id":source.to}]}
			cuts[source.id].points.append({"t":match_.t,"id":main_id})
		at.y=Props.ground(doc,at);entrance.y=Props.ground(doc,entrance)
		if existing.is_empty():nodes.append({"id":main_id,"position":B.arr(at)})
		nodes.append({"id":end_id,"position":B.arr(entrance)})
		edges.append({"id":"market_access_edge_"+house.id,"name":house.label+"入户小路","from":main_id,"to":end_id,"kind":"ground","width_start":1.8,"width_end":1.8})
	# Keep original outer endpoint IDs and the first edge ID. Copy every source
	# property; only subdivision endpoints and interpolated widths may differ.
	for split:Dictionary in cuts.values():
		var source:Dictionary=split.source;var points:Array=split.points;points.sort_custom(func(a,b):return a.t<b.t)
		for i in points.size()-1:
			var edge:Dictionary=source.duplicate(true);edge.from=points[i].id;edge.to=points[i+1].id
			if i>0:edge.id="market_split_"+source.id+"_"+str(i)
			edge.width_start=lerpf(source.width_start,source.width_end,points[i].t);edge.width_end=lerpf(source.width_start,source.width_end,points[i+1].t)
			edges.append(edge)
	return {"expected_token":City.token(graph),"nodes":nodes,"edges":edges}
static func direct_source(entry:Dictionary)->Dictionary:
	var loaded:=Library.read(entry)
	if not loaded.get("ok",false) or loaded.records.size()!=1:return {}
	var row:Dictionary=loaded.records[0].duplicate(true)
	for key:String in ["position","rotation","size","uuid","kind","surface_id"]:row.erase(key)
	return row
static func apply_content(doc,prepared:Dictionary)->Dictionary:
	if not prepared.get("ok",false):return prepared
	for path:String in prepared.inputs:
		if FileAccess.get_sha256(path)!=prepared.inputs[path]:return City.fail("Input changed before content placement: "+path)
	var houses:Array=[];var requests:Array=[];var entries:=Props.catalog();var lamp:=Props.entry(entries,"门旁暖光小壁灯")
	for h:Dictionary in prepared.houses:
		var template:Dictionary=h.template;var loaded:=read(template.loaded_path);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
		var support:=Support.sample(doc,loaded.records,Vector3(h.position_xz[0],-1000,h.position_xz[1]),basis,template.parameters)
		if not support.ok or support.highest-support.lowest>.01:return City.fail("Foundation was not made level through native terrain layout: "+h.id)
		var pos:Vector3=support.position;var threshold:=pos+basis*B.vec(template.door_threshold)
		var rise:=threshold.y-Props.ground(doc,threshold)
		if rise<-.02 or rise>.18:return City.fail("Door threshold has excessive height: "+h.id+" "+str(rise))
		var result:=Library.place_buildings(doc,oriented(loaded,h.yaw),pos,h.label)
		if not result.ok:return {"ok":false,"error":"Native complete prefab refused "+h.id,"detail":result}
		var native_id:String=doc._find(result.ids[0]).building.id;var parameters:Dictionary=doc.map_meta.building_instances[native_id].parameters
		if City.token(parameters)!=City.token(template.parameters):return City.fail("Native house parameters changed during placement")
		var row:={"id":h.id,"label":h.label,"use":h.use,"template_id":h.template_id,"template_sha256":h.template_sha256,"building_id":native_id,"position":B.arr(pos),"yaw":h.yaw,"component_ids":result.ids,"entrance":B.arr(pos+basis*B.vec(template.entrance)),"door_threshold":B.arr(threshold),"threshold_above_ground":rise,"parameters":parameters,"store_trading_implemented":false}
		var tip:=Vector3(h.access_tip_xz[0],0,h.access_tip_xz[1]);tip.y=Props.ground(doc,tip);row.access_tip=B.arr(tip);row.shot="MARKET_"+str(h.id)
		houses.append(row)
		var p:Dictionary=parameters;var door_x:float=-float(p.width)/2+1.2
		requests.append(Props.request("market/"+h.id+"/door_lamp",lamp,pos+basis*Vector3(door_x+1.25,float(p.base_height)+1.95,-float(p.depth)/2-.191447),float(h.yaw)+180,Vector3.ONE,false))
		if h.has("sign_label"):
			# Source GLBs use their shared sign-centre origin; prefab pivots differ.
			# The bracket's -X wall plate is seated at the west-facing wall.
			var board:=direct_source(Props.entry(entries,h.sign_label));var frame:=direct_source(Props.entry(entries,"写实木挂架·中斜撑木挂架"))
			if board.is_empty() or frame.is_empty():return City.fail("Missing reviewed independent sign or bracket")
			var source_origin:=Vector3(pos.x-float(p.depth)/2-1.02,pos.y+float(p.base_height)+2.5,threshold.z-2.4)
			requests.append(Props.request("market/"+h.id+"/sign",board,source_origin,180,Vector3.ONE,false))
			requests.append(Props.request("market/"+h.id+"/bracket",frame,source_origin,180,Vector3.ONE,false))
	for row:Dictionary in prepared.stalls:
		var at:=Vector3(row.position_xz[0],row.target_ground,row.position_xz[1])
		requests.append(Props.request("market/stall/"+row.id,row.entry,at,row.yaw,Vector3.ONE,true))
	var placed:=Props.apply_requests(doc,{"ok":true,"requests":requests})
	if not placed.ok:return placed
	var metadata:={"project_supplementary_design":true,"stage":"outdoor_layout_pending_review","plan_sha256":FileAccess.get_sha256(PLAN),"houses":houses,"props":placed.placements,"market_central_clear_axis":[162,77,6,30],"guild_player_stalls":"untouched and empty","store_trading_implemented":false,"asset_sources_modified":false,"cameras":prepared.plan.cameras}
	doc.map_meta.town_reference.market_functional_layout=metadata
	return {"ok":true,"houses":houses,"props":placed.placements,"metadata":metadata,"resource_review":"unchanged reviewed sources; current outdoor placement pending","indoor_tests":"not repeated per user"}
