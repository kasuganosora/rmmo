#[compute]
#version 450
// RMMO experimental continuous self contact. Reuses the moving-triangle
// predicate from cloth_collide_triangles.glsl, but reads immutable cloth data.
// Experimental vertex/face and separate edge/edge projection. This is not a
// guarantee of untangling or convergence under conflicting body contacts.
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer Previous {vec4 positions[];};
layout(set=0,binding=1,std430) buffer Output {vec4 predicted[];};
layout(set=0,binding=2,std430) readonly buffer Snapshot {vec4 snapshot[];};
layout(set=0,binding=3,std430) readonly buffer Faces {uint indices[];};
layout(set=0,binding=5,std430) readonly buffer Weights {vec4 cloth_weights[];};
layout(set=0,binding=6,std430) readonly buffer Rest {vec4 rest_positions[];};
layout(set=0,binding=7,std430) readonly buffer Counts {uint neighbor_counts[];};
layout(set=0,binding=8,std430) readonly buffer Offsets {uint neighbor_offsets[];};
layout(set=0,binding=9,std430) readonly buffer Neighbors {uint neighbors[];};
layout(set=0,binding=10,std430) readonly buffer UniqueEdges {uvec2 edge_ids[];};
// One contact owned by each point. A later dispatch gathers the four reactions
// without racing float writes to shared triangle vertices.
layout(set=0,binding=11,std430) buffer Reactions {vec4 reactions[];};
layout(set=0,binding=12,std430) readonly buffer BodyDirections {vec4 body_directions[];};
layout(push_constant,std430) uniform Params {
 uint particle_count;uint tri_count;float thickness;float friction;
 uint body_tangents;uint mass_balance;uint edge_phase;uint edge_count;
};
// One-sided projection: self contact may move outward or slide along an active
// body constraint, but must not undo its separating correction. Two directions
// retain reverse face and forward point contacts separately. Experimental local
// contact approximation; not a complete persistent manifold for curved bodies.
vec3 body_safe(uint idx,vec3 direction){
 if(body_tangents==0u)return direction;
 vec3 n0=body_directions[idx*2u].xyz,n1=body_directions[idx*2u+1u].xyz;
 float d0=dot(direction,n0),d1=dot(direction,n1);
 if(d0>=0.0&&d1>=0.0)return direction;
 // Exact projection onto two homogeneous half-spaces. Alternating a fixed
 // number of plane projections leaked through narrow/obtuse contact wedges.
 vec3 p0=direction-n0*min(d0,0.0);
 if(dot(p0,n1)>=0.0)return p0;
 vec3 p1=direction-n1*min(d1,0.0);
 if(dot(p1,n0)>=0.0)return p1;
 vec3 axis=cross(n0,n1);float nn=dot(axis,axis);
 if(nn>1e-12)return axis*(dot(direction,axis)/nn);
 // Opposite coincident normals leave only their common tangent plane.
 return direction-n0*d0;
}
vec3 closest_point_on_triangle(vec3 p, vec3 a, vec3 b, vec3 c) {
    vec3 ab = b - a;
    vec3 ac = c - a;
    vec3 ap = p - a;
    float d1 = dot(ab, ap);
    float d2 = dot(ac, ap);
    if (d1 <= 0.0 && d2 <= 0.0) return a;  // vertex region A

    vec3 bp = p - b;
    float d3 = dot(ab, bp);
    float d4 = dot(ac, bp);
    if (d3 >= 0.0 && d4 <= d3) return b;   // vertex region B

    float vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
        float v = d1 / (d1 - d3);
        return a + v * ab;                 // edge AB
    }

    vec3 cp = p - c;
    float d5 = dot(ab, cp);
    float d6 = dot(ac, cp);
    if (d6 >= 0.0 && d5 <= d6) return c;   // vertex region C

    float vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
        float w = d2 / (d2 - d6);
        return a + w * ac;                 // edge AC
    }

    float va = d3 * d6 - d5 * d4;
    if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
        float w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        return b + w * (c - b);            // edge BC
    }

    // Inside face — interpolate via barycentric weights.
    float denom = 1.0 / (va + vb + vc);
    float v = vb * denom;
    float w = vc * denom;
    return a + ab * v + ac * w;
}


