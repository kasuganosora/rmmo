extends RefCounted
## Scene authoring helper only. Caller owns candidate validation/save/reopen.
const Library=preload("res://scripts/world_editor/prefab_library.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const ASSETS="D:/code/rmmo_runtime/packs/default/assets"
static func catalog()->Array:
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string(ASSETS+"/library.json"))
	for r:Dictionary in rows:
		for field in ["prefab_path","asset_path","thumbnail_path"]:
			if r.has(field):r[field]=ASSETS.path_join(r[field])
	return rows
static func entry(rows:Array,label:String)->Dictionary:
	var matches:Array=rows.filter(func(r):return r.get("label")==label)
	# Prefer native standalone imports; prefab fallback preserves existing metadata.
	for r:Dictionary in matches:
		if r.has("asset_path"):return r
	return {} if matches.is_empty() else matches[0]
static func ground(doc,point:Vector3)->float:
	for r:Dictionary in doc.records:
		if not r.has("terrain_mesh") or r.get("surface_id")=="water":continue
		var pose:=Terrain.transform(r);var local:=pose.affine_inverse()*point;var y:=Terrain.sample(r,local)
		if is_finite(y):return (pose*Vector3(local.x,y,local.z)).y
	return NAN
static func actual_house(doc,h:Dictionary,final_houses:Dictionary)->Dictionary:
	var actual:Dictionary=final_houses.get(h.id,{})
	var registry:Dictionary=doc.map_meta.get("building_instances",{})
	var native_id:String=actual.get("building_id",actual.get("native_id",""))
	if registry.has(native_id):return registry[native_id]
	if actual.has("parameters") and actual.get("position",[]).size()==3:return actual
	return {}
static func request(key:String,asset:Dictionary,point:Vector3,yaw:float,scale_:Vector3=Vector3.ONE,grounded:bool=true)->Dictionary:
	return {"key":key,"entry":asset,"position":B.arr(point),"yaw":yaw,"scale":B.arr(scale_),"grounded":grounded}
