extends RefCounted
## Reusable local-review item: uses the same server clock as the normal world.
const ID:="day_night_review_dial"
const DEFINITION:={"id":ID,"name":"昼夜切换仪（验收）","type":"misc","rarity":"uncommon","stack_max":1,"consumable":false,"use_effect":"toggle_day_night","sell_price":0,"description":"双击切换白天 12:00 / 夜晚 00:00，并暂停时间推进。可重复使用，不消耗；仅改变当前地图本次运行的环境。"}

static func grant(inventory)->bool:
	if inventory.has_item(ID,1):return true
	return inventory.add_item(ID,1,true)==1

static func failure(message:String)->Dictionary:
	return {"ok":false,"actions":[{"type":"system_message","text":message}]}

static func use(server,map_id:String,request_environment:Callable)->Dictionary:
	if server.inventory==null or not server.inventory.has_item(ID,1):return failure("背包中没有昼夜切换仪。")
	if not request_environment.is_valid() or not server.has_method("snapshot_world3d_sky"):return failure("地图环境尚未就绪，请稍后再试。")
	var sky:Dictionary=server.snapshot_world3d_sky(map_id)
	if not sky.get("ok",false):return failure("地图环境尚未就绪，请稍后再试。")
	# Read the authoritative running hour, never a delayed client presentation flag.
	var hour:float=sky.time_of_day_hours
	var next_hour:=12.0 if hour<6.0 or hour>=20.0 else 0.0
	var result:Dictionary=request_environment.call({"time_hours":next_hour,"time_speed":0.0})
	if not result.get("ok",false):return failure(str(result.get("error","昼夜切换失败，请稍后再试。")))
	var label_:="白天 12:00" if next_hour==12.0 else "夜晚 00:00"
	return {"ok":true,"time_hours":next_hour,"actions":[{"type":"system_message","text":"已切换为%s，时间已暂停。再次双击可切回；道具不会消耗。"%label_}]}
