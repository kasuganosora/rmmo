extends RefCounted
## Review-only support geometry. No controller, map, or collision changes.
const Stair=preload("res://scripts/world3d/fortification_stair_mesh.gd")

static func vec(value:Array)->Vector3:
	return Vector3(value[0],value[1],value[2])

static func authored_tread(point:Vector3,record:Dictionary)->bool:
	if not point.is_finite() or record.get("fortification",{}).get("role","")!="tower_stair":return false
	var height:float=record.size[1]-1.1
	var spec:=Stair.spec(height,record.size[0]*.5)
	var local:=Basis.from_euler(vec(record.rotation)*PI/180).inverse()*(point-vec(record.position))
	var radius:=Vector2(local.x,local.z).length()
	# The inner 16 cm are a one-metre-high parapet, never a tread exemption.
	if radius<spec.inner+.16-.003 or radius>spec.outer+.08+.003:return false
	var angle:=fposmod(atan2(local.z,local.x),TAU)
	if angle>spec.sweep+.001:return false
	var step_angle:float=spec.sweep/spec.count
	var step:=int(floor(angle/step_angle))
	# At a shared radial edge either adjacent horizontal face can own contact.
	for index in [step-1,step,step+1]:
		if index<0 or index>=int(spec.count):continue
		if angle<index*step_angle-.001 or angle>(index+1)*step_angle+.001:continue
		var top:float=-float(record.size[1])*.5+height*(index+1)/spec.count
		if absf(local.y-top)<=.015:return true
	return false

static func contact_valid(on_floor:bool,floor_normal:Vector3,radius:float,radial_distance:float,bottom_y:float,hit:Vector3,normal:Vector3,known_tread:bool)->bool:
	if not on_floor or not known_tread or not floor_normal.is_finite() or not normal.is_finite():return false
	if floor_normal.y<cos(deg_to_rad(45)) or normal.y<cos(deg_to_rad(45)):return false
	if not hit.is_finite() or not is_finite(bottom_y) or not is_finite(radial_distance) or not is_finite(radius):return false
	if radius<=0 or radial_distance<0 or radial_distance>radius+.002:return false
	# The .035 m solver tolerance matches the existing doorway review. This
	# compares the spherical foot at the actual contact radius; it does not
	# increase the flat-ground centre-ray gap or accept a floor below a fall.
	var foot_y:=bottom_y+radius-sqrt(maxf(0.,radius*radius-radial_distance*radial_distance))
	return absf(hit.y-foot_y)<=.035
