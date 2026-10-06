"""Run with system Python; renders a separate Blender banner variant, never publishes."""
from pathlib import Path
import math, subprocess
from PIL import Image, ImageDraw, ImageFont

OUT=Path('D:/code/rmmo_runtime/art_sources/wall_guild_banners/soviet_variant')
OUT.mkdir(parents=True,exist_ok=True)
# Rasterize a standard symbol, keeping its physical proportions on the tall UV atlas.
glyph=Image.new('L',(1000,1000));d=ImageDraw.Draw(glyph)
font=ImageFont.truetype('C:/Windows/Fonts/seguisym.ttf',900)
d.text((500,500),'\u262d',font=font,fill=255,anchor='mm')
glyph=glyph.crop(glyph.getbbox());glyph.thumbnail((460,460))
glyph=glyph.resize((glyph.width,round(glyph.height*(4096/7.2)/(768/1.15))),Image.Resampling.LANCZOS)
mask=Image.new('L',(768,4096));mask.paste(glyph,((768-glyph.width)//2,850))
d=ImageDraw.Draw(mask)
def star(radius):
    return [(384+math.sin(i*math.pi/5)*(radius if i%2==0 else radius*.382),
             700-math.cos(i*math.pi/5)*(radius if i%2==0 else radius*.382)*.852)
            for i in range(10)]
d.polygon(star(112),fill=255);d.polygon(star(86),fill=0)
mask.save(OUT/'emblem_mask.png')

BLENDER_SCRIPT=r'''
import bpy, math, json, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/wall_guild_banners/soviet_variant')
BASE=OUT.parent
bpy.ops.wm.open_mainfile(filepath=str(BASE/'wall_guild_banners_optimized.blend'))
sc=bpy.context.scene
cloth=bpy.data.objects['guild_swallowtail_tall_cloth']
for o in list(bpy.data.objects):
    if o.type=='MESH' and not o.name.startswith('Review') and o!=cloth and abs(o.location.x)>1:
        bpy.data.objects.remove(o,do_unlink=True)
parts=[o for o in sc.objects if o.type=='MESH' and not o.name.startswith('Review')]
cloth.name='soviet_swallowtail_tall_cloth'
m=cloth.data.materials[0].copy();m.name='Red woven textile - Soviet emblem';cloth.data.materials[0]=m
w,h=768,4096
im=bpy.data.images.load(str(OUT/'emblem_mask.png'));im.colorspace_settings.name='Non-Color'
arr=np.empty(w*h*4,dtype=np.float32);im.pixels.foreach_get(arr);mask=arr.reshape(h,w,4)[:,:,0].copy()
v,u=np.mgrid[0:h,0:w];u=(u+.5)/w;v=1-(v+.5)/h
edge=1-.72/7.2*(1-2*abs(u-.5))
mask[(u<.035)|(u>.965)|(abs(v-edge+.025)<.012)|(v<.018)]=1
rng=np.random.default_rng(620);noise=rng.normal(0,1,(h,w))
weave=np.sin(u*math.tau*180)*np.sin(v*math.tau*1200)
variation=.93+.025*weave+.018*noise+.035*np.sin(u*32+np.sin(v*18))
def linear(c):
    c=np.array(c)/255.;return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
base=np.array([.34,.014,.022]);gold=linear([255,215,0])  # Match the approved original banner red exactly.
rgb=(base[None,None,:]*(1-mask[:,:,None])+gold*mask[:,:,None])*variation[:,:,None]
stitches=(((abs(u-.022)<.0016)|(abs(u-.978)<.0016))&((v*150)%1<.55))|((abs(v-edge+.024)<.0018)&((u*100)%1<.55))
rgb[stitches]=linear([202,159,24])
def saveim(name,pixels,color):
    image=bpy.data.images.new(name,width=w,height=h,alpha=True)
    image.colorspace_settings.name='sRGB' if color else 'Non-Color'
    image.pixels.foreach_set(pixels.astype(np.float32).ravel());image.filepath_raw=str(OUT/(name+'.png'));image.file_format='PNG';image.save();image.pack();return image
rgba=np.ones((h,w,4));rgba[:,:,:3]=np.clip(rgb,0,1)
albedo=saveim('soviet_artwork',rgba,True)
rough=np.clip(.9+.035*weave+.025*noise-mask*.05,.72,1);rgba[:,:,:3]=rough[:,:,None]
rmap=saveim('soviet_roughness',rgba,False)
for node in m.node_tree.nodes:
    if node.type=='TEX_IMAGE':
        if node.name=='REPLACE ARTWORK':node.image=albedo
        elif node.name=='Roughness':node.image=rmap
        elif node.name=='Normal':
            node.image=node.image.copy();node.image.filepath_raw=str(OUT/'woven_normal.png');node.image.save();node.image.pack()
bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Metallic'].default_value=0
cloth['artwork_variant']='Soviet red field; gold hammer and sickle; gold outlined red five-point star'
cam=sc.camera;sc.render.resolution_x=800;sc.render.resolution_y=1500;sc.render.resolution_percentage=100;sc.cycles.samples=40
def view(loc,target,scale):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
def render(name):
    sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
view((2,-18,6),(0,0,3.85),8.2)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'soviet_swallowtail.blend'),compress=True)
render('preview')
view((.5,-8,6.1),(0,0,5.8),2.6);sc.render.resolution_x=950;sc.render.resolution_y=1100;render('emblem_detail')
bpy.ops.object.select_all(action='DESELECT')
rigid=[o for o in parts if o!=cloth]
for o in rigid:
    o.select_set(True);bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    o.select_set(False)
for o in rigid:o.select_set(True)
bpy.context.view_layer.objects.active=rigid[0];bpy.ops.object.join();support=bpy.context.object;support.name='soviet_swallowtail_rigid_support'
cloth.select_set(True)
path=OUT/'soviet_swallowtail_tall.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_morph=False,export_apply=True)
(OUT/'manifest.json').write_text(json.dumps(dict(status='offline review; not published',width=1.15,height=7.2,mount_height=7.5,tip_clearance=.3,cut_depth=.72,source=str(BASE/'wall_guild_banners_optimized.blend'),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),palette_linear_red=[.34,.014,.022],palette_srgb_gold='#FFD700',palette_note='User requested the original guild banner vermilion red; gold emblem unchanged',symbol_source='Segoe UI Symbol U+262D plus constructed outlined five-point star',wind=dict(cloth['rmmo_wind'])),ensure_ascii=False,indent=2),encoding='utf8')
print('SOVIET_BANNER_COMPLETE',flush=True)
'''
script=OUT/'build_blender.py';script.write_text(BLENDER_SCRIPT,encoding='utf8')
with (OUT/'build.log').open('w',encoding='utf8') as log:
    result=subprocess.run(['C:/Program Files/Blender Foundation/Blender 4.5/blender.exe','-b','--python',str(script)],stdout=log,stderr=subprocess.STDOUT)
raise SystemExit(result.returncode)
