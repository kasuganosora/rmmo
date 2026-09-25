extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
var ROOT:String = ArtPaths.path("character_creator_mv_style")
const TYPES := ["Male","Female","YoungMale","YoungFemale"]
const COLS := [0,1,1,3,4,4,6,6]
const GEAR := ["Clothing1","Clothing2","Boots","Belt"]
var layout: Dictionary
var images := {}

func _initialize() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/source/layout.json"))
	var review := Image.create(8*96,4*144,false,Image.FORMAT_RGBA8)
	review.fill(Color("252936"))
	for t in range(4):
		var folder: String = ROOT+"/TV/"+TYPES[t]
		DirAccess.make_dir_recursive_absolute(folder)
		var sheets := {}
		for key in ["Body", "FrontHair1_1", "FrontHair1_2", "Eyes_1", "Eyes_2"]+GEAR:
			sheets[key] = Image.create(144,576,false,Image.FORMAT_RGBA8)
		for d in range(8):
			var col: int = COLS[d]
			var rec: Dictionary = layout.standing.rows[t][col]
			var r := rect(rec.rect)
			var height := 48 if t<2 else 44
			var factor := float(height)/r.size.y
			var size := Vector2i(roundi(r.size.x*factor),height)
			var offset := Vector2i(24-size.x/2,66-height)
			var head := Vector2i(Vector2(float(rec.head[0])-r.position.x,float(rec.head[1])-r.position.y)*factor)+offset
			var radius := float(rec.head_radius)*factor
			var body := cell()
			var art := source("body_standing").get_region(r)
			art.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
			body.blit_rect(art,Rect2i(Vector2i.ZERO,size),offset)
			var layers := {"Body":body}
			for v in [1,2]:
				var hair := part("hair_%d"%v,t,col)
				var hw := roundi(radius*2.9)
				var hh := roundi(radius*2.1)
				hair.resize(hw,hh,Image.INTERPOLATE_NEAREST)
				var layer := cell()
				layer.blit_rect(hair,Rect2i(0,0,hw,hh),Vector2i(head.x-hw/2,head.y-roundi(radius)-4))
				layers["FrontHair1_%d"%v] = layer
				var face := cell()
				if d not in [3,6,7]:
					var feat := portrait_feature(t,v)
					var fw := 10 if d == 0 else (5 if d in [1,2] else 8)
					feat.resize(fw,7,Image.INTERPOLATE_NEAREST)
					var shift := 0 if d==0 else (-5 if d in [1,2] else -2)
					face.blit_rect(feat,Rect2i(0,0,fw,7),Vector2i(head.x-fw/2+shift,head.y+2))
				layers["Eyes_%d"%v] = face
			for cat in GEAR:
				var gear := part("standing_"+cat,0 if cat=="Clothing1" else t,col)
				var gw: int
				var gh: int
				var gy: int
				match cat:
					"Clothing1":
						gh=roundi(height*.35);gw=roundi(size.x*1.03);gy=66-height+roundi(height*.41)
					"Clothing2":
						gh=roundi(height*.29);gw=roundi(size.x*.65);gy=64-gh
					"Boots":
						gh=roundi(height*.19);gw=roundi(size.x*.70);gy=66-gh
					_:
						gh=3;gw=roundi(size.x*.62);gy=66-roundi(height*.32)
				gear.resize(gw,gh,Image.INTERPOLATE_NEAREST)
				var layer:=cell()
				layer.blit_rect(gear,Rect2i(0,0,gw,gh),Vector2i(24-gw/2,gy))
				layers[cat]=layer
			var composed:=cell()
			for key in ["Body","Clothing2","Clothing1","Boots","Belt","Eyes_1","FrontHair1_1"]:
				composed.blend_rect(layers[key],Rect2i(0,0,48,72),Vector2i.ZERO)
			if d in [2,5,7]:
				composed.flip_x()
			for key in layers:
				var layer: Image=layers[key]
				if d in [2,5,7]:layer.flip_x()
				for f in range(3):sheets[key].blit_rect(layer,Rect2i(0,0,48,72),Vector2i(f*48,d*72))
			composed.resize(96,144,Image.INTERPOLATE_NEAREST)
			review.blend_rect(composed,Rect2i(0,0,96,144),Vector2i(d*96,t*144))
		for key in sheets:
			var cat: String=key.split("_")[0]
			var variant:=int(key.split("_")[1]) if "_" in key else 1
			var m:=1 if cat=="Body" else (3 if cat=="FrontHair1" else (7 if cat in GEAR else 0))
			sheets[key].save_png(folder+"/TV_%s_p%02d_m%03d.png"%[cat,variant,m])
		pack_portrait(t)
	review.save_png(ROOT+"/standing_review.png")
	var portraits:=Image.create(576,288,false,Image.FORMAT_RGBA8)
	portraits.fill(Color("252936"))
	for t in range(4):
		for v in [1,2]:
			for file in ["FG_Body_p01_m001.png","FG_Clothing1_p01_m007.png","FG_Eyes_p%02d_m000.png"%v,"FG_FrontHair1_p%02d_m003.png"%v]:
				var img:=Image.load_from_file(ProjectSettings.globalize_path(ROOT+"/Face/"+TYPES[t]+"/"+file))
				portraits.blend_rect(img,Rect2i(0,0,144,144),Vector2i(t*144,(v-1)*144))
	portraits.resize(1152,576,Image.INTERPOLATE_NEAREST)
	portraits.save_png(ROOT+"/portrait_review.png")
	quit()

