extends RefCounted
## The explicit Blender slot keeps cloth, emblem and wind separate from metalwork.
const Schema=preload("res://scripts/world3d/document_schema.gd")
static var _meshes:Dictionary={}

static func schema()->Dictionary:
	return {"type":"object","additionalProperties":false,"properties":{
		"shape":{"type":"string","enum":["pointed","rectangle","swallowtail"]},
		"design":{"type":"string","enum":["original","plain","flag","emblem"]},
		"color":Schema.vector(0,1),"trim_color":Schema.vector(0,1),
		"texture_path":{"type":"string","maxLength":2048},"wind_enabled":{"type":"boolean"}}}

static func defaults()->Dictionary:
	return {"shape":"pointed","design":"original","color":[.31,.016,.026],"trim_color":[.75,.45,.12],"texture_path":"","wind_enabled":true}

static func settings(record:Dictionary)->Dictionary:
	var value:=defaults().merged(record.get("banner",{}),true)
	value.texture_path=record.get("banner",{}).get("material",{}).get("texture_path","")
	value.erase("material")
	return value

static func store(value:Dictionary)->Dictionary:
	var result:=value.duplicate(true);result.erase("texture_path")
	result.material={"name":"路灯旗帜图案","color":[1.0,1.0,1.0,1.0],"roughness":.9,"texture_path":value.texture_path}
	return result

static func valid(record:Dictionary)->bool:
	if not record.has("banner"):return true
	if record.get("kind")!="asset" or not record.banner is Dictionary:return false
	if not record.banner.get("material") is Dictionary:return false
	for key in record.banner:
		if key=="texture_path" or (key!="material" and not schema().properties.has(key)):return false
	var value:=settings(record)
	return Schema.validate(value,schema()).is_empty() and (value.design not in ["flag","emblem"] or not value.texture_path.is_empty())

static func slot(root:Node)->MeshInstance3D:
	if root is MeshInstance3D and root.get_meta("extras",{}).get("rmmo_banner_slot",false):return root
	for child in root.get_children():
		var found:=slot(child)
		if found!=null:return found
	return null

static func apply(root:Node3D,record:Dictionary)->void:
	var node:=slot(root)
	if node==null:return
	preload("res://scripts/world3d/streetlamp_lights.gd").annotate(root,str(record.uuid))
	var value:=settings(record)
	var key:Array=[node.mesh.get_instance_id(),value]
	if record.has("banner"):
		if not _meshes.has(key):
			var built:=build(node.mesh,value)
			if built==null:root.set_meta("paint_error","旗帜贴图无法读取");return
			if _meshes.size()>=64:_meshes.erase(_meshes.keys()[0])
			_meshes[key]=built
		node.mesh=_meshes[key]
	var extras:Dictionary=node.get_meta("extras",{}).duplicate(true)
	# Fabric must not become a solid obstacle; post collision stays unchanged.
	extras.rmmo_collision="none"
	if value.wind_enabled:
		extras.rmmo_wind={"profile":"cloth","mesh":"*","anchor":"top","amplitude":.45,"stiffness":.22,"shelter":true}
	else:extras.erase("rmmo_wind")
	node.set_meta("extras",extras)
	if value.wind_enabled:load("res://scripts/world3d/wind_response.gd").register(node)

static func build(source:Mesh,value:Dictionary)->ArrayMesh:
	var result:=ArrayMesh.new()
	var color:=Color(value.color[0],value.color[1],value.color[2])
	var gold:=Color(value.trim_color[0],value.trim_color[1],value.trim_color[2])
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.9;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	if value.design in ["flag","emblem"]:
		var paint=load("res://scripts/world3d/surface_materials.gd")
		var texture:Texture2D=paint.texture({"texture_path":value.texture_path})
		if texture==null:return null
		var input:=texture.get_image();input.convert(Image.FORMAT_RGBA8)
		var composed:=Image.create(512,1024,false,Image.FORMAT_RGBA8);composed.fill(color)
		if value.design=="flag":
			input.resize(512,1024,Image.INTERPOLATE_LANCZOS);composed.blend_rect(input,Rect2i(0,0,512,1024),Vector2i.ZERO)
		else:
			var ratio:=minf(340.0/input.get_width(),350.0/input.get_height());input.resize(maxi(1,roundi(input.get_width()*ratio)),maxi(1,roundi(input.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
			composed.blend_rect(input,Rect2i(Vector2i.ZERO,input.get_size()),Vector2i((512-input.get_width())/2,170))
		composed.generate_mipmaps();mat.albedo_texture=ImageTexture.create_from_image(composed);mat.albedo_color=Color.WHITE;mat.texture_repeat=false
	var original:bool=value.shape=="pointed"
	if original:result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(0))
	else:
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in 14:
			for i in 8:
				for offset:Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
					var u:float=(i+offset.x)/8.0;var v:float=(j+offset.y)/14.0
					var length_:float=1.14-(.26*(1-absf(u*2-1)) if value.shape=="swallowtail" else 0.0)
					st.set_uv(Vector2(u,v));st.set_normal(Vector3.BACK)
					st.add_vertex(Vector3(-.945+u*.67,2.835-v*length_,.038-.032*sin(u*PI*2+.4)*sin(PI*v)-.025*v*v))
		st.generate_tangents();st.index();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,st.commit_to_arrays())
	result.surface_set_material(0,mat)
	if value.design=="original":
		# The crest/border deforms in the same slot, with the same anchor bounds.
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(1))
		var trim:StandardMaterial3D=source.surface_get_material(1).duplicate();trim.albedo_color=gold
		result.surface_set_material(1,trim)
	return result
