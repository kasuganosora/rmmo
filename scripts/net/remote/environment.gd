extends RefCounted
## Runtime environment menus and house authority projections.
var transport:Node
var options:Dictionary={}
var _serial:=0
func _init(owner:Node)->void:transport=owner
func reset()->void:options.clear()
func label(row:Dictionary)->String:
	return {"door":"门","window":"窗","shutter":"窗板"}.get(str(row.get("fixture_kind","")),{"fixture":"门窗","switch":"开关","mechanism":"机关"}.get(str(row.get("kind","")),"交互物"))
func menu(selected:Dictionary,feet:Vector3)->Array:
	options.clear()
	var choices:Array=[]
	var rows:Array=transport.business_snapshots.get("interactions",{}).get("objects",[])
	var houses:Dictionary={}
	for row:Dictionary in rows:
		var p:Variant=row.get("position",[])
		if not p is Array or p.size()!=3:continue
		var distance:=feet.distance_to(Vector3(p[0],p[1],p[2]))
		if distance>float(row.get("radius_m",0.)):continue
		var title:=label(row)+"（%.1f 米）"%distance
		for action:String in row.get("actions",[]):
			_serial+=1;var key:="environment:"+str(_serial)
			options[key]={"operation":"map_interaction","args":[row.id,action],"scope":transport.context()}
			var verb:=str({"open":"打开","close":"关闭","use":"操作","toggle":"切换"}.get(action,action))
			if action=="open" and row.get("access") is Dictionary and not row.access.get("can_operate",false):verb="开门通行："
			choices.append({"id":key,"label":verb+title})
		var access:Variant=row.get("access")
		if access is Dictionary and not houses.has(access.house):
			houses[access.house]=true;_serial+=1;var key:="environment:"+str(_serial)
			options[key]={"operation":"house_view","args":[access.house],"scope":transport.context()}
			choices.append({"id":key,"label":str(access.get("name","房屋"))+" · 权限"})
	var text:="请选择附近的门窗、开关或机关。"
	var access:Variant=selected.get("access")
	if access is Dictionary:
		text=str(access.get("name","房屋"))+"\n"+{"personal":"个人共享房屋","guild":"公会驻地","public":"公共建筑"}.get(str(access.get("kind","")),"房屋")
		text+="\n入口已开放，访客可以进入。" if access.get("open_to_visitors",false) else ("\n你有进入权限。" if access.get("can_enter",false) else "\n入口关闭，你没有进入权限。")
		if not access.get("can_operate",false):text+="\n你没有门窗操作权限。"
	return [{"type":"show_npc_dialogue","npc_name":"环境互动","body":text,"options":choices}]
func choose(id:String)->Dictionary:
	if not options.has(id):return {"ok":false,"error":"环境菜单已变化，请重新交互","actions":[]}
	var choice:Dictionary=options[id];options.clear()
	if choice.scope!=transport.context():return transport.gameplay.failure("环境菜单所属地图已变化，请重新交互")
	return transport.gameplay.dispatch(str(choice.operation),choice.args)
func request(operation:String,args:Array)->Dictionary:
	if operation=="house_view":return {"path":"/v1/world/houses?house="+str(args[0]).uri_encode(),"method":HTTPClient.METHOD_GET,"body":{}}
	return {"path":"/v1/world/houses","method":HTTPClient.METHOD_POST,"body":args[0].duplicate(true)}
func result(data:Dictionary)->Array:return [{"type":"house_permissions","house":data.duplicate(true)}]
