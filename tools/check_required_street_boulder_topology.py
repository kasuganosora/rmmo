"""Check actual exported boulder crowns for folded faces and overlapping tops."""
import json,hashlib
from pathlib import Path
import numpy as np
import audit_required_street_assets as gl

def main():
    root=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2')
    results=[];single_geometry=[]
    for name in 'abcd':
        path=root/'models'/('s12_water_step_'+name+'.glb');doc,binary=gl.glb(path)
        prim=doc['meshes'][0]['primitives'][0]
        positions=gl.accessor(doc,binary,prim['attributes']['POSITION']).astype('float64')
        tri=positions[gl.accessor(doc,binary,prim['indices']).ravel().reshape(-1,3)]
        single_geometry.append(tri)
        normals=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);area=np.linalg.norm(normals,axis=1)
        crown=tri[:,:,1].min(1)>.57
        upper=tri[normals[:,1]>1e-8]
        aa=upper[:,0][:,[0,2]];bb=upper[:,1][:,[0,2]];cc=upper[:,2][:,[0,2]]
        v0=bb-aa;v1=cc-aa;den=v0[:,0]*v1[:,1]-v1[:,0]*v0[:,1]
        multiple=[];max_delta=0.
        for x in np.linspace(-.59,.59,61):
            for z in np.linspace(-.44,.44,61):
                v2=np.array([x,z])-aa
                u=(v2[:,0]*v1[:,1]-v1[:,0]*v2[:,1])/den
                v=(v0[:,0]*v2[:,1]-v2[:,0]*v0[:,1])/den
                mask=(u>=-1e-8)&(v>=-1e-8)&(u+v<=1.00000001)
                h=upper[:,0,1]+u*(upper[:,1,1]-upper[:,0,1])+v*(upper[:,2,1]-upper[:,0,1])
                hit=h[mask]
                if len(hit)>1:
                    delta=float(np.ptp(hit));max_delta=max(max_delta,delta)
                    if delta>1e-5:multiple.append([float(x),float(z),hit.tolist()])
        record={'id':'s12_water_step_'+name,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                'zero_area_triangles':int((area<1e-9).sum()),'crown_downward_triangles':int(((normals[:,1]<-1e-8)&crown).sum()),
                'vertical_samples':61*61,'multiple_upward_intersections':multiple,'maximum_shared_edge_height_delta_m':max_delta}
        record['passed']=record['zero_area_triangles']==0 and record['crown_downward_triangles']==0 and not multiple
        results.append(record)
    combo=root/'models/s12_water_steps_four.glb';doc,binary=gl.glb(combo)
    identical=[]
    for number,mesh in enumerate(doc['meshes']):
        primitive=mesh['primitives'][0]
        pos=gl.accessor(doc,binary,primitive['attributes']['POSITION']).astype('float64')
        tri=pos[gl.accessor(doc,binary,primitive['indices']).ravel().reshape(-1,3)]
        identical.append(bool(np.array_equal(tri,single_geometry[number])))
    results.append({'id':'s12_water_steps_four','source_sha256':hashlib.sha256(combo.read_bytes()).hexdigest(),
                    'component_local_triangle_geometry_exact_to_individually_checked_sources':identical,
                    'passed':len(identical)==4 and all(identical)})
    (root/'ordered_boulders_v3_topology.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(json.dumps(results))
    assert all(r['passed'] for r in results)

if __name__=='__main__':main()
