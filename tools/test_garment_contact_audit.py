import numpy as np
import audit_garment_contacts as audit
from audit_garment_contacts import winding_inside

# Closed box, including reversed winding, translated/scaled coordinates,
# points just inside/outside a face, and exterior points beside a sharp edge.
v=np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]],dtype=float)
f=np.array([[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],[3,7,6],[3,6,2],[0,4,7],[0,7,3],[1,2,6],[1,6,5]])
p=np.array([[0,0,0],[.999,0,0],[1.001,0,0],[1.1,1.1,0],[-1.1,-1.1,-1.1],[.9,.9,.9]])
expected=np.array([True,True,False,False,False,True])
for scale in [.01,1,100]:
 offset=np.array([3,2,-5]);triangles=(v[f]*scale)+offset;points=p*scale+offset
 assert np.array_equal(winding_inside(points,triangles),expected)
 assert np.array_equal(winding_inside(points,triangles[:,::-1]),expected)
assert winding_inside(np.empty((0,3)),v[f]).size==0
accelerated = audit.igl
audit.igl = None
assert np.array_equal(winding_inside(p,v[f]),expected)
audit.igl = accelerated
print('PASS volume audit: interior/exterior, sharp edges, orientation and scale')
