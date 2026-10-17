extends RefCounted
## Read-only bridge ownership captured for a private residential transaction.
## Road preparation still performs the full approach and clearance validation.
const Data=preload("res://scripts/world3d/city_layout.gd")
const Bridges=preload("res://scripts/world3d/road_bridges.gd")
const BridgeTools=preload("res://scripts/world_editor/bridge_road_tools.gd")

static func failure(message:String,ids:Array=[])->Dictionary:
	return {"ok":false,"code":"bridge_context_invalid","stage":"bridge_context","error":message,"conflicts":ids}

static func capture(editor:Node3D,data:Dictionary)->Dictionary:
	var resolved:=Bridges.resolve(data)
	if not resolved.ok:return failure(resolved.error)
	var records:Dictionary={};var nodes:Dictionary={};var edges:Dictionary={}
	var checked_waterways:Dictionary={}
	for portal:Dictionary in resolved.portals:
		if portal.get("road_stone",false):
			var checked:=BridgeTools.verify(editor,portal)
			if not checked.ok:return failure(checked.error,[portal.deck_id])
		else:
			var id:String=portal.reference.waterway_id
			if not checked_waterways.has(id):
				for region:Dictionary in data.get("waterways",[]):
					if region.settings.id!=id:continue
					var checked:Dictionary=editor._waterways.owned(region)
					if not checked.ok:return failure(checked.error,region.parts.map(func(p):return p.id))
					for part:String in checked.ids:records[part]=editor._doc._find(part).duplicate(true)
					checked_waterways[id]=true
		for id:String in portal.part_ids:records[id]=editor._doc._find(id).duplicate(true)
		for node:Dictionary in data.roads.nodes:
			if node.id in portal.nodes:nodes[node.id]=node.duplicate(true)
		for edge:Dictionary in data.roads.edges:
			if edge.id==portal.edge_id:edges[edge.id]=edge.duplicate(true)
	# Unbound physical bridges also remain outside this operation's write scope.
	for record:Dictionary in editor._doc.records:
		if record.has("bridge_mesh"):records[record.uuid]=record.duplicate(true)
	return {"ok":true,"records":records,"nodes":nodes,"edges":edges,"portals":resolved.portals,"waterways":data.get("waterways",[]).duplicate(true),"summary":{"binding_count":resolved.portals.size(),"waterway_count":checked_waterways.size(),"preserved_ids":records.keys(),"bridgehead_node_ids":nodes.keys()}}

static func verify(doc,data:Dictionary,captured:Dictionary)->Dictionary:
	for id:String in captured.records:
		if Data.token(doc._find(id))!=Data.token(captured.records[id]):return failure("候选会改变桥梁或关联河道构件，已保留原地图",[id])
	if Data.token(data.get("waterways",[]))!=Data.token(captured.waterways):return failure("候选会改变河道归属或配方，已保留原地图")
	for pair:Array in [["nodes",captured.nodes],["edges",captured.edges]]:
		for id:String in pair[1]:
			var matches:Array=data.roads[pair[0]].filter(func(item):return item.id==id)
			if matches.size()!=1 or Data.token(matches[0])!=Data.token(pair[1][id]):return failure("候选会改变桥梁绑定或桥头节点，已保留原地图")
	var resolved:=Bridges.resolve(data)
	if not resolved.ok:return failure(resolved.error)
	if Data.token(resolved.portals)!=Data.token(captured.portals):return failure("候选会改变桥头、净宽或引道关系，已保留原地图")
	return {"ok":true}