float polynomial(vec4 c,float t){return ((c.w*t+c.z)*t+c.y)*t+c.x;}
// Point / linearly moving triangle: coplanarity is cubic in time. Derivative
// roots split it into monotone intervals, so a narrow sign change is not missed
// by a fixed temporal sampling grid. Barycentrics reject plane-only crossings.
float swept_hit(vec3 p0,vec3 p1,vec3 a0,vec3 b0,vec3 c0,
                vec3 a1,vec3 b1,vec3 c1,out vec3 bary,out float side){
    vec3 u=b0-a0,v=c0-a0,r=p0-a0;
    vec3 du=(b1-a1)-u,dv=(c1-a1)-v,dr=(p1-a1)-r;
    vec3 n0=cross(u,v),n1=cross(du,v)+cross(u,dv),n2=cross(du,dv);
    vec4 co=vec4(dot(r,n0),dot(dr,n0)+dot(r,n1),dot(dr,n1)+dot(r,n2),dot(dr,n2));
    float scale=max(max(abs(co.x),abs(co.y)),max(abs(co.z),abs(co.w)));
    if(scale<1e-18)return 2.0;
    co/=scale;
    float cuts[4];cuts[0]=0.0;cuts[1]=1.0;int count=2;
    float aa=3.0*co.w,bb=2.0*co.z,cc=co.y;
    if(abs(aa)<1e-7){
        if(abs(bb)>1e-7){float t=-cc/bb;if(t>0.0&&t<1.0)cuts[count++]=t;}
    }else{
        float d=bb*bb-4.0*aa*cc;
        if(d>=0.0){
            float t0=(-bb-sqrt(d))/(2.0*aa),t1=(-bb+sqrt(d))/(2.0*aa);
            if(t0>0.0&&t0<1.0)cuts[count++]=t0;
            if(t1>0.0&&t1<1.0&&abs(t1-t0)>1e-6)cuts[count++]=t1;
        }
    }
    for(int i=0;i<count;i++)for(int j=i+1;j<count;j++)if(cuts[j]<cuts[i]){float t=cuts[i];cuts[i]=cuts[j];cuts[j]=t;}
    for(int interval=0;interval<count-1;interval++){
        float lo=cuts[interval],hi=cuts[interval+1];
        float f0=polynomial(co,lo),f1=polynomial(co,hi);
        if(f0*f1>0.0)continue;
        for(int j=0;j<22;j++){
            float mid=(lo+hi)*.5,fm=polynomial(co,mid);
            if(f0*fm<=0.0)hi=mid;else{lo=mid;f0=fm;}
        }
        float t=(lo+hi)*.5;if(t<1e-5)continue;
        vec3 a=mix(a0,a1,t),ab=mix(b0,b1,t)-a,ac=mix(c0,c1,t)-a;
        vec3 q=mix(p0,p1,t)-a,n=cross(ab,ac);float nn=dot(n,n);
        if(nn<1e-18)continue;
        float x=dot(cross(q,ac),n)/nn,y=dot(cross(ab,q),n)/nn;
        if(x<-.00001||y<-.00001||x+y>1.00001)continue;
        bary=vec3(1.0-x-y,x,y);
        side=polynomial(co,max(0.0,t-.0001))>=0.0?1.0:-1.0;
        return t;
    }
    return 2.0;
}
// Closest segment pair, including parallel segments; parameters in [0,1].
vec2 segment_parameters(vec3 a,vec3 b,vec3 c,vec3 d){
 vec3 u=b-a,v=d-c,r=a-c;float aa=dot(u,u),bb=dot(u,v),cc=dot(v,v),dd=dot(u,r),ee=dot(v,r);
 if(aa<1e-18||cc<1e-18)return vec2(0);
 float denom=aa*cc-bb*bb;
 float x=denom>1e-18?clamp((bb*ee-cc*dd)/denom,0.0,1.0):0.0;
 float y=(bb*x+ee)/cc;
 if(y<0.0){y=0.0;x=clamp(-dd/aa,0.0,1.0);}
 else if(y>1.0){y=1.0;x=clamp((bb-dd)/aa,0.0,1.0);}
 return vec2(x,y);
}
vec3 edge_correction(uint idx){
 vec3 correction=vec3(0);float contacts=0.0;
 vec3 u0=positions[idx].xyz,u=snapshot[idx].xyz;
 for(uint adjacent=0u;adjacent<neighbor_counts[idx];adjacent++){
  uint other=neighbors[neighbor_offsets[idx]+adjacent];
  vec3 v0=positions[other].xyz,v=snapshot[other].xyz;
  vec3 low=min(min(u0,v0),min(u,v))-thickness,high=max(max(u0,v0),max(u,v))+thickness;
  for(uint edge=0u;edge<edge_count;edge++){
   uint pi=edge_ids[edge].x,qi=edge_ids[edge].y;
   if(pi==idx||qi==idx||pi==other||qi==other)continue;
   vec3 p0=positions[pi].xyz,q0=positions[qi].xyz,p=snapshot[pi].xyz,q=snapshot[qi].xyz;
   if(any(lessThan(max(max(p0,q0),max(p,q)),low))||any(greaterThan(min(min(p0,q0),min(p,q)),high)))continue;
   vec3 dir0=q0-p0,dir=q-p,weights0,weights1;float side0,side1;
   float hit0=swept_hit(p0,p,u0,v0,u0-dir0,u,v,u-dir,weights0,side0);
   float hit1=swept_hit(p0,p,v0-dir0,u0-dir0,v0,v-dir,u-dir,v,weights1,side1);
   float along,across,side;
   vec3 normal=cross(v-u,-dir);float nl=length(normal);if(nl<1e-10)continue;normal/=nl;
   vec3 ru=rest_positions[idx].xyz,rv=rest_positions[other].xyz,rp=rest_positions[pi].xyz,rq=rest_positions[qi].xyz;
   vec2 rest_uv=segment_parameters(ru,rv,rp,rq);
   float gap=min(thickness*cloth_weights[idx].x,.5*distance(mix(ru,rv,rest_uv.x),mix(rp,rq,rest_uv.y)));
   if(min(hit0,hit1)>1.0){
    vec2 closest=segment_parameters(u,v,p,q);along=closest.x;across=closest.y;
    if(distance(mix(u,v,along),mix(p,q,across))>=gap)continue;
    vec3 old_normal=cross(v0-u0,-dir0);
    side=dot(p0-u0,old_normal)>=0.0?1.0:-1.0;
   }else if(hit0<=hit1){along=weights0.y;across=weights0.z;side=side0;}
   else{along=1.0-weights1.y;across=1.0-weights1.z;side=side1;}
   float depth=gap-side*dot(mix(p,q,across)-mix(u,v,along),normal);
   float wa=1.0-along,wb=along,wc=1.0-across,wd=across;
   float denominator=wa*wa*snapshot[idx].w+wb*wb*snapshot[other].w+wc*wc*snapshot[pi].w+wd*wd*snapshot[qi].w;
   if(depth<=0.0||denominator<1e-10)continue;
   float amount=depth*wa*snapshot[idx].w/denominator;
   vec3 direction=-normal*side;
   if(body_tangents!=0u){
    vec3 ga=body_safe(idx,direction),gb=body_safe(other,direction);
    vec3 gc=body_safe(pi,-direction),gd=body_safe(qi,-direction);
    denominator=wa*wa*snapshot[idx].w*dot(direction,ga)+wb*wb*snapshot[other].w*dot(direction,gb)
      +wc*wc*snapshot[pi].w*dot(-direction,gc)+wd*wd*snapshot[qi].w*dot(-direction,gd);
    // Trust region for the local planes: no vertex may jump farther than the
    // current contact residual. Unlike dropping the projected mass entirely,
    // this still redistributes the reaction when one side is blocked by body.
    float largest=max(max(wa*snapshot[idx].w*length(ga),wb*snapshot[other].w*length(gb)),
      max(wc*snapshot[pi].w*length(gc),wd*snapshot[qi].w*length(gd)));
    denominator=max(denominator,largest);
    if(denominator<1e-10)continue;
    amount=depth*wa*snapshot[idx].w/denominator;direction=ga;
   }
   if(amount>1e-9&&dot(direction,direction)>1e-16){contacts+=1.0;correction+=direction*amount;}
  }
 }
 return contacts>0.0?correction/contacts:vec3(0);
}
void main() {
    uint idx=gl_GlobalInvocationID.x;if(idx>=particle_count)return;
    float w=snapshot[idx].w;
    if(edge_phase==2u){
        if(w<.001)return;
        vec3 correction=vec3(0);float count=0.0;
        for(uint point=0u;point<particle_count;point++){
            vec4 ids=reactions[point*5u];
            for(uint slot=0u;slot<4u;slot++)if(ids[slot]==float(idx)){
                vec3 delta=reactions[point*5u+1u+slot].xyz;
                if(dot(delta,delta)>1e-20){correction+=delta;count+=1.0;}
            }
        }
        predicted[idx]=vec4(snapshot[idx].xyz+(count>0.0?correction/count:vec3(0)),w);
        return;
    }
    if(edge_phase==1u){if(w>=.001)predicted[idx]=vec4(snapshot[idx].xyz+edge_correction(idx),w);return;}
    if(mass_balance!=0u)reactions[idx*5u]=vec4(-1);
    if(w<.001&&mass_balance==0u)return;
    float base_gap=thickness*cloth_weights[idx].x;
    // A fixed point can still constrain a FREE face passing across it. Painted
    // follow weight zero means immobile, not invisible to the reverse contact.
    if(base_gap<1e-6&&mass_balance!=0u)base_gap=thickness;
    if(base_gap<1e-6)return;
    float gap=base_gap;
    vec3 start=positions[idx].xyz,end=predicted[idx].xyz;
    vec3 segment_min=min(start,end)-gap,segment_max=max(start,end)+gap;
    float first=2.0,closest_distance=base_gap,contact_gap=base_gap;vec3 impact=end,contact=end,contact_normal=vec3(0);
    uvec3 hit_ids=uvec3(0),near_ids=uvec3(0);vec3 hit_bary=vec3(0),near_bary=vec3(0);
    for(uint t=0u;t<tri_count;t++){
        uint i0=indices[t*3u],i1=indices[t*3u+1u],i2=indices[t*3u+2u];
        if(idx==i0||idx==i1||idx==i2)continue;
        vec3 a0=positions[i0].xyz,b0=positions[i1].xyz,c0=positions[i2].xyz;
        vec3 a=snapshot[i0].xyz,b=snapshot[i1].xyz,c=snapshot[i2].xyz;
        // Do not demand more space than the source garment has between its
        // close ruffles/seams. This limits the contact gap, not CCD detection.
        vec3 rest_nearest=closest_point_on_triangle(rest_positions[idx].xyz,
            rest_positions[i0].xyz,rest_positions[i1].xyz,rest_positions[i2].xyz);
        gap=min(base_gap,.5*length(rest_positions[idx].xyz-rest_nearest));
        vec3 low=min(min(min(a,b),c),min(min(a0,b0),c0));
        vec3 high=max(max(max(a,b),c),max(max(a0,b0),c0));
        if(any(lessThan(high,segment_min))||any(greaterThan(low,segment_max)))continue;
        vec3 n=cross(b-a,c-a);float nl=length(n);if(nl<1e-10)continue;n/=nl;
        vec3 bary;float side;float hit=swept_hit(start,end,a0,b0,c0,a,b,c,bary,side);
        if(hit<first){
            vec3 anchor=a*bary.x+b*bary.y+c*bary.z;
            vec3 remaining=end-anchor;
            vec3 tangent=remaining-n*dot(remaining,n);
            float tangent_length=length(tangent);
            float correction=max(0.0,gap-side*dot(remaining,n));
            // Other contacts may already have separated this pair. The old
            // sweep remains in the substep history; it must not attract the
            // particle back or monopolize the earliest unresolved contact.
            if(correction>1e-9){
                first=hit;hit_ids=uvec3(i0,i1,i2);hit_bary=bary;
                float retained=tangent_length>1e-8?max(0.0,1.0-friction*correction/tangent_length):0.0;
                impact=end+n*side*correction-tangent*(1.0-retained);
            }
        }
        vec3 q=closest_point_on_triangle(end,a,b,c),diff=end-q;float distance=length(diff);
        if(distance<gap && distance<closest_distance){
            near_ids=uvec3(i0,i1,i2);
            vec3 ab=b-a,ac=c-a,aq=q-a,crossed=cross(ab,ac);float nn=dot(crossed,crossed);
            near_bary.y=dot(cross(aq,ac),crossed)/nn;
            near_bary.z=dot(cross(ab,aq),crossed)/nn;
            near_bary.x=1.0-near_bary.y-near_bary.z;
            contact_gap=gap;
            closest_distance=distance;contact_normal=distance>1e-8?diff/distance:n;
            contact=q+contact_normal*gap;
        }
    }
    vec3 result=first<=1.0?impact:contact;
    if(first>1.0&&closest_distance<contact_gap&&friction>0.0){
        vec3 movement=result-start,tangent=movement-contact_normal*dot(movement,contact_normal);
        float len=length(tangent);if(len>1e-8)result-=tangent*min(1.0,friction*(contact_gap-closest_distance)/len);
    }
    if(mass_balance==0u){predicted[idx]=vec4(result,w);return;}
    if(first>1.0&&closest_distance>=contact_gap)return;
    uvec3 ids=first<=1.0?hit_ids:near_ids;
    vec3 bary=first<=1.0?hit_bary:near_bary;
    vec3 masses=vec3(snapshot[ids.x].w,snapshot[ids.y].w,snapshot[ids.z].w);
    float denominator=w+dot(masses,bary*bary);if(denominator<1e-10)return;
    if(body_tangents!=0u){
        vec3 delta=result-end;float distance=length(delta);if(distance<1e-10)return;
        vec3 direction=delta/distance;
        vec3 gp=body_safe(idx,direction),g0=body_safe(ids.x,-direction),g1=body_safe(ids.y,-direction),g2=body_safe(ids.z,-direction);
        denominator=w*dot(direction,gp)+dot(masses*bary*bary,vec3(dot(-direction,g0),dot(-direction,g1),dot(-direction,g2)));
        // Bound the largest reaction to the current local contact residual.
        // Near opposed planes need repeated relinearization, not a metre-scale
        // jump to force exact separation using stale local contact directions.
        float largest=max(max(w*length(gp),masses.x*bary.x*length(g0)),max(masses.y*bary.y*length(g1),masses.z*bary.z*length(g2)));
        denominator=max(denominator,largest);
        if(denominator<1e-10)return;
        float scale=distance/denominator;
        reactions[idx*5u]=vec4(float(idx),vec3(ids));
        reactions[idx*5u+1u]=vec4(gp*w*scale,0);
        reactions[idx*5u+2u]=vec4(g0*masses.x*bary.x*scale,0);
        reactions[idx*5u+3u]=vec4(g1*masses.y*bary.y*scale,0);
        reactions[idx*5u+4u]=vec4(g2*masses.z*bary.z*scale,0);
        return;
    }
    vec3 correction=(result-end)/denominator;
    reactions[idx*5u]=vec4(float(idx),vec3(ids));
    reactions[idx*5u+1u]=vec4(correction*w,0);
    for(uint slot=0u;slot<3u;slot++)reactions[idx*5u+2u+slot]=vec4(-correction*masses[slot]*bary[slot],0);
}
