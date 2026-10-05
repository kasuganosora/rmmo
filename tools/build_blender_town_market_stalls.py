"""Reference-led street stalls: offline Blender review, no game integration."""
import bpy,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT.parent/'rmmo_runtime/art_sources/town_market_stalls';OUT.mkdir(exist_ok=True)
cfg=json.loads((ROOT/'tools/town_market_stalls_parameters.json').read_text(encoding='utf-8-sig'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);random.seed(10561)
with bpy.data.libraries.load(str(ROOT.parent/'rmmo_runtime/art_sources/town_low_fence/town_low_fence.blend'),link=False) as (src,dst):
    dst.materials=[n for n in src.materials if n.startswith('Fab solid timber')]
wood=dst.materials[0]
def mat(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.87
    return m
def cloth(name,color):
    m=mat(name,color);nt=m.node_tree;p=nt.nodes.get('Principled BSDF');p.inputs['Specular IOR Level'].default_value=.18
    uv=nt.nodes.new('ShaderNodeTexCoord');noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=120;nt.links.new(uv.outputs['UV'],noise.inputs['Vector'])
    bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.45;bump.inputs['Distance'].default_value=.0015;nt.links.new(noise.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs[0],p.inputs['Normal'])
    ramp=nt.nodes.new('ShaderNodeMapRange');ramp.inputs['To Min'].default_value=.68;ramp.inputs['To Max'].default_value=1.1;nt.links.new(noise.outputs['Fac'],ramp.inputs['Value'])
    mix=nt.nodes.new('ShaderNodeMixRGB');mix.name='USER CLOTH COLOR';mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[1].default_value=(*color,1);nt.links.new(ramp.outputs[0],mix.inputs[2]);nt.links.new(mix.outputs[0],p.inputs['Base Color']);return m
blue=cloth('Blue grey heavy woven canopy',(.13,.22,.27));purple=cloth('Faded plum canvas',(.26,.13,.28));gold=cloth('Ochre stitched cloth edging',(.60,.45,.18))
rope=mat('Hemp ties',(.34,.25,.13));wicker=mat('Willow basket',(.24,.12,.042));leaf=mat('Dried herbs',(.11,.19,.05))
fruits=[mat(n,c) for n,c in [('Red apples',(.42,.05,.025)),('Green pears',(.31,.34,.055)),('Plums',(.095,.035,.12))]]
def mesh(name,vs,fs,m,uv=None):
    d=bpy.data.meshes.new(name);d.from_pydata(vs,[],fs);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(m)
    layer=d.uv_layers.new(name='Surface UV')
    for lp in d.loops:
        co=d.vertices[lp.vertex_index].co;layer.data[lp.index].uv=uv[lp.vertex_index] if uv else (co.x,co.z)
    return o
def box(name,loc,size,m=wood):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    bevel=o.modifiers.new('Soft worn timber edges','BEVEL');bevel.width=.004;bevel.segments=1;return o
def beam(name,a,b,width=.075,m=wood):
    a,b=Vector(a),Vector(b);o=box(name,(a+b)/2,(width,width,(b-a).length),m);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o
def cord(name,points,r=.009,m=rope):
    data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.bevel_depth=r;data.bevel_resolution=1
    s=data.splines.new('POLY');s.points.add(len(points)-1)
    for p,co in zip(s.points,points):p.co=(*co,1)
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);data.materials.append(m);return o
def fruit(loc,kind=0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=random.uniform(.045,.06),location=loc);o=bpy.context.object;o.name='Removable produce';o.scale.z=1.15 if kind==1 else .88;o.data.materials.append(fruits[kind])
    for p in o.data.polygons:p.use_smooth=True
def basket(center,rx=.30,ry=.22,h=.23):
    x,y,z=center
    for row in range(10):
        t=row/9;r=.70+.30*t
        cord('Woven willow course',[(x+rx*r*math.cos(a*math.tau/40),y+ry*r*math.sin(a*math.tau/40),z+h*t) for a in range(41)],.008,wicker)
    for k in range(24):
        a=k*math.tau/24;cord('Basket upright',[(x+rx*(.7+.3*t)*math.cos(a),y+ry*(.7+.3*t)*math.sin(a),z+h*t) for t in [0,.25,.5,.75,1]],.006,wicker)
    box('Basket inset bottom',(x,y,z+.018),(rx*1.35,ry*1.35,.026),wicker)
for idx,variant in enumerate(cfg['variants']):
    offset=(idx-2)*3.6;canopy=cloth(variant['id']+' canopy',variant['canopy_color']);gold=cloth(variant['id']+' trim',variant['trim_color'])
    if variant['contents'] not in ['none','produce','pottery','potions','scrolls','ores']:raise ValueError('Unknown contents preset')
    start=set(bpy.context.scene.objects);w=2.8;depth=1.7;front=-.85;back=.85;hf=2.48;hb=2.82
    def P(x,y,z):return (x+offset,y,z)
    for x in [-w/2+.11,w/2-.11]:
        for y,h in [(front+.12,hf),(back-.12,hb)]:
            beam('Timber upright',P(x,y,0),P(x,y,h-.04),.085)
        beam('Side roof bearer',P(x,front,hf-.055),P(x,back,hb-.055),.075)
        beam('Side knee brace',P(x,back-.12,1.92),P(x,back-.60,2.65),.055)
        beam('Counter side bearer',P(x,front, .94),P(x,-.04,.94),.07)
        beam('Counter diagonal brace',P(x,front+.12,.48),P(x,-.08,.94),.052)
    for y,h in [(front,hf-.025),(back,hb-.025)]:beam('Canopy edge roller',P(-w/2,y,h),P(w/2,y,h),.06)
    # Rear operating lane remains open from the side, clear of front merchandise.
    for j in range(5):box('Countertop plank',P(0,front+.04+j*.145,.985),(w,.138,.048))
    for j in range(13):box('Counter front boards',P(-w/2+.11+j*(w-.22)/12,front+.045,.57),(.20,.033,.78))
    for z in [.23,.88]:beam('Counter front rail',P(-w/2,front+.07,z),P(w/2,front+.07,z),.06)
    # Taut cloth follows the rear/front bearers with shallow wrinkles, no water pocket.
    def roof(u,v):
        x=(u-.5)*(w+.16);y=front+(back-front)*v;z=hf+(hb-hf)*v-.025*math.sin(math.pi*u)*math.sin(math.pi*v)+.006*math.sin(u*41+v*4)*math.sin(math.pi*v)
        return P(x,y,z+.022)
    vs=[];uv=[];fs=[];nx=40;ny=20
    for j in range(ny+1):
        for i in range(nx+1):vs.append(roof(i/nx,j/ny));uv.append((i/nx,j/ny))
    for j in range(ny):
        for i in range(nx):q=j*(nx+1)+i;fs.append((q,q+1,q+nx+2,q+nx+1))
    o=mesh('Replaceable sloping canvas roof',vs,fs,canopy,uv);o.modifiers.new('Canvas thickness','SOLIDIFY').thickness=.002
    for p in o.data.polygons:p.use_smooth=True
    for side_name,n,count in [(s,n,c) for s,c in [('front',12),('back',12),('left',7),('right',7)] for n in range(c)]:
        outward={'front':Vector((0,-1,0)),'back':Vector((0,1,0)),'left':Vector((-1,0,0)),'right':Vector((1,0,0))}[side_name]
        def panel(u,v):
            t=(n+u)/count
            ru,rv={'front':(t,0),'back':(t,1),'left':(0,t),'right':(1,t)}[side_name]
            top=Vector(roof(ru,rv))
            return top+outward*(.009+.018*math.sin(u*math.pi)*v)-Vector((0,0,v*(.235+cfg['valance_extension_m']+.045*math.sin(math.pi*u))))
        vs=[];uv=[];fs=[]
        for j in range(7):
            for i in range(7):vs.append(panel(i/6,j/6));uv.append((i/6,j/6))
        for j in range(6):
            for i in range(6):q=j*7+i;fs.append((q,q+7,q+8,q+1))
        o=mesh('Cloth scalloped valance '+side_name,vs,fs,canopy,uv);o['side']=side_name;o.modifiers.new('Thin hem','SOLIDIFY').thickness=.002
        for p in o.data.polygons:p.use_smooth=True
        # Ochre binding is sewn into each narrow drooping lobe, as in the reference.
        for edge in [0,1,2]:
            vs=[];fs=[]
            for k in range(13):
                t=k/12
                for s in [0,1]:
                    u,v=((.035+s*.055,.035+t*.91) if edge==0 else ((.91+s*.055,.035+t*.91) if edge==1 else (.035+t*.93,.91+s*.055)))
                    co=Vector(panel(u,v))+outward*.0025;vs.append(co)
            for k in range(12):fs.append((2*k,2*k+2,2*k+3,2*k+1))
            mesh('Sewn ochre binding',vs,fs,gold)
    for x in [-w/2+.11,w/2-.11]:
        for y,z in [(front,hf),(back,hb)]:
            cord('Canvas corner lashing',[P(x+.038*math.cos(t*math.tau/16),y+.038*math.sin(t*math.tau/16),z-.04-t*.002) for t in range(33)],.005)
    # Display crates are separate from the structure and can be replaced later.
    before_contents=set(bpy.context.scene.objects)
    for n in range(3):
        cx=-.88+n*.86;cy=-.45;z=1.06
        box('Produce tray base',P(cx,cy,z),(.78,.55,.045))
        for y in [cy-.275,cy+.275]:box('Tray lip',P(cx,y,z+.075),(.80,.023,.15))
        for x in [cx-.39,cx+.39]:box('Tray side',P(x,cy,z+.075),(.025,.55,.15))
        for a in range(5):
            for b in range(3):fruit(P(cx-.28+a*.135+random.uniform(-.02,.02),cy-.16+b*.15,z+.08+random.uniform(0,.055)),n)
    basket(P(.75,.10,1.65),.26,.20,.20)
    for x,y in [(.49,.10),(1.01,.10),(.75,-.10)]:cord('Hanging basket rope',[P(x,y,1.85),P(.75,.10,2.58)],.007)
    beam('Basket carrying crossbar',P(-w/2+.11,.10,2.58),P(w/2-.11,.10,2.58),.045)
    for x in [-w/2+.11,w/2-.11]:cord('Crossbar suspension tie',[P(x,.10,2.58),P(x,.10,hf+(hb-hf)*(.10-front)/depth-.055)],.008)
    for k in range(9):fruit(P(.75+random.uniform(-.17,.17),.10+random.uniform(-.12,.12),1.82),0)
    for k in range(3):
        x=-.85+k*.21;cord('Herb suspension',[P(x,.1,2.58),P(x,.1,1.82)],.005)
        for j in range(15):
            z=2.25-j*.025;ang=j*2.4;center=Vector(P(x,.1,z));tip=center+Vector((math.cos(ang)*.12,math.sin(ang)*.08,-.045))
            mesh('Dried hanging herb leaves',[center,center.lerp(tip,.55)+Vector((.025,.02,0)),tip,center.lerp(tip,.55)-Vector((.025,.02,0))],[(0,1,2,3)],leaf)
    if variant['contents']!='produce':
        for obj in set(bpy.context.scene.objects)-before_contents:bpy.data.objects.remove(obj,do_unlink=True)
    if variant['contents']=='pottery':
        ceramic=mat('Unglazed earthenware '+str(idx),(.40,.19,.085))
        for n in range(7):
            cx=-1.1+n*.36;cy=-.46+random.uniform(-.08,.08);h=random.uniform(.20,.37);r=random.uniform(.095,.14)
            profile=[(0,0),(.75,.02),(1,.28),(.96,.65),(.62,.88),(.60,1),(.48,1),(.49,.86),(.82,.60),(.85,.28),(.62,.10),(0,.10)]
            vs=[];fs=[]
            for radius,z in profile:
                for j in range(24):a=j*math.tau/24;vs.append(P(cx+radius*r*math.cos(a),cy+radius*r*math.sin(a),1.01+z*h))
            for row in range(len(profile)-1):
                for j in range(24):fs.append((row*24+j,row*24+(j+1)%24,(row+1)*24+(j+1)%24,(row+1)*24+j))
            pot=mesh('Replaceable open pottery',vs,fs,ceramic)
            for p in pot.data.polygons:p.use_smooth=True
    if variant['contents']=='potions':
        cork=mat('Bottle cork',(.26,.13,.055));label=mat('Potion parchment labels',(.72,.61,.37))
        glass=[]
        for name,color in [('Emerald',(.035,.38,.19)),('Amethyst',(.28,.055,.43)),('Amber',(.52,.22,.018))]:
            m=mat(name+' alchemist glass',color);p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.18;p.inputs['Transmission Weight'].default_value=.35;p.inputs['IOR'].default_value=1.46;glass.append(m)
        for level,(y,z) in enumerate([(-.61,1.04),(-.24,1.25)]):
            box('Potion display shelf',P(0,y,z-.025),(2.45,.30,.05))
            if level:
                for x in [-1.08,1.08]:box('Shelf feet',P(x,y,1.13),(.065,.23,.22))
            for n in range(8):
                x=-1.04+n*.295;h=random.uniform(.20,.31);r=random.uniform(.062,.087)
                profile=[(0,0),(.8,0),(1,.12),(1,.53),(.6,.70),(.35,.77),(.35,.94),(.45,.94),(.45,1),(.25,1),(.25,.77),(.50,.67),(.84,.5),(.84,.14),(0,.10)]
                vs=[];fs=[]
                for radius,zz in profile:
                    for j in range(20):a=j*math.tau/20;vs.append(P(x+radius*r*math.cos(a),y+radius*r*math.sin(a),z+zz*h))
                for row in range(len(profile)-1):
                    for j in range(20):fs.append((row*20+j,row*20+(j+1)%20,(row+1)*20+(j+1)%20,(row+1)*20+j))
                bottle=mesh('Replaceable potion bottle',vs,fs,glass[n%3])
                for p in bottle.data.polygons:p.use_smooth=True
                bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r*.28,depth=.035,location=P(x,y,z+h+.009));bpy.context.object.data.materials.append(cork);bpy.context.object.name='Bottle stopper'
                box('Bottle paper label',P(x,y-r-.002,z+h*.38),(r*1.0,.003,h*.23),label)
    if variant['contents']=='scrolls':
        paper=mat('Aged parchment',(.68,.53,.29));ink=mat('Faded charcoal ink',(.095,.065,.036));binding=mat('Red scroll cords',(.29,.025,.015))
        for n in range(9):
            x=-1.05+(n%5)*.26;y=-.39+(n//5)*.19;z=1.06+(n//5)*.07
            bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=.048,depth=.30,location=P(x,y,z),rotation=(math.pi/2,0,0));o=bpy.context.object;o.name='Replaceable parchment roll';o.data.materials.append(paper)
            for end in [-1,1]:
                pts=[]
                for j in range(65):
                    t=j/64;a=t*math.tau*2.8;r=.046*(1-t)+.009;pts.append(P(x+r*math.cos(a),y+end*.151,z+r*math.sin(a)))
                cord('Rolled parchment spiral',pts,.0016,ink)
            cord('Scroll binding',[P(x+.050*math.cos(j*math.tau/24),y,z+.050*math.sin(j*math.tau/24)) for j in range(25)],.006,binding)
        vs=[];fs=[]
        for j in range(21):
            v=j/20
            for i in range(13):u=i/12;vs.append(P(.25+u*.77,-.75+v*.57,1.025+.055*(abs(v-.5)*2)**8))
        for j in range(20):
            for i in range(12):q=j*13+i;fs.append((q,q+1,q+14,q+13))
        mesh('Unfurled sample parchment',vs,fs,paper)
        for j in range(9):
            y=-.66+j*.042;cord('Sample manuscript strokes',[P(.34+i*.10,y+.004*math.sin(i*4+j),1.029+.055*(abs((y+.75)/.57-.5)*2)**8) for i in range(6)],.002,ink)
    if variant['contents']=='ores':
        rock=mat('Rough charcoal ore',(.13,.145,.16));copper=mat('Copper mineral veins',(.36,.19,.075));crystal=mat('Blue mineral crystals',(.07,.26,.36))
        crystal.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.33
        for n in range(3):
            cx=-.89+n*.89;cy=-.46
            box('Ore sorting bin base',P(cx,cy,1.04),(.81,.57,.055))
            for y in [cy-.285,cy+.285]:box('Ore sorting bin rim',P(cx,y,1.105),(.82,.026,.15))
            for x in [cx-.405,cx+.405]:box('Ore sorting bin divider',P(x,cy,1.105),(.026,.57,.15))
            for j in range(10):
                x=cx+random.uniform(-.28,.28);y=cy+random.uniform(-.17,.17);z=1.15+random.uniform(0,.065)
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=random.uniform(.065,.115),location=P(x,y,z));o=bpy.context.object;o.name='Replaceable mineral chunk';o.scale=(1,random.uniform(.7,1.2),random.uniform(.7,1.5));o.data.materials.append(rock if n<2 else crystal)
                if n==1:
                    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.040,location=P(x+.035,y-.02,z+.04));bpy.context.object.name='Copper mineral inclusion';bpy.context.object.data.materials.append(copper)
    content_objects=set(bpy.context.scene.objects)-before_contents
    col=bpy.data.collections.new(variant['id']);bpy.context.scene.collection.children.link(col)
    contents=bpy.data.collections.new(variant['id']+'_CONTENTS');col.children.link(contents);contents['preset']=variant['contents']
    for o in set(bpy.context.scene.objects)-start:
        for c in list(o.users_collection):c.objects.unlink(o)
        (contents if o in content_objects else col).objects.link(o)
    for n in range(3):
        slot=bpy.data.objects.new('DISPLAY_SLOT_'+str(idx)+'_'+str(n),None);col.objects.link(slot);slot.location=P(-.88+n*.86,-.45,1.01);slot.empty_display_size=.07;slot['purpose']='replaceable contents; origin at countertop'
    col['width_m']=w;col['roof_depth_m']=depth;col['front_valance_clearance_m']=hf+.022-(.28+cfg['valance_extension_m']);col['contents_preset']=variant['contents']