func pack_portrait(t:int)->void:
	var folder: String=ROOT+"/Face/"+TYPES[t]
	DirAccess.make_dir_recursive_absolute(folder)
	var base:=portrait_cell("portrait_clean",t)
	base.resize(144,144,Image.INTERPOLATE_LANCZOS)
	base.save_png(folder+"/FG_Body_p01_m001.png")
	for v in [1,2]:
		var face:=Image.create(144,144,false,Image.FORMAT_RGBA8)
		var feat:=portrait_feature(t,v)
		feat.resize(50,42,Image.INTERPOLATE_LANCZOS)
		face.blit_rect(feat,Rect2i(0,0,50,42),Vector2i(38,39))
		face.save_png(folder+"/FG_Eyes_p%02d_m000.png"%v)
		var hair:=portrait_cell("portrait_hair_%d"%v,t)
		var bound:=opaque(hair)
		hair=hair.get_region(bound)
		var hair_height := 64 if v==1 and t%2==0 else 78
		hair.resize(104,hair_height,Image.INTERPOLATE_LANCZOS)
		var layer:=Image.create(144,144,false,Image.FORMAT_RGBA8)
		layer.blit_rect(hair,Rect2i(0,0,104,hair_height),Vector2i(17,0))
		layer.save_png(folder+"/FG_FrontHair1_p%02d_m003.png"%v)
	var shirt:=portrait_cell("portrait_Clothing1",t%2)
	shirt=shirt.get_region(opaque(shirt))
	shirt.resize(144,44,Image.INTERPOLATE_LANCZOS)
	var clothing:=Image.create(144,144,false,Image.FORMAT_RGBA8)
	clothing.blit_rect(shirt,Rect2i(0,0,144,44),Vector2i(0,100))
	clothing.save_png(folder+"/FG_Clothing1_p01_m007.png")

func portrait_feature(t:int,v:int)->Image:
	var image:=portrait_cell("portrait_features_%d"%v,t)
	return image.get_region(opaque(image))
func portrait_cell(name:String,t:int)->Image:
	var img:=source(name)
	var size:=img.get_size()/2
	return img.get_region(Rect2i(Vector2i((t%2)*size.x,(t/2)*size.y),size))
func part(name:String,t:int,d:int)->Image:
	return source(name).get_region(rect(layout.parts[name].rows[t][d]))
func source(name:String)->Image:
	if not images.has(name):images[name]=Image.load_from_file(ProjectSettings.globalize_path(ROOT+"/source/"+name+".png"))
	return images[name]
func rect(a:Array)->Rect2i:return Rect2i(int(a[0]),int(a[1]),int(a[2]),int(a[3]))
func cell()->Image:return Image.create(48,72,false,Image.FORMAT_RGBA8)
func opaque(img:Image)->Rect2i:
	var lo:=img.get_size();var hi:=Vector2i(-1,-1)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x,y).a>.5:
				lo=lo.min(Vector2i(x,y));hi=hi.max(Vector2i(x,y))
	return Rect2i(lo,hi-lo+Vector2i.ONE)
