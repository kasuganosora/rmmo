extends RefCounted
## Continuous articulated motion in character-local coordinates.
const DURATION := {"idle":2.5,"walk":1.3333333333,"dash":.6666666667,"attack":.65,"cast":1.4666666667,"death":2.4,"sit_ground":.65,"sit_chair":.65}

static func apply(model:Node3D,time:float)->bool:
	match model.action:
		"idle":
			joint(model,"spine",Vector3(sin(time*1.8)*.012,0,0))
			joint(model,"head",Vector3(-sin(time*1.8)*.008,0,0))
			for side in ["L","R"]:joint(model,"forearm"+side,Vector3(-.12,0,0))
		"walk","dash":gait(model,time,model.action=="dash")
		"cast":cast_spell(model,time)
		"death":fall(model,time)
		_:return false
	return true

static func joint(model:Node3D,id:String,angles:Vector3)->void:
	if model.bones.has(id):model._rotate(id,angles)

static func gait(model:Node3D,time:float,running:bool)->void:
	var cycle:float=DURATION.dash if running else DURATION.walk
	var phase:=fposmod(time/cycle,1.0)
	var wave:=sin(phase*TAU)
	var bob:float=(-.055-.025*cos(phase*TAU*2)) if running else (-.035+.012*cos(phase*TAU*2))
	var shift:=Vector3((.009 if running else .018)*wave,bob,0)
	model.rig.position=Basis(Vector3.UP,float(model.YAW.get(model.direction,0)))*shift
	joint(model,"hips",Vector3(0,wave*.045,wave*.022))
	joint(model,"spine",Vector3(.13 if running else .025,-wave*.08,-wave*.018))
	joint(model,"chest",Vector3(.055 if running else .008,-wave*.055,0))
	joint(model,"head",Vector3(-.07 if running else -.02,wave*.08,0))
	for side in ["L","R"]:
		var phase_side:=fposmod(phase+(0.0 if side=="L" else .5),1.0)
		var stance:=.40 if running else .62
		var stride:=.39 if running else .23
		var forward:float
		var lift:=0.0
		var pitch:=0.0
		if phase_side<stance:
			var p:=phase_side/stance
			forward=lerpf(stride,-stride,p)
			pitch=lerpf(-.18,0,smoothstep(0,.18,p))+.27*smoothstep(.7,1,p)
		else:
			var p:float=(phase_side-stance)/(1-stance)
			forward=lerpf(-stride,stride,smoothstep(0,1,p))
			lift=sin(p*PI)*(.30 if running else .13)
			pitch=-.14*sin(p*PI)
		model.imported_rig.plant_leg(model,side,Vector3(0,lift,forward)-shift/model.rig.scale,pitch)
		var swing:=cos(phase_side*TAU)
		var sign_x:float=-1.0 if side=="L" else 1.0
		joint(model,"arm"+side,Vector3(swing*(.62 if running else .29),0,-sign_x*.035))
		joint(model,"forearm"+side,Vector3(-1.0+.16*sin(phase_side*TAU-.5) if running else -.18+.08*sin(phase_side*TAU-.45),0,0))
		joint(model,"hand"+side,Vector3(.06,0,sign_x*.035))

static func envelope(time:float,start:float,end:float)->float:
	return smoothstep(start,end,time)

static func cast_spell(model:Node3D,time:float)->void:
	# Gather at the torso, aim, release, then lower the arms.
	var gather:=envelope(time,0,.34)
	var release:=envelope(time,.62,.86)
	var recover:=envelope(time,1.04,1.5)
	var active:=1-recover
	joint(model,"hips",Vector3(0,-.07*gather*active,0))
	joint(model,"spine",Vector3((-.055*gather+.12*release)*active,.13*gather*active,0))
	joint(model,"chest",Vector3(.035*release*active,-.08*gather*active,0))
	joint(model,"head",Vector3(-.035*gather*active,-.06*gather*active,0))
	joint(model,"armR",Vector3(lerpf(-.50,-1.40,release)*gather*active,-.08*gather*active,-.08*gather*active))
	joint(model,"forearmR",Vector3(lerpf(-1.05,-.20,release)*gather*active-.12*recover,0,0))
	joint(model,"handR",Vector3(-.22*release*active,0,.10*gather*active))
	joint(model,"armL",Vector3(-.48*gather*active,.13*gather*active,.10*gather*active))
	joint(model,"forearmL",Vector3(-.95*gather*active-.12*recover,0,0))
	joint(model,"handL",Vector3(-.10*gather*active,0,-.18*gather*active))
	for side in ["L","R"]:model.imported_rig.plant_leg(model,side,Vector3.ZERO,0)

static func fall(model:Node3D,time:float)->void:
	var recoil:=envelope(time,0,.16)*(1-envelope(time,.20,.46))
	var buckle:=envelope(time,.16,.54)
	var fall_side:=envelope(time,.40,1.10)
	var settle:=envelope(time,1.10,1.55)
	joint(model,"spine",Vector3(-.12*recoil+.34*buckle-.19*fall_side,0,-.12*fall_side))
	joint(model,"chest",Vector3(.12*buckle,0,-.08*fall_side))
	joint(model,"head",Vector3(.22*buckle,0,.12*fall_side))
	joint(model,"thighL",Vector3(-.75*buckle+.38*fall_side,0,-.10*fall_side))
	joint(model,"thighR",Vector3(-.56*buckle+.38*fall_side,0,.17*fall_side))
	joint(model,"shinL",Vector3(1.36*buckle-.70*fall_side,0,0))
	joint(model,"shinR",Vector3(1.16*buckle-.78*fall_side,0,0))
	joint(model,"armL",Vector3(-.45*buckle+.30*settle,0,-.24*fall_side+.39*settle))
	joint(model,"armR",Vector3(-.65*buckle+.26*settle,0,.16*fall_side-.30*settle))
	joint(model,"forearmL",Vector3(-.60*buckle+.30*settle,0,0))
	joint(model,"forearmR",Vector3(-.85*buckle+.30*settle,0,0))
	var angle:float=-1.48*fall_side-.035*sin(settle*PI)
	var yaw:=Basis(Vector3.UP,float(model.YAW.get(model.direction,0)))
	var tilt:=Basis(Vector3.BACK,angle)
	var hip:Vector3=model.imported_rig.rest_positions.hips*model.rig.scale
	var destination:=hip+Vector3(.17*fall_side,-.27*buckle-(hip.y-.46)*fall_side,.07*fall_side)
	model.rig.basis=yaw*tilt*Basis.from_scale(model.rig.scale)
	model.rig.position=yaw*(destination-tilt*hip)