scene=bpy.context.scene
box('Review ground',(0,0,-.09),(200,200,.15),mat('Warm limestone stage',(.32,.30,.255)))
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.70,.80,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
for loc,power,size in [((-3,-4,8),1800,5),((5,3,7),1600,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(4,-23,9));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.3))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=19;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.view_settings.view_transform='AgX';scene.unit_settings.system='METRIC'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_market_stalls.blend'))
scene.render.filepath=str(OUT/'market_stalls_review.png');bpy.ops.render.render(write_still=True)
for variant in cfg['variants']:bpy.data.collections[variant['id']].hide_render=variant['contents']!='none'
cam.location=(-4.7,-8,3.8);cam.rotation_euler=(Vector((-7.2,0,1.45))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=5.2
scene.render.filepath=str(OUT/'market_stall_detail.png');bpy.ops.render.render(write_still=True)
cam.location=(-4.2,7,4.6);cam.rotation_euler=(Vector((-7.2,0,1.45))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(OUT/'market_stall_rear.png');bpy.ops.render.render(write_still=True)
for idx,variant in enumerate(cfg['variants']):
    if variant['contents'] not in ['potions','scrolls','ores']:continue
    for v in cfg['variants']:bpy.data.collections[v['id']].hide_render=v['id']!=variant['id']
    x=(idx-2)*3.6;cam.location=(x+2,-7,3.7);cam.rotation_euler=(Vector((x,0,1.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.8
    scene.render.filepath=str(OUT/('market_'+variant['contents']+'.png'));bpy.ops.render.render(write_still=True)
print('MARKET_STALLS_COMPLETE')
