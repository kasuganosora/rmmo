#[compute]
#version 450
#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_FALLBACK) || defined(RMMO_CANDIDATE_COMBINED)
#define RMMO_PARALLEL
#endif

// Skinned mesh collider — pushes each free cloth particle outside the body's
// decimated triangle proxy. The CPU side (gpu_cloth_solver.gd:_build_collider_mesh)
// extracts and decimates the body mesh at init, then per-frame skins each
// triangle's verts via single-bone bind_pose * bone_global_pose and uploads to
// the SkinnedTris buffer below. This shader runs alongside cloth_collide.glsl
// in the substep iter loop; both push the same `predicted[]` buffer.
//
// Pinned particles (w < 0.001) are skipped — they're snapped to skinned_targets
// directly in predict and can't be displaced by collision.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// Substep-start positions for the friction tangent calculation. Read-only
// here; the actual position write target is predicted[] at binding 1.
layout(set = 0, binding = 0, std430) restrict readonly buffer Positions {
    vec4 positions[];
};
layout(set = 0, binding = 1, std430) restrict buffer Predicted {
    vec4 predicted[];
};
// Each triangle: 3 contiguous vec4s holding the skinned vert positions
// (w = unused). Total stride 48 bytes per triangle.
layout(set = 0, binding = 4, std430) restrict readonly buffer SkinnedTris {
    vec4 tri_verts[];
};
// Per-particle cloth_weight (x = 0..1). Reused as a thickness multiplier:
// pinned particles (cw=0) are skipped via the w<0.001 check below, so their
// thickness doesn't matter; blend-zone particles (0<cw<1) get proportionally
// less thickness ("lightly attached" cloth shouldn't push hard against the
// body); fully-free particles (cw=1) get the full base thickness.
layout(set = 0, binding = 5, std430) restrict readonly buffer ClothWeights {
    vec4 cloth_weights[];
};
layout(set = 0, binding = 6, std430) restrict readonly buffer PreviousTris {
    vec4 old_tri_verts[];
};

layout(push_constant, std430) uniform Params {
    uint  particle_count;
    uint  tri_count;
    float thickness;     // base thickness; multiplied by cloth_weights[idx].x per-particle
    float friction;      // Coulomb μ; 0 = frictionless
    float frame_start;
    float frame_end;
    uint use_body_bounds; uint triangle_leaves;
};

