extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
## Technical registration of generated garment poses into independent animation layers.
var ROOT:String = ArtPaths.path("character_creator_mv_style")
const TYPES := ["Male","Female","YoungMale","YoungFemale"]
const DIRS := ["front","left","left","back","front_left","front_left","back_left","back_left"]
const POSES := [[0,0,0,0],[0,1,0,2],[3,4,5,0],[6,7,6,7],[8,9,9,8],[0,10,11,11],[0,12,13,13],[0,14,15,15]]
const CATS := ["Clothing1","Clothing2","Boots","Belt"]
var layout: Dictionary
func _initialize()->void:
	# Bulk overlays were rejected for invalid anatomy. Never repack them as production art.
	push_error("MV-style equipment batch rejected: trousers include extra limbs and full-body silhouettes. Rebuild from individually reviewed poses.")
	quit(1)
	return

func _pack_unreviewed_draft()->void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/source/layout.json"))
	var sources:={}
	for d in DIRS:
		for cat in CATS:
			var key: String="equipment_"+d+"_"+cat
			if layout.has(key) and not sources.has(key):sources[key]=Image.load_from_file(ROOT+"/source/"+key+".png")
	var review:=Image.create(768,768,false,Image.FORMAT_RGBA8)
	review.fill(Color("252936"))
	for t in range(4):
		var folder: String=ROOT+"/Motion/"+TYPES[t]
		var output:={}
		for cat in CATS:output[cat]=Image.create(384,6144,false,Image.FORMAT_RGBA8)
		var body:=Image.load_from_file(folder+"/TV_Body_p01_m001.png")
		var hair:=Image.load_from_file(folder+"/TV_FrontHair1_p01_m003.png")
		var face:=Image.load_from_file(folder+"/TV_Eyes_p01_m000.png")
		for d in range(8):
			if not sources.has("equipment_"+DIRS[d]+"_Clothing1"):continue
			var row: Array=layout["motion_"+DIRS[d]].rows[t]
			var factor:=float(48 if t<2 else 44)/float(row[0].rect[3])
			for a in range(8):
				for f in range(4):
					var pose: int=POSES[a][f]
					var rec: Dictionary=row[pose]
					var r:=rect(rec.rect)
					var size:=Vector2i(roundi(r.size.x*factor),roundi(r.size.y*factor))
					var offset:=Vector2i(48-size.x/2,80-size.y)
					var head:=(Vector2(rec.head[0],rec.head[1])-Vector2(r.position))*factor+Vector2(offset)
					var rad:=float(rec.head_radius)*factor
					var waist:=(Vector2(rec.waist[0],rec.waist[1])-Vector2(r.position))*factor+Vector2(offset)
					var dest:=Vector2i(f*96,(a*8+d)*96)
					var composed:=body.get_region(Rect2i(dest,Vector2i(96,96)))
					for cat in ["Clothing2","Clothing1","Boots","Belt"]:
						var key: String="equipment_"+DIRS[d]+"_"+cat
						if not sources.has(key):continue
						var src_rect:=rect(layout[key].rows[t][pose])
						var garment: Image=sources[key].get_region(src_rect)
						var box: Rect2i
						var neck:=roundi(head.y+rad*.9)
						var wy:=clampi(roundi(waist.y),neck+3,77)
						var torso_w:=maxi(8,roundi(rad*2.5))
						var leg_w:=maxi(7,roundi(rad*1.9))
						if pose in [6,7]:leg_w=maxi(leg_w,size.x-3)
						if pose in [10,12,13]:leg_w=size.x-2
						match cat:
							"Clothing1":box=Rect2i(roundi(head.x)-torso_w/2,neck,torso_w,wy-neck+3)
							"Clothing2":box=Rect2i(roundi(waist.x)-leg_w/2,wy,leg_w,79-wy)
							"Boots":box=Rect2i(roundi(waist.x)-leg_w/2,74,leg_w,6)
							"Belt":box=Rect2i(roundi(waist.x)-leg_w/2,wy,leg_w,2)
						if pose==11:
							var nx:=roundi(head.x+rad*.9)
							var wx:=roundi(offset.x+size.x*.70)
							match cat:
								"Clothing1":box=Rect2i(nx,80-maxi(7,roundi(rad*1.5)),maxi(4,wx-nx+2),maxi(7,roundi(rad*1.5)))
								"Clothing2":box=Rect2i(wx,72,offset.x+size.x-wx,8)
								"Boots":box=Rect2i(offset.x+size.x-5,72,5,8)
								"Belt":
									garment.rotate_90(CLOCKWISE)
									box=Rect2i(wx,72,2,8)
						box.size=box.size.max(Vector2i.ONE)
						garment.resize(box.size.x,box.size.y,Image.INTERPOLATE_NEAREST)
						var layer:=Image.create(96,96,false,Image.FORMAT_RGBA8)
						layer.blit_rect(garment,Rect2i(Vector2i.ZERO,box.size),box.position)
						if d in [2,5,7]:layer.flip_x()
						output[cat].blit_rect(layer,Rect2i(0,0,96,96),dest)
						composed.blend_rect(layer,Rect2i(0,0,96,96),Vector2i.ZERO)
					composed.blend_rect(face,Rect2i(dest,Vector2i(96,96)),Vector2i.ZERO)
					composed.blend_rect(hair,Rect2i(dest,Vector2i(96,96)),Vector2i.ZERO)
					if t==0 and f==2:review.blend_rect(composed,Rect2i(0,0,96,96),Vector2i(d*96,a*96))
		for cat in CATS:output[cat].save_png(folder+"/TV_%s_p01_m007.png"%cat)
		print("Packed MV-style equipment: ",TYPES[t])
	review.resize(1536,1536,Image.INTERPOLATE_NEAREST)
	review.save_png(ROOT+"/equipment_review.png")
	quit()
func rect(a:Array)->Rect2i:return Rect2i(int(a[0]),int(a[1]),int(a[2]),int(a[3]))
