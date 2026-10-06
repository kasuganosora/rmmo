#[compute]
#version 450
// Ordered binary trees: eight primitives per leaf. Endpoint bounds are
// conservative for every substep, reduction levels have dispatch barriers.
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Body {vec4 body[];};
layout(set=0,binding=1,std430) readonly buffer OldBody {vec4 old_body[];};
layout(set=0,binding=2,std430) readonly buffer VertexIds {uint vertex_ids[];};
layout(set=0,binding=3,std430) buffer Bounds {vec4 bounds[];};
layout(set=0,binding=4,std430) readonly buffer Order {uint order[];};
layout(push_constant,std430) uniform Params {
 uint triangle_count;uint vertex_count;uint triangle_leaves;uint level;
 float frame_start;float frame_end;uint motion_threshold_mm;uint refit;
};
void build(uint leaves,uint base,uint count,bool triangles,bool ordered){
 uint id=gl_GlobalInvocationID.x,width=leaves>>level;
 if(id>=width)return;
 uint node=base+width+id;
 vec3 low=vec3(3.402823e38),high=-low;float motion=0.0;
 if(level==0u){
  for(uint item=id*8u;item<min(id*8u+8u,count);item++){
   for(uint corner=0u;corner<(triangles?3u:1u);corner++){
    uint mapped=ordered?order[(triangles?0u:triangle_count)+item]:item;
    uint i=triangles?mapped*3u+corner:vertex_ids[mapped];
    motion=max(motion,length(body[i].xyz-old_body[i].xyz));
    vec3 a=refit!=0u?mix(old_body[i].xyz,body[i].xyz,frame_start):old_body[i].xyz;
    vec3 b=refit!=0u?mix(old_body[i].xyz,body[i].xyz,frame_end):body[i].xyz;
    low=min(low,min(a,b));high=max(high,max(a,b));
   }
  }
  if(id*8u<count){vec3 guard=max(vec3(1e-6),max(abs(low),abs(high))*1e-6);low-=guard;high+=guard;}
 }else{
  uint child=base+(width+id)*2u;
  motion=max(bounds[child*2u].w,bounds[(child+1u)*2u].w);
  low=min(bounds[child*2u].xyz,bounds[(child+1u)*2u].xyz);
  high=max(bounds[child*2u+1u].xyz,bounds[(child+1u)*2u+1u].xyz);
 }
 bounds[node*2u]=vec4(low,motion);bounds[node*2u+1u]=vec4(high,0);
}
void main(){
 // Keep the original-order whole-frame tree immutable during refit. Its root
 // holds the frame motion test and its leaves serve sanitizer/fallback paths.
 if(refit!=0u && (refit&2u)==0u && bounds[2].w<=float(motion_threshold_mm)*.001)return;
 if(refit==0u && gl_GlobalInvocationID.x==0u && level==0u)bounds[0]=vec4(0,0,0,uintBitsToFloat(triangle_count));
 uint vertex_leaves=vertex_count<=8u?1u:1u<<uint(findMSB((vertex_count-1u)/8u)+1);
 if(refit==0u)build(triangle_leaves,0u,triangle_count,true,false);
 build(triangle_leaves,triangle_leaves*2u,triangle_count,true,true);
 build(vertex_leaves,triangle_leaves*4u,vertex_count,false,true);
}
