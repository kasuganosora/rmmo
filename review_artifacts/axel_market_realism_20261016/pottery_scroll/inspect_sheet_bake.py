import bpy, json, sys, numpy as np
from pathlib import Path

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
base=Path(args[0]) if args else Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v3/scroll')
report_path=Path(args[1]) if len(args)>1 else Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/sheet_v3_inspection.json')
out={}
for kind in ['authoring','runtime_baked']:
    path=base/(kind+'.blend')
    if not path.exists() and kind=='authoring':path=base/'authoring_sheet.blend'
    bpy.ops.wm.open_mainfile(filepath=str(path))
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.get('rmmo_export_group')=='PaperSheet' or o.name=='PaperSheet')]
    entries=[]
    for obj in objects:
        e={'name':obj.name,'materials':[m.name for m in obj.data.materials], 'uv_layers':[x.name for x in obj.data.uv_layers], 'upward_materials':{}}
        for face in obj.data.polygons:
            if face.normal.z>.9:e['upward_materials'][str(face.material_index)]=e['upward_materials'].get(str(face.material_index),0)+1
        for m in obj.data.materials:
            for node in m.node_tree.nodes:
                if node.type=='TEX_IMAGE' and node.image:
                    image=node.image;px=np.asarray(image.pixels[:],dtype=np.float32).reshape(image.size[1],image.size[0],4)
                    lum=px[:,:,:3].mean(axis=2)
                    e.setdefault('images',[]).append({'material':m.name,'node':node.name,'image':image.name,'color_space':image.colorspace_settings.name,'min':float(lum.min()),'max':float(lum.max()),'mean':float(lum.mean()),'count_above_point1':int((lum>.1).sum()),'count_dark_nonzero':int(((lum>0)&(lum<.3)).sum())})
        if obj.name=='PaperSheet':
            mat=obj.data.materials[0];tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and 'DIFFUSE' in n.image.name)
            im=tex.image;px=np.asarray(im.pixels[:]).reshape(im.size[1],im.size[0],4)
            samples=[]
            uv=obj.data.uv_layers['GameAtlas']
            for face in obj.data.polygons:
                if face.normal.z>.9:
                    xy=sum((uv.data[li].uv for li in face.loop_indices),start=uv.data[face.loop_start].uv*0)/len(face.loop_indices)
                    x,y=[max(0,min(im.size[i]-1,int(xy[i]*im.size[i]))) for i in range(2)]
                    samples.append(float(np.mean(px[y,x,:3])))
            e['upward_diffuse_centroids']={'min':min(samples),'max':max(samples),'mean':float(np.mean(samples)),'under_point3':sum(v<.3 for v in samples),'count':len(samples)}
        entries.append(e)
    out[kind]=entries
o=bpy.data.objects['PaperSheet']; src=bpy.data.objects['Goods_UnfurledManuscript']
mask=src.data.materials[1].node_tree.nodes['ORIGINAL_INK_MASK'].image; a=np.asarray(mask.pixels[:]).reshape(1024,1024,4)[:,:,0]
im=bpy.data.images['PaperSheet_DIFFUSE']; atlas=np.asarray(im.pixels[:]).reshape(1024,1024,4)[:,:,:3].mean(axis=2)
rows=[]
for f in o.data.polygons:
    if f.normal.z < .9:continue
    indices=list(f.loop_indices)
    uv0=np.asarray([o.data.uv_layers['GameAtlas'].data[li].uv[:] for li in indices])*1024
    uv1=np.asarray([src.data.uv_layers['GoodsUV'].data[li].uv[:] for li in indices])
    for ii in [(0,1,2),(0,2,3)]:
        tri=uv0[list(ii)]; st=uv1[list(ii)]
        xmin,ymin=np.maximum(0,np.floor(tri.min(axis=0))).astype(int);xmax,ymax=np.minimum(1023,np.ceil(tri.max(axis=0))).astype(int)
        yy,xx=np.mgrid[ymin:ymax+1,xmin:xmax+1]; points=np.stack([xx.ravel()+.5,yy.ravel()+.5],axis=1)
        ab=np.linalg.solve((tri[1:]-tri[0]).T,(points-tri[0]).T).T
        inside=(ab.min(axis=1)>=0)&(ab.sum(axis=1)<=1)
        ab=ab[inside]; pixels=points[inside].astype(int)
        uv=st[0]+ab@(st[1:]-st[0]); sample=np.clip((uv*1024).astype(int),0,1023)
        rows.extend(zip(a[sample[:,1],sample[:,0]].tolist(),atlas[pixels[:,1],pixels[:,0]].tolist()))
rows=np.asarray(rows);out['baked_top_expected_mask_correlation']={'count':len(rows),'corr':float(np.corrcoef(rows.T)[0,1]),'bins':[]}
for lo,hi in [(0,.01),(.1,.3),(.3,.5),(.5,1)]:
    values=rows[(rows[:,0]>=lo)&(rows[:,0]<hi),1]
    out['baked_top_expected_mask_correlation']['bins'].append({'mask_range':[lo,hi],'count':len(values),'luminance_mean':float(values.mean()) if len(values) else None,'luminance_min':float(values.min()) if len(values) else None})
report_path.write_text(json.dumps(out,indent=2))
print(json.dumps(out,indent=2),flush=True)