// Standard closest-point-on-triangle (Ericson, Real-Time Collision Detection).
// Returns the point on triangle (a, b, c) nearest to p — handles all 7 Voronoi
// regions (3 vertices, 3 edges, 1 face).
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
layout(set=0,binding=7,std430) buffer BodyDirections {vec4 body_directions[];};
layout(set=0,binding=8,std430) readonly buffer BodyBounds {vec4 body_bounds[];};
uint next_node(uint node){
 while((node&1u)!=0u){node>>=1u;if(node==0u)return 0u;}
 return node+1u;
}
layout(set=0,binding=9,std430) readonly buffer Order {uint order[];};
#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_FALLBACK) || defined(RMMO_CANDIDATE_COMBINED)
layout(set=0,binding=10,std430) readonly buffer Candidates {uint candidates[];};
#endif
#ifdef RMMO_PARALLEL
shared float hits[64],distances[64];
shared vec3 impacts[64],contacts[64],normals[64];
shared uint hit_ids[64],closest_ids[64];
#endif
void main() {
    #ifdef RMMO_PARALLEL
    uint idx=gl_WorkGroupID.x;
#else
    uint idx=gl_GlobalInvocationID.x;
#endif
    if(idx>=particle_count)return;
#ifdef RMMO_CANDIDATE_LIST
 if(candidates[idx*2055u]>2048u)return;
#endif
#ifdef RMMO_CANDIDATE_FALLBACK
 if(candidates[idx*2055u]<=2048u)return;
#endif

#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_COMBINED)
    if(candidates[idx*2055u]==0u)return;
#endif
    float w=predicted[idx].w;if(w<.001)return;
    float gap=thickness*cloth_weights[idx].x;if(gap<1e-6)return;
    vec3 start=positions[idx].xyz,end=predicted[idx].xyz;
    vec3 segment_min=min(start,end)-gap,segment_max=max(start,end)+gap;
    float first=2.0,closest_distance=gap;vec3 impact=end,contact=end,contact_normal=vec3(0);
    uint first_index=0xffffffffu,closest_index=0xffffffffu;
#ifdef RMMO_CANDIDATE_COMBINED
 uint candidate_count=candidates[idx*2055u];
 bool overflow=candidate_count>2048u;
 for(uint entry=gl_LocalInvocationID.x;entry<(overflow?tri_count:candidate_count);entry+=64u){
  uint t=overflow?entry:candidates[idx*2055u+1u+entry];
#elif defined(RMMO_CANDIDATE_LIST)
 for(uint entry=gl_LocalInvocationID.x;entry<candidates[idx*2055u];entry+=64u){
  uint t=candidates[idx*2055u+1u+entry];
#elif defined(RMMO_CANDIDATE_FALLBACK)
 for(uint t=gl_LocalInvocationID.x;t<tri_count;t+=64u){
#else
    uint node=1u;
    while(node!=0u){
        bool hit_box=use_body_bounds==0u || !(any(lessThan(body_bounds[(triangle_leaves*2u+node)*2u+1u].xyz,segment_min))||any(greaterThan(body_bounds[(triangle_leaves*2u+node)*2u].xyz,segment_max)));
        if(hit_box && node<triangle_leaves){node*=2u;continue;}
        uint begin=node>=triangle_leaves?(node-triangle_leaves)*8u:tri_count;
        uint limit=hit_box?min(begin+8u,tri_count):begin;
        node=next_node(node);
        for(uint item=begin;item<limit;item++){
        uint t=use_body_bounds!=0u?order[item]:item;
#endif
        vec3 ar=old_tri_verts[t*3u].xyz,br=old_tri_verts[t*3u+1u].xyz,cr=old_tri_verts[t*3u+2u].xyz;
        vec3 an=tri_verts[t*3u].xyz,bn=tri_verts[t*3u+1u].xyz,cn=tri_verts[t*3u+2u].xyz;
        vec3 a0=mix(ar,an,frame_start),b0=mix(br,bn,frame_start),c0=mix(cr,cn,frame_start);
        vec3 a=mix(ar,an,frame_end),b=mix(br,bn,frame_end),c=mix(cr,cn,frame_end);
        vec3 low=min(min(min(a,b),c),min(min(a0,b0),c0));
        vec3 high=max(max(max(a,b),c),max(max(a0,b0),c0));
        if(any(lessThan(high,segment_min))||any(greaterThan(low,segment_max)))continue;
        vec3 n=cross(b-a,c-a);float nl=length(n);if(nl<1e-10)continue;n/=nl;
        vec3 bary;float side;float hit=swept_hit(start,end,a0,b0,c0,a,b,c,bary,side);
        if(hit<first || (hit==first && hit<=1.0 && t<first_index)){
            vec3 anchor=a*bary.x+b*bary.y+c*bary.z;
            vec3 remaining=end-anchor;
            vec3 tangent=remaining-n*dot(remaining,n);
            float tangent_length=length(tangent);
            float correction=max(0.0,gap-side*dot(remaining,n));
            // Another projection or the moving body may have already released
            // this contact. A historical crossing must not attract the point
            // back onto the surface or hide a later unresolved contact.
            if(correction>1e-9){
                first=hit;first_index=t;
                float retained=tangent_length>1e-8?max(0.0,1.0-friction*correction/tangent_length):0.0;
                impact=end+n*side*correction-tangent*(1.0-retained);
            }
        }
        vec3 q=closest_point_on_triangle(end,a,b,c),diff=end-q;float distance=length(diff);
        if(distance<closest_distance || (distance==closest_distance && t<closest_index && distance<gap)){
            closest_distance=distance;closest_index=t;contact_normal=distance>1e-8?diff/distance:n;
            contact=q+contact_normal*gap;
        }
    }

#ifndef RMMO_PARALLEL
    }
#endif
#ifdef RMMO_PARALLEL
    uint lane=gl_LocalInvocationID.x;
    hits[lane]=first;hit_ids[lane]=first_index;impacts[lane]=impact;
    distances[lane]=closest_distance;closest_ids[lane]=closest_index;contacts[lane]=contact;normals[lane]=contact_normal;
    barrier();if(lane!=0u)return;
    for(uint other=1u;other<64u;other++){
        if(hits[other]<first || (hits[other]==first && hit_ids[other]<first_index)){
            first=hits[other];first_index=hit_ids[other];impact=impacts[other];
        }
        if(distances[other]<closest_distance || (distances[other]==closest_distance && closest_ids[other]<closest_index)){
            closest_distance=distances[other];closest_index=closest_ids[other];contact=contacts[other];contact_normal=normals[other];
        }
    }
#endif
    vec3 result=first<=1.0?impact:contact;
    if(first>1.0&&closest_distance<gap&&friction>0.0){
        vec3 movement=result-start,tangent=movement-contact_normal*dot(movement,contact_normal);
        float len=length(tangent);if(len>1e-8)result-=tangent*min(1.0,friction*(gap-closest_distance)/len);
    }
    vec3 delta=result-end;
    if(dot(delta,delta)>1e-18)body_directions[idx*2u+1u]=vec4(normalize(delta),1);
    predicted[idx]=vec4(result,w);
}
