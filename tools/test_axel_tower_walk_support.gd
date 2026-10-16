extends SceneTree
const Support=preload("res://tools/axel_tower_walk_support.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/tower_walk_support_precheck.json"
var checks:Array=[]
func check(passed:bool,label_:String)->void:
	checks.append({"passed":passed,"name":label_});print("PASS " if passed else "FAIL ",label_)
func _initialize()->void:
	var record:={"position":[145.,14.9,30.],"rotation":[0.,-97.,0.],"size":[11.2,8.6,11.2],"fortification":{"role":"tower_stair"}}
	var height:=7.5;var count:=42;var step:=10;var angle:float=PI*1.25*(step+.5)/count
	var top:float=-4.3+height*(step+1)/count
	var local:=Vector3(cos(angle)*3.2,top,sin(angle)*3.2)
	var pose:=Transform3D(Basis.from_euler(Support.vec(record.rotation)*PI/180),Support.vec(record.position))
	var point:=pose*local
	check(Support.authored_tread(point,record),"rotated and elevated real tread accepted")
	check(not Support.authored_tread(point+Vector3.UP*.08,record),"point above tread rejected")
	check(not Support.authored_tread(point-Vector3.UP*.08,record),"tread underside and riser height rejected")
	check(not Support.authored_tread(pose*Vector3(cos(angle)*2.32,top+1.05,sin(angle)*2.32),record),"inner parapet cannot count as a tread")
	check(not Support.authored_tread(pose*Vector3(cos(angle)*5.5,top,sin(angle)*5.5),record),"outer tower skin cannot count as a tread")
	check(not Support.authored_tread(pose*Vector3(cos(5.)*3.2,top,sin(5.)*3.2),record),"space outside stair sweep rejected")
	var other:=record.duplicate(true);other.position[0]+=20
	check(not Support.authored_tread(point,other),"a different tower cannot authorize the support")
	other=record.duplicate(true);other.fortification.role="wall"
	check(not Support.authored_tread(point,other),"ordinary fortification wall has no tread exemption")
	var radius:=.3;var radial:=.15
	var sphere_rise:=radius-sqrt(radius*radius-radial*radial)
	var bottom_y:float=point.y-sphere_rise
	check(Support.contact_valid(true,Vector3.UP,radius,radial,bottom_y,point,Vector3.UP,true),"grounded spherical capsule contact accepted")
	var lower_tread_y:float=point.y-height/count
	check(bottom_y-lower_tread_y>.12,"legitimate higher-tread contact exceeds old centre-ray .12m gap")
	check(not Support.contact_valid(false,Vector3.UP,radius,radial,bottom_y,point,Vector3.UP,true),"airborne capsule is not grounded by a nearby tread")
	check(not Support.contact_valid(true,Vector3.UP,radius,radial,bottom_y+.10,point,Vector3.UP,true),"unsupported gap cannot use the spherical contact exception")
	check(not Support.contact_valid(true,Vector3.UP,radius,radial,bottom_y,point,Vector3.RIGHT,true),"vertical wall normal rejected")
	check(not Support.contact_valid(true,Vector3.RIGHT,radius,radial,bottom_y,point,Vector3.UP,true),"native wall contact cannot masquerade as floor")
	check(not Support.contact_valid(true,Vector3.UP,radius,.35,bottom_y,point,Vector3.UP,true),"support outside actual capsule radius rejected")
	check(not Support.contact_valid(true,Vector3.UP,radius,radial,bottom_y,point,Vector3.UP,false),"unknown surface rejected")
	check(not Support.contact_valid(true,Vector3.UP,radius,radial,NAN,point,Vector3.UP,true),"invalid measurement rejected")
	var failures:=checks.filter(func(row):return not row.passed).size()
	var result:={"passed":failures==0,"checks":checks,"failures":failures,"scope":"pure review predicate regression; no map/controller/model changes; real final-map navigation still requires production GPU rerun","helper_sha256":FileAccess.get_sha256("res://tools/axel_tower_walk_support.gd"),"review_sha256":FileAccess.get_sha256("res://tools/review_axel_town_fortifications.gd"),"native_step_height_m":height/count,"old_center_gap_false_negative_m":bottom_y-lower_tread_y}
	var file:=FileAccess.open(OUT,FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	quit(0 if failures==0 else 1)
