"""Six head-bound hairstyle variants, shared by adult male/female characters.
Keeps the supplied Artoria front locks where appropriate; authors fitted back
hair, straight fringe and wispy fringe as editable strand surfaces.
"""
import bpy,bmesh,math,os
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
STYLES={10:'ShortFemale',11:'ShortMale',12:'Hime',13:'Long',14:'TiedLong',15:'AiryBob'}
bpy.ops.wm.open_mainfile(filepath=str(art_path('characters/imported/female/editable/character.blend')))
original=bpy.data.objects['Hair']
# Save the source front locks as ordinary Python data before loading each rig.
polys=[p for p in original.data.polygons if (original.matrix_world@p.center).y<.105]
ids=sorted({i for p in polys for i in p.vertices});mapping={i:j for j,i in enumerate(ids)}
front_points=[original.matrix_world@original.data.vertices[i].co for i in ids]
front_faces=[[mapping[i] for i in p.vertices] for p in polys]
front_uvs=[[tuple(original.data.uv_layers.active.data[i].uv) for i in p.loop_indices] for p in polys]

for gender in ['female','male']:
    bpy.ops.wm.open_mainfile(filepath=str(art_path(f'characters/imported/{gender}/editable/character.blend')))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    body=bpy.data.objects['Body'];objects=[]
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for side in ['Left','Right','Back']:
        bone=rig.data.edit_bones.new('HairSecondary'+side)
        bone.matrix=rig.data.edit_bones['mixamorig:Head'].matrix.copy();bone.length=.12
        bone.parent=rig.data.edit_bones['mixamorig:Head'];bone.use_connect=False
    bpy.ops.object.mode_set(mode='OBJECT')
    def point(p):
        p=Vector(p)
        if gender=='male':p.x*=1.035;p.y*=.99;p.z+=.065
        return body.matrix_world.inverted()@p
    def make(name,verts,faces,uv_faces=None,source=False):
        if name.startswith(('Hair_15_','Hair_12_','Hair_10_','Hair_14_','Hair_11_','Hair_13_')):
            verts=[(p[0],p[1],2.15+(p[2]-2.15)*.78 if p[2]>2.15 else p[2]) for p in verts]
        mesh=bpy.data.meshes.new(name);mesh.from_pydata([point(p) for p in verts],[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
        obj.parent=rig;obj.matrix_world=body.matrix_world.copy()
        group=obj.vertex_groups.new(name='mixamorig:Head')
        secondary={s:obj.vertex_groups.new(name='HairSecondary'+s) for s in ['Left','Right','Back']}
        for index,p in enumerate(verts):
            weight=0 if 'Scalp' in name else min(.9,max(0,(2.18-p[2])/.60))**.8
            side='Back' if name.startswith(('Hair_12_LongBack','Hair_13_WaveBack','Hair_14_Gather','Hair_14_Tail','Hair_14_Tie')) else ('Left' if p[0]>.08 else ('Right' if p[0]<-.08 else 'Back'))
            group.add([index],1-weight,'REPLACE')
            if weight>0:secondary[side].add([index],weight,'REPLACE')
        mod=obj.modifiers.new('Shared head bone','ARMATURE');mod.object=rig
        uv=mesh.uv_layers.new(name='UVMap')
        for polygon in mesh.polygons:
            polygon.use_smooth=True
            coords=uv_faces[polygon.index] if uv_faces else [(0,0),(1,0),(1,1),(0,1)]
            for i,coord in zip(polygon.loop_indices,coords):uv.data[i].uv=coord
        if name.startswith(('Hair_15_','Hair_12_','Hair_10_','Hair_14_','Hair_11_','Hair_13_')):
            gradient=mesh.uv_layers.new(name='HairHeight')
            for polygon in mesh.polygons:
                for loop in polygon.loop_indices:
                    z=verts[mesh.loops[loop].vertex_index][2]
                    gradient.data[loop].uv=(max(0,min(1,(2.37-z)/(1.18 if name.startswith('Hair_13_') else .78 if name.startswith('Hair_14_') else (.69 if name.startswith('Hair_12_') else .43)))),0)
        if source:
            mat=bpy.data.objects['Hair'].data.materials[0].copy()
        else:
            mat=bpy.data.materials.new(name+' strand tone');mat.use_nodes=True
            nodes=mat.node_tree.nodes;nodes.clear()
            output=nodes.new('ShaderNodeOutputMaterial');emission=nodes.new('ShaderNodeEmission')
            emission.inputs['Color'].default_value=(.37,.245,.135,1) if gender=='male' else (.88,.69,.43,1)
            mat.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
            mat.use_backface_culling=False
        mesh.materials.append(mat);objects.append(obj)
        return obj
    def sheet(name,rows):
        verts=[];faces=[];uvs=[];width=len(rows[0])
        for row in rows:verts.extend(row)
        for i in range(len(rows)-1):
            for j in range(width-1):
                a=i*width+j;faces.append((a,a+1,a+1+width,a+width))
                uvs.append([(j/(width-1),i/(len(rows)-1)),((j+1)/(width-1),i/(len(rows)-1)),((j+1)/(width-1),(i+1)/(len(rows)-1)),(j/(width-1),(i+1)/(len(rows)-1))])
        return make(name,verts,faces,uvs)
    for style,label in STYLES.items():
        prefix=f'Hair_{style}_'
        # Fitted scalp shell, open over the face.
        rows=[]
        for i in range(17):
            t=max(.001,i/16)
            row=[]
            for j in range(65):
                angle=j/64*math.tau
                front=max(0,-math.cos(angle))
                end=2.03-.9*front**3
                polar=t*end
                row.append(((.167 if style==11 else (.178 if style in [10,12,13,14,15] else .194))*math.sin(polar)*math.sin(angle),.025+(.174+.038*front if style in [10,11,12,13,14,15] else .174)*math.sin(polar)*math.cos(angle),2.21+(.197 if style==11 else (.22 if style in [10,12,13,14,15] else .205))*math.cos(polar)))
            rows.append(row)
        sheet(prefix+'Scalp',rows)
        if style==11:
            # Continuous rear coverage; only the last few millimetres form wisps.
            rows=[]
            for i in range(33):
                t=i/32;row=[]
                for j in range(65):
                    angle=-1.9+j/64*3.8
                    end=2.62-.30*(abs(angle)/1.9)**2
                    polar=.55+(end-.55)*t
                    row.append((.184*math.sin(polar)*math.sin(angle),.022+.184*math.sin(polar)*math.cos(angle),2.21+.226*math.cos(polar)+.002*math.sin(j*1.9)*t**12))
                rows.append(row)
            sheet(prefix+'NapeCoverage',rows)
            # Overlapping nape locks continue below the backing to the neck line.
            # Only their free tips separate; no straight hem and no exposed scalp.
            for lock in range(28):
                angle=-1.7+(lock+.5)*3.4/28;rows=[]
                for i in range(29):
                    t=i/28
                    z=2.14-.18*t+.035*(abs(angle)/1.7)**2*t+.008*math.sin(lock*2.3)*t**5
                    rx=.176-.065*t;ry=.17-.060*t
                    taper=1-.97*max(0,(t-.73)/.27)
                    row=[]
                    for j in range(5):
                        theta=angle+(j/4-.5)*3.4/28*1.24*taper+.028*math.sin(lock*1.7)*t*t
                        row.append((rx*math.sin(theta),.023+ry*math.cos(theta),z))
                    rows.append(row)
                sheet(prefix+'NapeWisp%02d'%lock,rows)
            # Short, swept, staggered layers over the continuous rear surface.
            for layer,count in [(0,40),(1,32),(2,22)]:
                for lock in range(count):
                    angle=lock/count*math.tau+layer*.097;rows=[]
                    front=max(0,-math.cos(angle))
                    end=2.32-.47*front-.16*layer+.085*math.sin(lock*2.3+layer)
                    for i in range(29):
                        t=i/28;polar=.045+(end-.045)*t
                        sweep=.28*math.sin(t*math.pi)*(.4+math.sin(angle+.7))
                        taper=1-.96*max(0,(t-(.94 if layer==0 and front<.35 else .76))/(.06 if layer==0 and front<.35 else .24))
                        row=[]
                        for j in range(7):
                            theta=angle+sweep+(j/6-.5)*math.tau/count*(1.18 if layer==0 else .85)*taper
                            lift=(.011+layer*.009)*math.sin(t*math.pi)+.008*math.sin(lock*1.7)*t**4
                            rx=.184+lift;ry=.182+lift
                            x=rx*math.sin(polar)*math.sin(theta)
                            y=.022+ry*math.sin(polar)*math.cos(theta)
                            z=2.21+(.226+lift)*math.cos(polar)
                            # Front locks sweep across the forehead, with uneven fine ends.
                            if front>.5:x+=.024*front*t*t
                            row.append((x,y,z))
                        rows.append(row)
                    sheet(prefix+'Layer%d_%02d'%(layer,lock),rows)
            continue
        if style==13:
            # Loose waves, uninterrupted crown coverage and staggered free ends.
            profile=[(2.415,.012,.012),(2.37,.105,.115),(2.27,.179,.174),(2.10,.183,.19),
                     (1.94,.202,.231),(1.79,.234,.255),(1.66,.226,.25),(1.56,.226,.25),(1.52,.180,.225)]
            def wcurve(t):
                u=t*(len(profile)-1);k=min(len(profile)-2,int(u));f=u-k
                a=Vector(profile[max(0,k-1)]);b=Vector(profile[k]);c=Vector(profile[k+1]);d=Vector(profile[min(len(profile)-1,k+2)])
                return .5*(2*b+(-a+c)*f+(2*a-5*b+4*c-d)*f*f+(-a+3*b-3*c+d)*f*f*f)
            for lock in range(40):
                angle=-1.95+(lock+.5)*3.9/40;rows=[]
                for i in range(65):
                    # Trim the lateral curtain above the shoulder; keep the back long.
                    cut=max(0,min(1,(abs(angle)-1.22)/.28))
                    cut=cut*cut*(3-2*cut)
                    u=i/64;t=u*(1-.52*cut);z,rx,ry=wcurve(t)
                    wave=.055*math.sin(t*math.pi*5+angle*.4)*max(0,(t-.22)/.78)
                    taper=1-(.92-.40*cut)*max(0,(u-.94)/.06)
                    row=[]
                    for j in range(7):
                        theta=angle+(j/6-.5)*3.9/40*1.24*taper
                        ridge=.002*math.sin(j/6*math.pi)*math.sin(t*math.pi)
                        row.append(((rx+wave+ridge)*math.sin(theta),.025+(ry+wave+ridge)*math.cos(theta),z+.015*math.sin(lock*1.9)*t**7))
                    rows.append(row)
                sheet(prefix+'WaveBack%02d'%lock,rows)
            for lock in range(24):
                center=(lock-11.5)*.0111;rows=[]
                for i in range(29):
                    t=i/28
                    z=2.425-.238*t+(.008*math.sin(lock*2.7)+.007*math.sin(lock*.85))*t**5
                    y=.005-.199*math.sqrt(max(0,1-((z-2.21)/.22)**2))
                    if style==13:z+=.025*math.sin((center+.03)*18)*t**3
                    width=.0113*(.16+.84*math.sin(t*math.pi/2))
                    taper=1-.94*max(0,(t-.83)/.17)
                    row=[]
                    for j in range(5):
                        x=center*(.16+.84*math.sin(t*math.pi/2))+(j/4-.5)*width*taper+.004*math.sin(lock*1.7)*t**3
                        if style==13:x+=.035*math.sin(t*math.pi/2)*t
                        y=.025-.215*math.sqrt(max(0,1-(x/.222)**2-((z-2.21)/.23)**2))
                        # Front is -Y: curl the free ends back toward the forehead.
                        curl=max(0,(t-.58)/.42)
                        y+=.027*curl*curl
                        row.append((x,y-.0005*math.sin(j/4*math.pi),z))
                    rows.append(row)
                sheet(prefix+'Fringe%02d'%lock,rows)
            continue
        if style in [12,14]:
            # Hime: shoulder-blade back hair and short cheek cuts; no chest panels.
            profile=[(2.415,.012,.012),(2.37,.105,.115),(2.27,.177,.174),(2.12,.182,.185),
                     (1.98,.179,.205),(1.83,.192,.245),(1.72,.186,.244),(1.68,.168,.227),(1.70,.145,.215)]
            def hcurve(t):
                u=t*(len(profile)-1);k=min(len(profile)-2,int(u));f=u-k
                a=Vector(profile[max(0,k-1)]);b=Vector(profile[k]);c=Vector(profile[k+1]);d=Vector(profile[min(len(profile)-1,k+2)])
                return .5*(2*b+(-a+c)*f+(2*a-5*b+4*c-d)*f*f+(-a+3*b-3*c+d)*f*f*f)
            if style==12:
                for lock in range(38):
                    angle=-1.72+(lock+.5)*3.44/38;rows=[]
                    for i in range(49):
                        t=i/48;z,rx,ry=hcurve(t);tip=max(0,(t-.89)/.11)
                        row=[]
                        for j in range(5):
                            theta=angle+(j/4-.5)*3.44/38*1.17*(1-.7*tip)
                            ridge=.001*math.sin(j/4*math.pi)
                            row.append(((rx+ridge)*math.sin(theta),.025+(ry+ridge)*math.cos(theta),z+.018*math.sin(lock*1.9)*t**8))
                        rows.append(row)
                    sheet(prefix+'LongBack%02d'%lock,rows)
            else:
                # Low gathered hair: crown locks converge onto one elastic band.
                for lock in range(32):
                    angle=-1.95+(lock+.5)*3.9/32;rows=[]
                    for i in range(33):
                        t=i/32;z=2.415-.40*t
                        rx=.012+.175*math.sin(min(1,t*1.8)*math.pi/2)
                        ry=.012+.17*math.sin(min(1,t*1.8)*math.pi/2)
                        gather=max(0,(t-.45)/.55)**2
                        row=[]
                        for j in range(5):
                            theta=angle+(j/4-.5)*3.9/32*1.15
                            x=(rx*(1-gather)+.038*gather)*math.sin(theta)
                            y=(.025+ry*math.cos(theta))*(1-gather)+(.245+.038*math.cos(theta))*gather
                            row.append((x,y,z))
                        rows.append(row)
                    sheet(prefix+'Gather%02d'%lock,rows)
                for lock in range(24):
                    angle=lock/24*math.tau;rows=[]
                    for i in range(37):
                        t=i/36;radius=.038+.03*math.sin(t*math.pi)-.030*t**4
                        center_y=.245+.07*math.sin(t*math.pi*.7)
                        row=[]
                        for j in range(5):
                            theta=angle+(j/4-.5)*math.tau/24*1.12
                            row.append((radius*math.sin(theta),center_y+radius*math.cos(theta),2.025-.43*t+.012*math.sin(lock*2.2)*t**7))
                        rows.append(row)
                    sheet(prefix+'Tail%02d'%lock,rows)
                rows=[]
                for i in range(5):
                    rows.append([((.042+.002*math.sin(i/4*math.pi))*math.sin(j/48*math.tau),.245+(.042+.002*math.sin(i/4*math.pi))*math.cos(j/48*math.tau),2.005+i*.006) for j in range(49)])
                sheet(prefix+'Tie',rows)
            for sign in [-1,1]:
                rows=[]
                for i in range(33):
                    t=i/32;curl=max(0,(t-.68)/.32)
                    z=2.37-.365*t
                    radius=.10+.075*math.sin(t*math.pi/2)-.043*curl**2
                    row=[]
                    for j in range(29):
                        u=j/28;theta=2.03+u*.43
                        x=sign*radius*math.sin(theta)
                        y=.005+radius*math.cos(theta)-.055*math.sin(t*math.pi/2)
                        row.append((x,y,z+(.006*math.sin(u*29)+.003*math.sin(u*11))*t**6))
                    rows.append(row)
                sheet(prefix+'Cheek'+str(sign),rows)
            for lock in range(24):
                center=(lock-11.5)*.0111;rows=[]
                for i in range(29):
                    t=i/28
                    z=2.425-.238*t+(.008*math.sin(lock*2.7)+.007*math.sin(lock*.85))*t**5
                    y=.005-.199*math.sqrt(max(0,1-((z-2.21)/.22)**2))
                    if style==14:z+=.018*math.sin((center+.03)*18)*t**3
                    width=.0113*(.16+.84*math.sin(t*math.pi/2))
                    taper=1-.94*max(0,(t-.83)/.17)
                    row=[]
                    for j in range(5):
                        x=center*(.16+.84*math.sin(t*math.pi/2))+(j/4-.5)*width*taper+.004*math.sin(lock*1.7)*t**3
                        if style==14:x+=.025*math.sin(t*math.pi/2)*t
                        y=.025-.215*math.sqrt(max(0,1-(x/.222)**2-((z-2.21)/.23)**2))
                        # Front is -Y: curl the free ends back toward the forehead.
                        curl=max(0,(t-.58)/.42)
                        y+=.027*curl*curl
                        row.append((x,y-.0005*math.sin(j/4*math.pi),z))
                    rows.append(row)
                sheet(prefix+'Fringe%02d'%lock,rows)
            continue
        if style in [10,15]:
            # Reference bob: crown volume, cheek curtains and rounded undercurl.
            # Hair only: no ornaments, clips, ribbons or headband geometry.
            profile=[(2.415,.012,.012),(2.37,.105,.115),(2.27,.177,.174),
                     (2.12,.182,.185),(2.00,.164,.175),(1.940,.132,.139),(1.982,.094,.091)]
            if style==10:
                profile=[(2.415,.012,.012),(2.37,.105,.115),(2.27,.177,.174),
                         (2.12,.180,.181),(2.00,.158,.165),(1.95,.139,.14),(1.93,.113,.119)]
            def curve(t):
                u=t*(len(profile)-1);k=min(len(profile)-2,int(u));f=u-k
                a=Vector(profile[max(0,k-1)]);b=Vector(profile[k]);c=Vector(profile[k+1]);d=Vector(profile[min(len(profile)-1,k+2)])
                return .5*((2*b)+(-a+c)*f+(2*a-5*b+4*c-d)*f*f+(-a+3*b-3*c+d)*f*f*f)
            for lock in range(40):
                angle=-2.45+(lock+.5)*4.9/40;rows=[]
                for i in range(41):
                    t=i/40;z,rx,ry=curve(t)
                    if style==10:z+=.065*math.cos(angle)*t**3
                    taper=1-.90*max(0,(t-.88)/.12) if style==10 else 1-.68*max(0,(t-.94)/.06)
                    row=[]
                    for j in range(7):
                        theta=angle+(j/6-.5)*(4.9/40)*1.23*taper
                        ridge=.0008*math.sin(j/6*math.pi)*math.sin(t*math.pi)
                        # Cheek locks sweep inward below the jaw, leaving the face open.
                        row.append(((rx+ridge)*math.sin(theta),.025+(ry+ridge)*math.cos(theta),z+(.006 if style==10 else .017)*math.sin(lock*2.4)*t**5))
                    rows.append(row)
                sheet(prefix+'BobCurtain%02d'%lock,rows)
            # Unequal overlay locks separate the silhouette into soft, curled layers.
            for lock in range(19):
                angle=-2.45+(lock+.5)*4.9/19;rows=[]
                for i in range(37):
                    t=i/36;z,rx,ry=curve(t)
                    if style==10:z+=.065*math.cos(angle)*t**3
                    lift=.003*math.sin(t*math.pi)**2
                    shorten=(.014+.014*(.5+.5*math.sin(lock*2.1)))*t**3
                    curl=max(0,(t-.70)/.30)
                    rx+=lift-.017*curl;ry+=lift-.015*curl
                    width=(4.9/19)*.62*(1-.86*max(0,(t-.80)/.20))
                    row=[]
                    for j in range(9):
                        theta=angle+(j/8-.5)*width+.07*math.sin(t*math.pi)*(1 if lock%2 else -1)
                        bulge=.001*math.sin(j/8*math.pi)*math.sin(t*math.pi)
                        row.append(((rx+bulge)*math.sin(theta),.025+(ry+bulge)*math.cos(theta),z+shorten))
                    rows.append(row)
                sheet(prefix+'BobLayer%02d'%lock,rows)
            for lock in range(24):
                center=(lock-11.5)*.0111;rows=[]
                for i in range(29):
                    t=i/28
                    z=2.425-(.249 if style==10 else .238)*t+(.008*math.sin(lock*2.7)+.007*math.sin(lock*.85))*t**5
                    y=.005-.199*math.sqrt(max(0,1-((z-2.21)/.22)**2))
                    width=.0113*(.16+.84*math.sin(t*math.pi/2))
                    taper=1-(.82 if style==10 else .94)*max(0,(t-(.9 if style==10 else .83))/(.10 if style==10 else .17))
                    row=[]
                    for j in range(5):
                        x=center*(.16+.84*math.sin(t*math.pi/2))+(j/4-.5)*width*taper+.004*math.sin(lock*1.7)*t**3
                        y=.025-.215*math.sqrt(max(0,1-(x/.222)**2-((z-2.21)/.23)**2))
                        # Front is -Y: curl the free ends back toward the forehead.
                        curl=max(0,(t-.58)/.42)
                        y+=.027*curl*curl
                        row.append((x,y-.0005*math.sin(j/4*math.pi),z))
                    rows.append(row)
                sheet(prefix+'BobFringe%02d'%lock,rows)
            continue
        # Separate, overlapping locks give shaped ends and a combed direction.
        bottom={10:2.085,11:2.15,12:1.48,13:1.40,14:2.08,15:2.015}[style]
        count=18 if style!=11 else 22
        for lock in range(count):
            angle=-1.65+(lock+.5)*3.3/count
            rows=[]
            for i in range(17):
                t=i/16;z=2.36+(bottom-2.36)*t
                depth=.13+.055*math.sin(min(1,t*2)*math.pi/2)+max(0,2.0-z)*.09
                radius=.10+.085*math.sin(min(1,t*2)*math.pi/2)
                # Keep every descending lock outside the skull, even on long cuts.
                skull=math.sqrt(max(0,1-((z-2.21)/.205)**2))
                radius=max(radius,.200*skull+.006)
                depth=max(depth,.180*skull+.006)
                if style in [10,15]:radius-=.028*max(0,(t-.65)/.35)
                taper=1 if style in [10,11,12,13,14,15] else max(.05,1-max(0,(t-.83)/.17)*.92)
                row=[]
                for j in range(5):
                    theta=angle+(j/4-.5)*(3.3/count)*1.16*taper
                    bulge=.007*math.sin(j/4*math.pi)
                    row.append(((radius+bulge)*math.sin(theta),.025+(depth+bulge)*math.cos(theta),z+.018*math.sin(lock*2.3)*t**6))
                rows.append(row)
            sheet(prefix+'Back%02d'%lock,rows)
        if style not in [12,15]:
            verts=[]
            for p in front_points:
                p=p.copy()
                if style==11 and p.z<2.16:p.z=2.16-(2.16-p.z)*.36
                elif style==10 and p.z<2.10:p.z=2.10-(2.10-p.z)*.55
                verts.append(p)
            make(prefix+'Front',verts,front_faces,front_uvs,True)
        else:
            # Hime: level fringe. Airy bob: narrow separated curved wisps.
            count=7 if style==12 else 6
            for lock in range(count):
                center=(lock-(count-1)/2)*(.038 if style==12 else .041)
                width=.042 if style==12 else .020
                rows=[]
                for i in range(13):
                    t=i/12
                    z=2.35-(.205 if style==12 else .215)*t
                    y=-.06-.118*math.sin(t*math.pi/2)
                    taper=1 if style==12 else max(.10,1-t**3)
                    rows.append([(center+(j/4-.5)*width*taper+.012*math.sin(t*math.pi),y-.008*math.sin(j/4*math.pi),z) for j in range(5)])
                sheet(prefix+'Fringe%02d'%lock,rows)
        if style==12:
            for sign in [-1,1]:
                rows=[]
                for i in range(14):
                    t=i/13
                    rows.append([(sign*(.142+j/4*.045),-.105-.02*math.sin(t*math.pi),2.27-.30*t) for j in range(5)])
                sheet(prefix+'Side'+str(sign),rows)
        if style==14:
            # Bound long hair: a gathered low ponytail, with a visible tie.
            for lock in range(12):
                angle=lock/12*math.tau;rows=[]
                for i in range(21):
                    t=i/20
                    radius=.035+.05*math.sin(t*math.pi)-.025*t
                    rows.append([((radius+.004*math.sin(j/4*math.pi))*math.sin(angle+(j/4-.5)*.57),.20+.12*math.sin(t*math.pi*.85)+radius*math.cos(angle+(j/4-.5)*.57),2.18-.75*t) for j in range(5)])
                sheet(prefix+'Tail%02d'%lock,rows)
            rows=[]
            for i in range(2):
                rows.append([(.043*math.sin(j/32*math.tau),.225+.043*math.cos(j/32*math.tau),2.155+i*.025) for j in range(33)])
            tie=sheet(prefix+'Tie',rows)
            emission=next(n for n in tie.data.materials[0].node_tree.nodes if n.type=='EMISSION');emission.inputs['Color'].default_value=(.025,.02,.025,1)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for obj in objects:obj.select_set(True)
    out=art_path(f'characters/hair/{gender}');out.mkdir(parents=True,exist_ok=True)
    (out/'editable').mkdir(exist_ok=True);(out/'editable/.gdignore').touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'editable/hairstyles.blend'))
    bpy.ops.export_scene.gltf(filepath=str(out/'hairstyles.glb'),export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
    (out/'SOURCE.txt').write_text('Adapted Artoria front locks plus authored scalp, back strands, hime fringe, airy fringe and tied tail. Uses the same source terms as the supplied base character.\n',encoding='utf-8')
    print('HAIRSTYLES_EXPORTED',gender,flush=True)