static func build_requests(doc,plans:Array,final_houses:Dictionary)->Dictionary:
	var entries:=catalog();var requests:Array=[];var errors:Array=[];var used:Dictionary={}
	var lamp:=entry(entries,"门旁暖光小壁灯")
	var wall:=entry(entries,"写实石围墙·1.5米高·2.4米直墙")
	var pier:=entry(entries,"写实石立柱·1.95米")
	var oak:=entry(entries,"写实阔叶橡树·宽冠粗干")
	var laundry:=entry(entries,"晾衣绳架")
	var fruit:=entry(entries,"S10 写实红果阔叶树")
	var planter:=entry(entries,"暖砖长花池")
	var natural_post:=entry(entries,"原木金丝带彩柱")
	var blue_post:=entry(entries,"蓝色金丝带彩柱")
	var green_post:=entry(entries,"绿色金丝带彩柱")
	var bunting:=entry(entries,"桥头九面长旗")
	var arch:=entry(entries,"S12 外挑双柱大拱门")
	var relief:=entry(entries,"S12 山墙高窄雕饰板")
	for pair:Array in [["lamp",lamp],["wall",wall],["pier",pier],["oak",oak],["fruit",fruit],["planter",planter]]:
		if pair[1].is_empty():errors.append("Missing formal asset: "+pair[0])
	if not errors.is_empty():return {"ok":false,"errors":errors}
	for plan:Dictionary in plans:
		for h:Dictionary in plan.get("houses",[]):
			if used.has(h.id):continue
			used[h.id]=true
			var actual:=actual_house(doc,h,final_houses)
			if actual.is_empty():errors.append("Final house position/registry missing: "+str(h.id));continue
			var p:Dictionary=actual.parameters;var origin:=B.vec(actual.position);var yaw:float=actual.yaw;var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
			# Lamp source faces +Z; house faces -Z. Source was recentered to bottom.
			# Backplate at local z_min, so a half-depth outward offset seats it on wall.
			var door_x:float=-float(p.width)/2+1.2
			var lamp_at:=origin+basis*Vector3(door_x+1.25,float(p.get("base_height",.3))+1.95,-float(p.depth)/2-.191447)
			if p.get("entrance_style","rectangular")!="round_arch_hall":requests.append(request(str(h.id)+"/door_lamp",lamp,lamp_at,yaw+180,Vector3.ONE,false))
			else:
				var arch_x:float=preload("res://scripts/world3d/house_arched_entrance.gd").center(p)
				requests.append(request(str(h.id)+"/projecting_arch",arch,origin+basis*Vector3(arch_x,float(p.get("base_height",0)),-float(p.depth)/2),yaw+180,Vector3.ONE,false))
				requests.append(request(str(h.id)+"/gable_relief",relief,origin+basis*Vector3(0,5.35,-float(p.depth)/2),yaw+180,Vector3.ONE,false))
			if h.get("shot")=="S10" and int(p.floors)==1:
				var fruit_at:=origin+basis*Vector3(-7.75,0,-12.5)
				var fruit_xz:Array=plan.get("props",{}).get("s10_tree",{}).get("position_xz",[])
				if fruit_xz.size()==2:fruit_at=Vector3(float(fruit_xz[0]),0,float(fruit_xz[1]))
				requests.append(request(str(h.id)+"/redfruit",fruit,fruit_at,yaw))
				# Two separate warm brick planters, keeping the actual left-offset door clear.
				for side:Array in [[-7.55,3.2],[.75,4.2]]:
					requests.append(request(str(h.id)+"/planter_"+str(side[0]),planter,origin+basis*Vector3(side[0],0,-7.3),yaw,Vector3(float(side[1])/3.620182,1,.8/1.235942)))
		for pole:Dictionary in plan.get("pole_reserves",[]):
			var xz:Array=pole.position
			var post:Dictionary=blue_post if str(pole.id) in ["bridge_left_blue","lane_near_north","lane_far_north"] else natural_post
			if str(pole.id)=="lane_near_south" and not green_post.is_empty():post=green_post
			if post.is_empty():errors.append("Missing festival pole material variant")
			else:requests.append(request("festival/"+str(pole.id),post,Vector3(xz[0],0,xz[1]),0,Vector3(1.2,2.1,1.2)))
		var tree_reserve:Dictionary=plan.get("props",{}).get("s12_tree_clearance",{})
		if not tree_reserve.is_empty():
			var xz:Array=tree_reserve.center_xz
			requests.append(request("s12/reference_oak",oak,Vector3(xz[0],0,xz[1]),0,Vector3.ONE))
		# These are independent landscape reserves, not courtyard attachments.
		# Keep the complete imported crown within the planned seven-metre envelope.
		for reserve:Dictionary in plan.get("other_reserves",[]):
			if reserve.get("type")=="tree_canopy":
				var center:Array=reserve.center
				var tree_scale:float=2*float(reserve.radius)/9.64645004272461
				requests.append(request("s1/south_reference_oak",oak,Vector3(center[0],0,center[1]),0,Vector3.ONE*tree_scale))
			elif reserve.get("type")=="laundry":
				var bounds:Array=reserve.bounds
				# Native laundry is X-long; its full 3.94m span fits the seven-metre
				# reserved strip without stretching the cloth or changing its wind.
				requests.append(request("s1/south_laundry",laundry,Vector3((float(bounds[0])+float(bounds[2]))/2,0,(float(bounds[1])+float(bounds[3]))/2),0))
		for courtyard:Dictionary in plan.get("courtyards",[]):
			var match:Array=plan.get("houses",[]).filter(func(h):return h.id==courtyard.house)
			if match.is_empty():errors.append("Courtyard house missing");continue
			var h:Dictionary=match[0];var actual:=actual_house(doc,h,final_houses)
			if actual.is_empty():continue
			var original:=Vector3(float(h.position[0]),0,float(h.position[-1]));var origin:=B.vec(actual.position)
			var delta_yaw:float=float(actual.yaw)-float(h.yaw);var turn:=Basis(Vector3.UP,deg_to_rad(delta_yaw))
			var line:Array=courtyard.closed_wall_polyline
			for segment in line.size()-1:
				var a:=origin+turn*(Vector3(line[segment][0],0,line[segment][1])-original)
				var b:=origin+turn*(Vector3(line[segment+1][0],0,line[segment+1][1])-original)
				var count:=maxi(1,ceili(a.distance_to(b)/2.4));var length:=a.distance_to(b)/count
				var angle:float=-rad_to_deg(atan2(b.z-a.z,b.x-a.x))
				for i in count:
					requests.append(request(str(courtyard.house)+"/wall_%d_%d"%[segment,i],wall,a.lerp(b,(i+.5)/count),angle,Vector3((length+.015)/2.391341, float(courtyard.get("wall_height",1.25))/1.54082,float(courtyard.get("wall_thickness",.4))/.472633)))
			for i in courtyard.gate.size():
				var at:Array=courtyard.gate[i]
				requests.append(request(str(courtyard.house)+"/gate_pier_"+str(i),pier,origin+turn*(Vector3(at[0],0,at[1])-original),float(actual.yaw),Vector3(.9,.85,.9)))
			for i in courtyard.get("canopy_reserves",[]).size():
				var reserve:Dictionary=courtyard.canopy_reserves[i];var center:Array=reserve.center
				var scale_:float=float(reserve.radius)*2/9.64645
				requests.append(request(str(courtyard.house)+"/oak_"+str(i),oak,origin+turn*(Vector3(center[0],0,center[1])-original),float(actual.yaw)+i*137,Vector3.ONE*scale_))
	for row:Dictionary in requests:
		if row.entry.is_empty():errors.append("Missing asset for "+str(row.key));continue
		if row.grounded:
			var point:=B.vec(row.position);var y:=ground(doc,point)
			if not is_finite(y):errors.append("No terrain: "+str(row.key))
			else:
				if str(row.key).contains("/wall_"):
					# Embed each short segment to its low endpoint rather than leaving
					# the downhill end hanging; do not flatten the courtyard terrain.
					var right:=Basis(Vector3.UP,deg_to_rad(float(row.yaw)))*Vector3.RIGHT
					var half:float=2.391341*float(row.scale[0])/2
					var a:=ground(doc,point-right*half);var b:=ground(doc,point+right*half)
					if not is_finite(a) or not is_finite(b):errors.append("Wall endpoint lacks terrain: "+str(row.key))
					else:
						row.endpoint_relief=maxf(y,maxf(a,b))-minf(y,minf(a,b));y=minf(y,minf(a,b))-.02
				row.position[1]=y
	# The verified nine-pennant GLB has rope anchors at X=+-5.65,Y=2.35.
	# Preserve its UVs, pinned cloth wind and actual hanging depth. Tilt the whole
	# span to join unequal-height posts rather than leaving a floating endpoint.
	if bunting.is_empty():errors.append("Missing formal nine-pennant bunting")
	else:
		for pair:Array in [["bridge_left_blue","bridge_right_raw_wood"],["lane_near_north","lane_near_south"],["lane_far_north","lane_far_south"]]:
			var left:Array=requests.filter(func(r):return r.key=="festival/"+pair[0]);var right:Array=requests.filter(func(r):return r.key=="festival/"+pair[1])
			if left.is_empty() or right.is_empty():continue
			var a:=B.vec(left[0].position)+Vector3.UP*(3.063523*float(left[0].scale[1])-.20)
			var b:=B.vec(right[0].position)+Vector3.UP*(3.063523*float(right[0].scale[1])-.20)
			var axis:Vector3=(b-a).normalized();var vertical:Vector3=(Vector3.UP-axis*axis.y).normalized();var basis:=Basis(axis,vertical,axis.cross(vertical))
			var at:Vector3=(a+b)/2-basis*Vector3(0,2.35,0)
			var row:=request("festival/span_"+str(pair[0]),bunting,at,-rad_to_deg(atan2(axis.z,axis.x)),Vector3(a.distance_to(b)/11.3,1,1),false)
			row.rotation=B.arr(basis.get_euler()*180/PI);row.collision="none";row.mount_a=B.arr(a);row.mount_b=B.arr(b)
			row.minimum_nominal_hanging_clearance=3.063523*minf(float(left[0].scale[1]),float(right[0].scale[1]))-.20-2.388019
			var clearance:=INF
			for sample in 33:
				var point:Vector3=a.lerp(b,sample/32.0);var soil:=ground(doc,point)
				if is_finite(soil):clearance=minf(clearance,point.y-2.388019-soil)
			row.minimum_terrain_clearance=clearance
			row.clearance_scope="33 terrain samples and full cloth vertical envelope; native road/bridge surface and animated wind checked in final scene"
			requests.append(row)
	return {"ok":errors.is_empty(),"requests":requests,"errors":errors,"material_deviations":["lane_near_south uses approved natural timber: green variant exists only in an old isolated cache library, not the current formal catalog"] if green_post.is_empty() else [],"validation":"Native placement, final collision/doorway/canopy clearance and scene visuals must be checked by caller."}
