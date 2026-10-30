extends RefCounted
## Presentation helpers for authoritative combat values. Missing data remains
## absent; these helpers never synthesize combat stats or decide eligibility.

static func skill_row(id:String,data:Dictionary,training:Dictionary={})->Dictionary:
	var row:=data.duplicate(true)
	row.id=id
	row.cooldown=float(data.get("timing",{}).get("cooldown_ms",0))/1000.
	row.cast_time=float(data.get("timing",{}).get("cast_ms",0))/1000.
	row.mp_cost=data.get("cost",{}).get("mp",0)
	row.range=data.get("target",{}).get("range_m",0)
	row.requires_target=data.get("target",{}).get("mode","")=="unit"
	row.target_mode="ground" if data.get("target",{}).get("mode","")=="area" else data.get("target",{}).get("mode","self")
	row.category=category(data,training)
	row.training=training.duplicate(true)
	row.desc=str(data.get("description",training.get("description","")))
	row.effect_summary=effect_summary(data)
	if not row.effect_summary.is_empty():row.desc+=("\n" if not row.desc.is_empty() else "")+row.effect_summary
	return row

static func category(data:Dictionary,training:Dictionary={})->String:
	var explicit:=str(training.get("category",data.get("category","")))
	if explicit in ["physical","magic","passive"]:return explicit
	if data.get("passive",false) or data.get("operation","")=="passive":return "passive"
	for effect:Dictionary in data.get("effects",[]):
		var formula:Variant=effect.get("formula",{})
		var channel:=str(formula.get("channel",formula.get("kind",""))) if formula is Dictionary else str(formula)
		if channel in ["magic","magical","spell"] or effect.get("type","") in ["heal_hp","heal_mp","resurrect"]:return "magic"
	return "physical"

static func effect_summary(data:Dictionary)->String:
	var labels:={"damage":"伤害","heal_hp":"治疗","heal_mp":"恢复法力","status":"施加状态","dispel":"驱散","resurrect":"复活","interrupt":"打断","displacement":"位移","control":"控制"}
	var parts:PackedStringArray=[]
	for effect:Dictionary in data.get("effects",[]):
		var kind:=str(effect.get("type",""))
		var text:=str(labels.get(kind,kind))
		if kind=="status":text+="："+str(effect.get("status",{}).get("key",""))
		elif effect.has("base"):text+=" %d" % int(effect.base)
		if not text.is_empty():parts.append(text)
	return "；".join(parts)

static func status_state(snapshot:Dictionary)->Dictionary:
	return snapshot.get("statuses",snapshot)

static func status_row(status:Dictionary,now_game:float,cancelable:Array)->Dictionary:
	var spec:Dictionary=status.get("definition",{})
	var policy:Dictionary=spec.get("policy",{})
	var kind:=str(spec.get("kind",""))
	var harmful:bool=policy.get("class","")=="debuff"
	if not policy.has("class") or policy.get("class","").is_empty():
		harmful=kind in ["damage","stun","silence","root","slow"] or kind in ["attack","defense"] and int(spec.get("base",0))<0
	var display:="debuff" if harmful else "buff"
	if kind=="damage":display="dot"
	elif kind in ["heal_hp","heal_mp"]:display="hot"
	return {"id":status.get("status_id",""),"name":spec.get("key",""),"kind":display,"effect_kind":kind,"stacks":status.get("stacks",1),"remaining_sec":maxf(0.,float(status.get("expires_game_us",0))/1000000.-now_game),"duration_max":float(spec.get("duration_ms",0))/1000.,"can_cancel":status.get("status_id","") in cancelable,"authoritative":true}

static func aim_yaw(origin:Vector3,destination:Vector3,fallback:float=0.)->float:
	var direction:=destination-origin
	return atan2(-direction.x,-direction.z) if Vector2(direction.x,direction.z).length_squared()>0.000001 else fallback

static func attribute_text(stats:Dictionary,key:String)->String:
	if not stats.has(key):return "未提供"
	return str(int(stats[key]))
