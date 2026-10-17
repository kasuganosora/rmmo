extends RefCounted
## A map-local receipt, never inferred from proximity or generated ID prefixes.
const Data=preload("res://scripts/world3d/city_layout.gd")

static func capture(graph:Dictionary,key:String,building:Dictionary)->Dictionary:
	var edge:Dictionary=graph.edges.filter(func(e):return e.id=="home_"+key+"_access")[0]
	var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=node
	return {"version":1,"edge":edge.duplicate(true),"door":nodes[edge.from].duplicate(true),"join":nodes[edge.to].duplicate(true),"position":building.position.duplicate(),"yaw":building.yaw}

static func schema()->Dictionary:
	return Data.object({"version":Data.S.number(1,1,true),"edge":Data.edge_schema(),"door":Data.node_schema(),"join":Data.node_schema(),"position":Data.S.vector(-100000,100000),"yaw":Data.S.number(-180,180)},["version","edge","door","join","position","yaw"])

static func removal(graph:Dictionary,building:Dictionary,registry:Dictionary)->Dictionary:
	var receipt:Variant=building.get("residential_access")
	if not Data.S.validate(receipt,schema()).is_empty():return {"ok":false,"code":"access_unowned","error":"旧入户路没有有效的专属归属记录，请选择保留旧路；不会按距离或名称删除道路"}
	if Data.token([building.position,building.yaw])!=Data.token([receipt.position,receipt.yaw]):return {"ok":false,"code":"access_modified","error":"建筑已在归属记录之外移动，请保留旧路并重新确认关系"}
	var edges:Array=graph.edges.filter(func(e):return e.id==receipt.edge.id)
	var nodes:Dictionary={}
	for node:Dictionary in graph.nodes:nodes[node.id]=node
	if edges.size()!=1 or receipt.edge.from!=receipt.door.id or receipt.edge.to!=receipt.join.id or receipt.edge.get("kind")!="ground" or receipt.edge.has("controls") or receipt.edge.has("bridge_ref") or receipt.edge.has("stone_bridge"):
		return {"ok":false,"code":"access_modified","error":"旧入户路身份或结构已变化，请保留旧路"}
	for pair:Array in [[edges[0],receipt.edge],[nodes.get(receipt.door.id,{}),receipt.door],[nodes.get(receipt.join.id,{}),receipt.join]]:
		if pair[0].get("locked",false) or pair[0].get("hidden",false):return {"ok":false,"code":"protected_scope","error":"旧入户路或端点被锁定／隐藏"}
		if Data.token(pair[0])!=Data.token(pair[1]):return {"ok":false,"code":"access_modified","error":"旧入户路或端点已手改，请保留旧路"}
	if graph.edges.filter(func(e):return receipt.door.id in [e.from,e.to]).size()!=1:return {"ok":false,"code":"access_shared","error":"旧门前端点已接入其他道路，不能移除共享支路"}
	var owners:=0
	for value:Dictionary in registry.values():
		var other:Variant=value.get("residential_access",{})
		if other is Dictionary and other.get("edge") is Dictionary and other.edge.get("id")==receipt.edge.id:owners+=1
	if owners!=1:return {"ok":false,"code":"access_shared","error":"旧入户路没有唯一建筑归属"}
	return {"ok":true,"edge_id":receipt.edge.id,"node_id":receipt.door.id,"retained_join_id":receipt.join.id}