static func apply_requests(doc,prepared:Dictionary,only_missing:bool=false)->Dictionary:
	if not prepared.get("ok",false):return prepared
	var ids:Array=[];var placements:Array=[]
	for row:Dictionary in prepared.requests:
		if only_missing:
			var previous:Array=doc.records.filter(func(r):return r.get("editor_name")=="Axel reference "+str(row.key))
			if not previous.is_empty():
				# A reference correction may change a festival post's colour while
				# retaining its key. Replace through native operations, not by
				# mutating an immutable model's shared material in-place.
				var desired:String=row.entry.get("asset_path","")
				if row.entry.has("prefab_path"):
					var loaded:Dictionary=Library.read(row.entry)
					if not loaded.ok:return loaded
					if loaded.records.size()==1:desired=loaded.records[0].get("asset_path","")
				if str(row.key).begins_with("festival/") and not desired.is_empty() and previous.size()==1 and previous[0].get("asset_path","")!=desired:
					doc.remove(str(previous[0].uuid))
				else:continue
		var entry_:Dictionary=row.entry;var target:=B.vec(row.position);var scale_:=B.vec(row.scale);var basis:=Basis.from_euler(B.vec(row.rotation)*PI/180) if row.has("rotation") else Basis(Vector3.UP,deg_to_rad(float(row.yaw)))
		var start:int=doc.records.size()
		if entry_.has("prefab_path"):
			var result:Dictionary=Library.place(doc,entry_,target)
			if not result.get("ok",false):return {"ok":false,"error":result,"key":row.key,"ids":ids}
		else:doc.add_asset(entry_,target)
		for r:Dictionary in doc.records.slice(start):
			# Center ground assets by their actual imported bounds, including off-centre walls.
			var low:=B.vec(r.get("bounds_position",[0,0,0]));var size_:=B.vec(r.get("bounds_size",[0,0,0]))
			var pivot:=Vector3(low.x+size_.x/2,low.y,low.z+size_.z/2) if row.grounded else Vector3.ZERO
			r.position=B.arr(target+basis*((B.vec(r.position)-target-pivot)*scale_))
			r.rotation=B.arr((basis*Basis.from_euler(B.vec(r.get("rotation",[0,0,0]))*PI/180)).get_euler()*180/PI)
			r.size=B.arr(B.vec(r.get("size",[1,1,1]))*scale_)
			if row.has("collision"):r.collision=row.collision
			r.editor_name="Axel reference "+str(row.key);ids.append(r.uuid)
			var source_path:String=r.get("asset_path","")
			placements.append({"id":r.uuid,"key":row.key,"position":r.position,"rotation":r.rotation,"scale":r.size,"asset_label":entry_.get("label",""),"asset_id":entry_.get("id",""),"asset_path":source_path,"asset_sha256":FileAccess.get_sha256(source_path) if FileAccess.file_exists(source_path) else ""})
	return {"ok":true,"ids":ids,"placements":placements,"material_deviations":prepared.get("material_deviations",[])}
