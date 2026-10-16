extends "res://tools/apply_axel_functional_vegetation.gd"
var slope:=0.0
var missing_ground:=false
func ground(p:Vector2)->float:return NAN if missing_ground else p.x*slope
func run():
 plan=read(OUT+"/functional_vegetation_plan.json")
 for a:Dictionary in plan.assets:
  if a.label not in [plan.tree_palette.woodland,plan.tree_palette.orchard]:continue
  var low:Array
  if a.kind=="prefab_path":
   var box:AABB=Foot.record_shape(read(a.asset_id).records[0]).bounds;low=[box.position.x,box.position.y,box.position.z]
  else:low=a.entry.bounds_position
  palette[a.label]={"low":low,"size":a.bounds_size}
 print("SUPPORT_INIT ",load_tree_support()," ",tree_support_error);check(load_tree_support(),"actual SHA and centered pivot match both basal hulls")
 for label:String in palette:
  var size_:Array=palette[label].size
  var full:=rect_poly([-size_[0]/2,-size_[2]/2,size_[0],size_[2]])
  slope=.10
  check(root_support(label,Vector2.ZERO,0,"tree",full).ok,"gentle actual root support allowed despite broad crown slope "+label)
  slope=2.
  check(not root_support(label,Vector2.ZERO,0,"tree",full).ok,"steep actual root support rejected "+label)
  missing_ground=true
  check(not root_support(label,Vector2.ZERO,0,"tree",full).ok,"missing ground rejected "+label)
  missing_ground=false;slope=.10
  check(not root_support(label,Vector2.ZERO,0,"shrub",full).ok,"non-tree full footprint protection unchanged "+label)
 tree_support_loaded=false;palette[plan.tree_palette.woodland].low[0]+=1.
 check(not load_tree_support(),"changed pivot cannot reuse measured hull")
 FileAccess.open(OUT+"/vegetation_basal_support_logic_review.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"mode":"synthetic terrain against exact real model hull; no authoring","helper_sha256":FileAccess.get_sha256("res://tools/apply_axel_functional_vegetation.gd")},"\t"))
 print("BASAL_SUPPORT failures=",failed);quit(0 if failed==0 else 1)
