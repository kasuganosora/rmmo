extends RefCounted
## Private asset finalization. Share one preorder node list for banner discovery
## and receiver registration; each node/receiver is a bounded cursor step.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Wind=preload("res://scripts/world3d/wind_response.gd")
const Lights=preload("res://scripts/world3d/streetlamp_lights.gd")
var holder:Node3D
var record:Dictionary={}
var document:RefCounted
var nodes:Array[Node]=[]
var visuals:Array[MeshInstance3D]=[]
var excluded:Dictionary={}
var banner_slot:MeshInstance3D
var wind_config:Dictionary={}
var phase:=0
var at:=0
var profile:Dictionary={"visited_nodes":0,"registered_visuals":0}

func begin(doc:RefCounted,root:Node3D,value:Dictionary,model_nodes:Array[Node]=[])->void:
	document=doc;holder=root;record=value
	nodes=[holder]
	# Namespace preparation already visited this exact private graph. Components
	# rename/annotate those nodes but do not create or remove descendants.
	nodes.append_array(model_nodes if not model_nodes.is_empty() else holder.find_children("*","",true,false))

func advance(budget_usec:int)->bool:
	var began:=Time.get_ticks_usec();var advanced:=false
	while phase<5 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true
		if phase==0:
			if at>=nodes.size():nodes.clear();excluded.clear();at=0;phase=1;continue
			var node:Node=nodes[at];at+=1;profile.visited_nodes+=1
			var blocked:bool=excluded.has(node.get_parent()) or node.get_meta("editor_shadow_proxy",false)
			if blocked:excluded[node]=true
			if node is MeshInstance3D:
				if not blocked and node.mesh!=null:visuals.append(node)
				# Banner.slot includes proxy descendants and selects its first tag.
				if banner_slot==null and node.get_meta("extras",{}).get("rmmo_banner_slot",false):banner_slot=node
		elif phase==1:
			Banner.apply_slot(holder,record,banner_slot);banner_slot=null;phase=2
		elif phase==2:
			Paint.apply(holder,record,document.load_paint_validation,document.load_texture_checks)
			if record.has("wind_response") and Wind.valid(record):wind_config=Wind.resolve(record)
			phase=3
		elif phase==3:
			if at>=visuals.size():visuals.clear();wind_config.clear();phase=4;continue
			var visual:MeshInstance3D=visuals[at];at+=1;profile.registered_visuals+=1
			if not wind_config.is_empty() and (wind_config.mesh=="*" or str(holder.get_path_to(visual))==wind_config.mesh):Wind.annotate_mesh(visual,wind_config)
			Wind.register(visual);Lights.register(visual)
		else:
			holder=preload("res://scripts/world3d/vegetation_render.gd").flatten(holder,record);phase=5
	return phase==5

func take_holder()->Node3D:
	var result:=holder;dispose();return result

func dispose()->void:
	# The enclosing instance cursor owns/freezes/frees the graph. This helper
	# owns only traversal state and must never free that graph a second time.
	holder=null;document=null;record={};nodes.clear();visuals.clear();excluded.clear();banner_slot=null;wind_config={};phase=5
