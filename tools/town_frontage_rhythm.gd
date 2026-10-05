extends RefCounted
## Authoring recipe: seeded candidate search, not a runtime generator or a
## global placement restriction. See docs/town_frontage_rhythm_20261005.md.
const B=preload("res://scripts/world3d/building_blueprint.gd")

static func valid_levels(levels:Array)->bool:
	var last_tall:=-10
	for i in levels.size():
		if i>=2 and levels[i]==levels[i-1] and levels[i]==levels[i-2]:return false
		if levels[i]==3:
			if i-last_tall<3:return false
			last_tall=i
	return true

static func score(levels:Array)->float:
	var value:=0.0
	for i in range(1,levels.size()):
		if levels[i]==levels[i-1]:value+=.6
		# A repeating high/low or three-building motif is another kind of grid.
		if i>=3 and levels[i]==levels[i-2] and levels[i-1]==levels[i-3]:value+=2.0
		if i>=5 and levels.slice(i-5,i-2)==levels.slice(i-2,i+1):value+=2.0
	if levels.size()==16:
		var a:int=levels.slice(0,8).count(3)
		if a==0 or a==3:return INF
		for i in 8:
			if levels[i]==levels[i+8]:value+=.25
		# Keep at least one taller shop visible in the first half of each side.
		if not 3 in levels.slice(0,4):value+=2.0
		if not 3 in levels.slice(8,12):value+=2.0
	return value

static func sequence(use_:String,seed_:int)->Array:
	var rng:=RandomNumberGenerator.new();rng.seed=seed_
	var pool:Array=[1,1,1,1,2,2,2,2,2,2,2,2,2,3,3,3] if use_=="shop" else [1,1,2,2,2,2,2,3]
	var best:Array=[];var best_score:=INF
	for attempt in 4096:
		var candidate:=pool.duplicate()
		for i in range(candidate.size()-1,0,-1):
			var j:=rng.randi_range(0,i);var tmp=candidate[i];candidate[i]=candidate[j];candidate[j]=tmp
		if not valid_levels(candidate):continue
		var quality:=score(candidate)+rng.randf()*.2
		if quality<best_score:best_score=quality;best=candidate
	if best.is_empty():return []
	var presets:=B.town_presets();var result:Array=[];var uses:Dictionary={}
	for level:int in best:
		var choices:Array=presets.filter(func(p):return p.parameters.template==use_ and p.parameters.floors==level)
		var selected:Dictionary={};var cost:=INF
		for p:Dictionary in choices:
			var c:float=float(uses.get(p.id,0))*.7+rng.randf()
			if not result.is_empty():
				if p.id==result[-1].id:c+=20
				if p.parameters.roof_axis==result[-1].parameters.roof_axis:c+=.3
			if c<cost:cost=c;selected=p
		if selected.is_empty():return []
		uses[selected.id]=int(uses.get(selected.id,0))+1
		var row:=selected.duplicate(true)
		row.setback=snappedf(rng.randf_range(2.8,5.1) if use_=="shop" else rng.randf_range(3.8,6.2),.05)
		row.gap=snappedf(rng.randf_range(2.7,5.8),.05)
		result.append(row)
	var windows:=RandomNumberGenerator.new();windows.seed=seed_+701
	var window_usage:Dictionary={};var previous:=""
	for row:Dictionary in result:
		var family:="";var best_cost:=INF
		for style:String in preload("res://scripts/world3d/house_window_styles.gd").IDS:
			var cost:float=float(window_usage.get(style,0))+windows.randf()+(5.0 if style==previous else 0.0)
			if cost<best_cost:best_cost=cost;family=style
		row.family_id=row.id;row.id+="__"+family;row.parameters.window_style=family
		row.parameters.shutters=family=="tall_shutter"
		window_usage[family]=int(window_usage.get(family,0))+1;previous=family
	return result

static func audit(houses:Array)->Dictionary:
	var histogram:={"1":0,"2":0,"3":0};var groups:Dictionary={};var max_run:=0;var valid:=true;var windows:Dictionary={}
	for row:Dictionary in houses:
		histogram[str(row.floors)]+=1
		var style:String=row.get("window_style","")
		windows[style]=int(windows.get(style,0))+1
		valid=valid and style in preload("res://scripts/world3d/house_window_styles.gd").IDS
		var key:String=str(row.edge)+":"+str(row.side)
		if not groups.has(key):groups[key]=[]
		groups[key].append(row)
	var streets:Array=[]
	for key in groups:
		var rows:Array=groups[key];rows.sort_custom(func(a,b):return a.station<b.station)
		var run:=0;var previous:=-1;var levels:Array=[]
		for row:Dictionary in rows:
			levels.append(row.floors);run=run+1 if row.floors==previous else 1;previous=row.floors;max_run=maxi(max_run,run)
		valid=valid and valid_levels(levels)
		streets.append({"edge_side":key,"floors":levels})
	return {"floors":histogram,"window_families":windows,"max_same_floor_run":max_run,"valid":valid,"frontages":streets}
