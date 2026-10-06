#[compute]
#version 450
#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_FALLBACK) || defined(RMMO_CANDIDATE_COMBINED)
#define RMMO_PARALLEL
#endif
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer OldCloth {vec4 positions[];};
layout(set=0,binding=1,std430) readonly buffer Cloth {vec4 predicted[];};
layout(set=0,binding=2,std430) readonly buffer Indices {uint indices[];};
layout(set=0,binding=3,std430) readonly buffer Body {vec4 body[];};
layout(set=0,binding=4,std430) readonly buffer OldBody {vec4 old_body[];};
layout(set=0,binding=5,std430) readonly buffer VertexIds {uint vertex_ids[];};
layout(set=0,binding=6,std430) writeonly buffer Corrections {vec4 corrections[];};
layout(set=0,binding=7,std430) readonly buffer Edges {uvec2 edges[];};
layout(set=0,binding=8,std430) readonly buffer BodyBounds {vec4 body_bounds[];};
layout(push_constant,std430) uniform Params {
 uint face_count; uint vertex_count; float thickness; uint edge_count;
 float frame_start; float frame_end; uint use_body_bounds; uint triangle_blocks;
};
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
uint next_node(uint node){
 while((node&1u)!=0u){node>>=1u;if(node==0u)return 0u;}
 return node+1u;
}
layout(set=0,binding=9,std430) readonly buffer Order {uint order[];};
#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_FALLBACK) || defined(RMMO_CANDIDATE_COMBINED)
layout(set=0,binding=10,std430) readonly buffer Candidates {uint candidates[];};
#endif
#ifdef RMMO_PARALLEL
shared float depths[64];shared uint contact_ids[64];shared vec3 barycentrics[64],directions[64];
#endif
void main(){
 #ifdef RMMO_PARALLEL
 uint face=gl_WorkGroupID.x;
#else
 uint face=gl_GlobalInvocationID.x;
#endif
 if(face>=face_count)return;
#ifdef RMMO_CANDIDATE_LIST
 if(candidates[face*2055u]>2048u)return;
#endif
#ifdef RMMO_CANDIDATE_FALLBACK
 if(candidates[face*2055u]<=2048u)return;
#endif

 uint i=indices[face*3],j=indices[face*3+1],k=indices[face*3+2];
 vec3 a=predicted[i].xyz,b=predicted[j].xyz,c=predicted[k].xyz;
 vec3 a0=positions[i].xyz,b0=positions[j].xyz,c0=positions[k].xyz;
 vec3 mass=vec3(predicted[i].w,predicted[j].w,predicted[k].w);
 vec3 n=cross(b-a,c-a);float nn=dot(n,n);
#ifdef RMMO_PARALLEL
 if(gl_LocalInvocationID.x==0u){
#endif
 corrections[face*3]=vec4(0);corrections[face*3+1]=vec4(0);corrections[face*3+2]=vec4(0);
#ifdef RMMO_PARALLEL
 }
#endif
#if defined(RMMO_CANDIDATE_LIST) || defined(RMMO_CANDIDATE_COMBINED)
 if(candidates[face*2055u]==0u && edge_count==0u)return;
#endif
 if(nn<1e-18||dot(mass,mass)<1e-8)return;
 vec3 unit_n=n/sqrt(nn);
 vec3 low=min(min(min(a,b),c),min(min(a0,b0),c0))-thickness;
 vec3 high=max(max(max(a,b),c),max(max(a0,b0),c0))+thickness;
 float strongest=0;vec3 chosen=vec3(0),direction=vec3(0);
 uint chosen_index=0xffffffffu;
#ifdef RMMO_CANDIDATE_COMBINED
 uint candidate_count=candidates[face*2055u];
 bool overflow=candidate_count>2048u;
 for(uint entry=gl_LocalInvocationID.x;entry<(overflow?vertex_count:candidate_count);entry+=64u){
  uint v=overflow?entry:candidates[face*2055u+1u+entry];
#elif defined(RMMO_CANDIDATE_LIST)
 for(uint entry=gl_LocalInvocationID.x;entry<candidates[face*2055u];entry+=64u){
  uint v=candidates[face*2055u+1u+entry];
#elif defined(RMMO_CANDIDATE_FALLBACK)
 for(uint v=gl_LocalInvocationID.x;v<vertex_count;v+=64u){
#else
 uint leaves=vertex_count<=8u?1u:1u<<uint(findMSB((vertex_count-1u)/8u)+1);
 uint node=1u;
 while(node!=0u){
  uint address=triangle_blocks*4u+node;
  bool hit_box=use_body_bounds==0u || !(any(lessThan(body_bounds[address*2u+1u].xyz,low))||any(greaterThan(body_bounds[address*2u].xyz,high)));
  if(hit_box&&node<leaves){node*=2u;continue;}
  uint begin=node>=leaves?(node-leaves)*8u:vertex_count;
  uint limit=hit_box?min(begin+8u,vertex_count):begin;
  node=next_node(node);
  for(uint item=begin;item<limit;item++){
  uint v=use_body_bounds!=0u?order[floatBitsToUint(body_bounds[0].w)+item]:item;
#endif
  uint id=vertex_ids[v];
  vec3 p0=mix(old_body[id].xyz,body[id].xyz,frame_start);
  vec3 p=mix(old_body[id].xyz,body[id].xyz,frame_end);
  if(any(lessThan(max(p,p0),low))||any(greaterThan(min(p,p0),high)))continue;
  vec3 bary;float side;
  float hit=swept_hit(p0,p,a0,b0,c0,a,b,c,bary,side);
  if(hit>1.0){
   vec3 q=closest_point_on_triangle(p,a,b,c);
   if(distance(p,q)>=thickness)continue;
   vec3 n0=cross(b0-a0,c0-a0);
   side=dot(p0-a0,n0)>=0?1.0:-1.0;
   vec3 offset=q-a;
   float x=dot(cross(offset,c-a),n)/nn,y=dot(cross(b-a,offset),n)/nn;
   bary=vec3(1-x-y,x,y);
  }
  float depth=thickness-side*dot(p-(a*bary.x+b*bary.y+c*bary.z),unit_n);
  if(depth>strongest || (depth==strongest && v<chosen_index && depth>0)){strongest=depth;chosen_index=v;chosen=bary;direction=-unit_n*side;}
 }


#ifndef RMMO_PARALLEL
 }
#endif
#ifdef RMMO_PARALLEL
 uint lane=gl_LocalInvocationID.x;
 depths[lane]=strongest;contact_ids[lane]=chosen_index;barycentrics[lane]=chosen;directions[lane]=direction;
 barrier();if(lane!=0u)return;
 for(uint other=1u;other<64u;other++){
  if(depths[other]>strongest || (depths[other]==strongest && contact_ids[other]<chosen_index)){
   strongest=depths[other];chosen_index=contact_ids[other];chosen=barycentrics[other];direction=directions[other];
  }
 }
#endif
 // Edge/edge CCD. A moving edge pair is coplanar exactly when the moving
 // body endpoint meets the parallelogram spanned by clothEdge and -bodyEdge.
 // Two triangles cover that parallelogram without the s+t<=1 restriction.
 for(uint edge=0;edge<edge_count;edge++){
  uvec2 ids=edges[edge];
  vec3 p0=mix(old_body[ids.x].xyz,body[ids.x].xyz,frame_start);
  vec3 q0=mix(old_body[ids.y].xyz,body[ids.y].xyz,frame_start);
  vec3 p=mix(old_body[ids.x].xyz,body[ids.x].xyz,frame_end);
  vec3 q=mix(old_body[ids.y].xyz,body[ids.y].xyz,frame_end);
  vec3 elow=min(min(p0,q0),min(p,q)),ehigh=max(max(p0,q0),max(p,q));
  if(any(lessThan(ehigh,low))||any(greaterThan(elow,high)))continue;
  vec3 old_cloth[3]=vec3[3](a0,b0,c0),cloth[3]=vec3[3](a,b,c);
  for(int e=0;e<3;e++){
   int next=(e+1)%3;
   vec3 u0=old_cloth[e],v0=old_cloth[next],u=cloth[e],v=cloth[next];
   vec3 dir0=q0-p0,dir=q-p;
   vec3 weights;float side;
   float hit=swept_hit(p0,p,u0,v0,u0-dir0,u,v,u-dir,weights,side);
   float along=weights.y,other=weights.z;
   if(hit>1.0){
    hit=swept_hit(p0,p,v0-dir0,u0-dir0,v0,v-dir,u-dir,v,weights,side);
    along=1.0-weights.y;other=1.0-weights.z;
   }
   if(hit>1.0)continue;
   vec3 normal=cross(v-u,-dir);float len=length(normal);
   if(len<1e-10)continue;normal/=len;
   float depth=thickness-side*dot(mix(p,q,other)-mix(u,v,along),normal);
   if(depth>strongest){
    strongest=depth;chosen=vec3(0);chosen[e]=1.0-along;chosen[next]=along;direction=-normal*side;
   }
  }
 }
 float denominator=dot(chosen*chosen,mass);
 if(strongest<=0||denominator<1e-8)return;
 vec3 delta=direction*strongest/denominator;
 corrections[face*3]=vec4(delta*chosen.x*mass.x,1);
 corrections[face*3+1]=vec4(delta*chosen.y*mass.y,1);
 corrections[face*3+2]=vec4(delta*chosen.z*mass.z,1);
}
