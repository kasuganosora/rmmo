extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Packs generated pose art and attaches separate generated hair/features.
var ROOT:String = ArtPaths.path("character_creator_mv_style")
const TYPES := ["Male","Female","YoungMale","YoungFemale"]
const DIRS := ["front","left","left","back","front_left","front_left","back_left","back_left"]
const COLS := [0,1,1,3,4,4,6,6]
const POSES := [[0,0,0,0],[0,1,0,2],[3,4,5,0],[6,7,6,7],[8,9,9,8],[0,10,11,11],[0,12,13,13],[0,14,15,15]]
var layout: Dictionary
func _initialize()->void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/source/layout.json"))
	var sources:={}
	for d in DIRS:
		if not sources.has(d):sources[d]=Image.load_from_file(ROOT+"/source/motion_"+d+".png")
	var review:=Image.create(768,768,false,Image.FORMAT_RGBA8)
	review.fill(Color("252936"))
	for t in range(4):
		var folder: String=ROOT+"/Motion/"+TYPES[t]
		DirAccess.make_dir_recursive_absolute(folder)
		var layers:={}
		var output:={"TV_Body_p01_m001.png":sheet()}
		for file in DirAccess.get_files_at(ROOT+"/TV/"+TYPES[t]):
			if file.ends_with(".png") and ("_FrontHair" in file or "_Eyes_" in file):
				layers[file]=Image.load_from_file(ROOT+"/TV/"+TYPES[t]+"/"+file)
				output[file]=sheet()
		for d in range(8):
			var row: Array=layout["motion_"+DIRS[d]].rows[t]
			var standing: Dictionary=layout.standing.rows[t][COLS[d]]
			var height:=48 if t<2 else 44
			var sf:=float(height)/float(standing.rect[3])
			var sw:=roundi(float(standing.rect[2])*sf)
			var old_head:=Vector2(24-sw/2,66-height)+Vector2(float(standing.head[0])-float(standing.rect[0]),float(standing.head[1])-float(standing.rect[1]))*sf
			if d in [2,5,7]:old_head.x=47-old_head.x
			var scale_factor:=float(height)/float(row[0].rect[3])
			for a in range(8):
				for f in range(4):
					var pose: int=POSES[a][f]
					var rec: Dictionary=row[pose]
					var r:=rect(rec.rect)
					var size:=Vector2i(maxi(1,roundi(r.size.x*scale_factor)),maxi(1,roundi(r.size.y*scale_factor)))
					var offset:=Vector2i(48-size.x/2,80-size.y)
					var body:=Image.create(96,96,false,Image.FORMAT_RGBA8)
					var art: Image=sources[DIRS[d]].get_region(r)
					art.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
					if d in [2,5,7]:art.flip_x()
					body.blit_rect(art,Rect2i(Vector2i.ZERO,size),offset)
					stamp(output["TV_Body_p01_m001.png"],body,a,d,f)
					var head:=Vector2(float(rec.head[0])-r.position.x,float(rec.head[1])-r.position.y)*scale_factor
					if d in [2,5,7]:head.x=size.x-1-head.x
					head+=Vector2(offset)
					var angle:=deg_to_rad(90 if d in [2,5,7] else -90) if pose==11 else 0.0
					var composed:=body.duplicate()
					for file in layers:
						var src: Image=layers[file].get_region(Rect2i(48,d*72,48,72))
						var part:=attach(src,old_head,head,angle)
						stamp(output[file],part,a,d,f)
						if "p01_" in file:composed.blend_rect(part,Rect2i(0,0,96,96),Vector2i.ZERO)
					if t==0 and f==2:review.blend_rect(composed,Rect2i(0,0,96,96),Vector2i(d*96,a*96))
		for file in output:assert(output[file].save_png(folder+"/"+file)==OK)
		print("Packed MV-style motion: ",TYPES[t])
	review.save_png(ROOT+"/motion_review.png")
	quit()
func sheet()->Image:return Image.create(384,6144,false,Image.FORMAT_RGBA8)
func rect(a:Array)->Rect2i:return Rect2i(int(a[0]),int(a[1]),int(a[2]),int(a[3]))
func stamp(img:Image,part:Image,a:int,d:int,f:int)->void:img.blit_rect(part,Rect2i(0,0,96,96),Vector2i(f*96,(a*8+d)*96))
func attach(src:Image,old_head:Vector2,head:Vector2,angle:float)->Image:
	var result:=Image.create(96,96,false,Image.FORMAT_RGBA8)
	for y in range(96):
		for x in range(96):
			var p:=Vector2i((Vector2(x,y)-head).rotated(-angle)+old_head)
			if p.x>=0 and p.x<48 and p.y>=0 and p.y<72:result.set_pixel(x,y,src.get_pixel(p.x,p.y))
	return result
