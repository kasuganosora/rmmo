#[compute]
#version 450
#ifndef RMMO_CANDIDATE_PADDING
#define RMMO_CANDIDATE_PADDING 0.012
#endif
#ifndef RMMO_CANDIDATE_GROUP_SIZE
#define RMMO_CANDIDATE_GROUP_SIZE 64
#endif
layout(local_size_x=RMMO_CANDIDATE_GROUP_SIZE) in;
layout(set=0,binding=0,std430) readonly buffer OldCloth {vec4 positions[];};
layout(set=0,binding=1,std430) readonly buffer Cloth {vec4 predicted[];};
layout(set=0,binding=2,std430) readonly buffer Indices {uint indices[];};
layout(set=0,binding=3,std430) readonly buffer Body {vec4 body[];};
layout(set=0,binding=4,std430) readonly buffer OldBody {vec4 old_body[];};
layout(set=0,binding=5,std430) readonly buffer Vertices {uint vertex_ids[];};
layout(set=0,binding=6,std430) readonly buffer Bounds {vec4 bounds[];};
layout(set=0,binding=7,std430) readonly buffer Order {uint order[];};
layout(set=0,binding=8,std430) buffer Candidates {uint candidates[];};
layout(set=0,binding=9,std430) readonly buffer Weights {vec4 weights[];};
// reverse bit flags: 1=reverse query, 2=new frame, 4=substep mode,
// 8=substep boundary, 16=adapt envelope to body motion; upper 24 bits
// encode the motion threshold in millimeters (search policy, not precision).
layout(push_constant,std430) uniform Params {uint count;uint reverse;uint leaves;uint triangle_count;float start;float end;float thickness;uint vertex_count;};
uint next_node(uint node){while((node&1u)!=0u){node>>=1u;if(node==0u)return 0u;}return node+1u;}
#ifdef RMMO_COOPERATIVE_CANDIDATES
shared uint shared_found;
uint next_subtree_node(uint node,uint root){while(node!=root && (node&1u)!=0u)node>>=1u;return node==root?0u:node+1u;}
#endif
void main(){
#ifdef RMMO_COOPERATIVE_CANDIDATES
 uint lane=gl_LocalInvocationID.x;
 uint id=gl_WorkGroupID.x;if(id>=count)return;
#else
 uint id=gl_GlobalInvocationID.x;if(id>=count)return;
#endif
 uint base=id*2055u,found=0u,mode=reverse&1u;
 // Whole-frame caching is cheaper for small motion. The threshold selects
 // only a conservative search envelope; contact thickness/CCD are unchanged.
 bool substep=(reverse&4u)!=0u && ((reverse&16u)==0u || bounds[(leaves*2u+1u)*2u].w>float(reverse>>8u)*.001);
 bool refresh=(reverse&2u)!=0u || (substep && (reverse&8u)!=0u);
 vec3 low,high;
 if(mode==0u){
  float gap=thickness*weights[id].x;if(predicted[id].w<.001||gap<1e-6){
#ifdef RMMO_COOPERATIVE_CANDIDATES
   if(lane==0u)candidates[base]=0u;
#else
   candidates[base]=0u;
#endif
   return;
  }
  low=min(positions[id].xyz,predicted[id].xyz)-gap;high=max(positions[id].xyz,predicted[id].xyz)+gap;
 }else{
  uvec3 ids=uvec3(indices[id*3u],indices[id*3u+1u],indices[id*3u+2u]);
  low=min(min(predicted[ids.x].xyz,predicted[ids.y].xyz),predicted[ids.z].xyz);
  low=min(low,min(min(positions[ids.x].xyz,positions[ids.y].xyz),positions[ids.z].xyz))-thickness;
  high=max(max(predicted[ids.x].xyz,predicted[ids.y].xyz),predicted[ids.z].xyz);
  high=max(high,max(max(positions[ids.x].xyz,positions[ids.y].xyz),positions[ids.z].xyz))+thickness;
 }
 bool reuse=false;
 if(!refresh){
  vec3 cached_low=vec3(uintBitsToFloat(candidates[base+2049u]),uintBitsToFloat(candidates[base+2050u]),uintBitsToFloat(candidates[base+2051u]));
  vec3 cached_high=vec3(uintBitsToFloat(candidates[base+2052u]),uintBitsToFloat(candidates[base+2053u]),uintBitsToFloat(candidates[base+2054u]));
  reuse=all(greaterThanEqual(low,cached_low))&&all(lessThanEqual(high,cached_high));
 }
#ifdef RMMO_COOPERATIVE_CANDIDATES
 // All lanes finish reading the old cache before lane zero may replace it.
 groupMemoryBarrier();barrier();
#endif
 if(reuse)return;
 // Cached lists are a conservative superset. Rebuild whenever the full swept
 // query escapes, and unconditionally at each new body-packet boundary. Body candidate bounds
 // cover the entire frame. Active substep mode narrows only leaf endpoints;
 // bit 8 forces a refresh at each substep boundary even if the cloth is still.
 low-=RMMO_CANDIDATE_PADDING;high+=RMMO_CANDIDATE_PADDING;
#ifdef RMMO_COOPERATIVE_CANDIDATES
 if(lane==0u){shared_found=0u;
#endif
 for(uint axis=0u;axis<3u;axis++){candidates[base+2049u+axis]=floatBitsToUint(low[axis]);candidates[base+2052u+axis]=floatBitsToUint(high[axis]);}
#ifdef RMMO_COOPERATIVE_CANDIDATES
 }
 barrier();
#endif
 uint tree_leaves=mode==0u?leaves:(vertex_count<=8u?1u:1u<<uint(findMSB((vertex_count-1u)/8u)+1));
 uint tree_base=mode==0u?leaves*2u:leaves*4u;
 uint total=mode==0u?triangle_count:vertex_count;
#ifdef RMMO_COOPERATIVE_CANDIDATES
 uint roots=min(tree_leaves,uint(RMMO_CANDIDATE_GROUP_SIZE));
 uint root=roots+lane,node=lane<roots?root:0u;
#else
 uint node=1u;
#endif
 while(node!=0u){
  uint address=tree_base+node;
  bool hit=!(any(lessThan(bounds[address*2u+1u].xyz,low))||any(greaterThan(bounds[address*2u].xyz,high)));
  if(hit&&node<tree_leaves){node*=2u;continue;}
  uint begin=node>=tree_leaves?(node-tree_leaves)*8u:total;
  uint limit=hit?min(begin+8u,total):begin;
#ifdef RMMO_COOPERATIVE_CANDIDATES
  node=next_subtree_node(node,root);
#else
  node=next_node(node);
#endif
  for(uint item=begin;item<limit;item++){
   uint original=order[(mode==0u?0u:triangle_count)+item];
   vec3 plow=vec3(3.402823e38),phigh=-plow;
   for(uint corner=0u;corner<(mode==0u?3u:1u);corner++){
    uint vertex=mode==0u?original*3u+corner:vertex_ids[original];
    vec3 old=old_body[vertex].xyz,current=body[vertex].xyz;
    vec3 a=substep?mix(old,current,start):old;
    vec3 b=substep?mix(old,current,end):current;
    plow=min(plow,min(a,b));phigh=max(phigh,max(a,b));
   }
   if(any(lessThan(phigh,low))||any(greaterThan(plow,high)))continue;
#ifdef RMMO_COOPERATIVE_CANDIDATES
   uint slot=atomicAdd(shared_found,1u)+1u;
   if(slot<=2048u)candidates[base+slot]=original;
#else
   found++;if(found>2048u){candidates[base]=2049u;return;}
   candidates[base+found]=original;
#endif
  }
#ifdef RMMO_COOPERATIVE_CANDIDATES
  if(atomicAdd(shared_found,0u)>2048u)break;
#endif
 }
#ifdef RMMO_COOPERATIVE_CANDIDATES
 barrier();
 if(lane==0u)candidates[base]=min(shared_found,2049u);
#else
 candidates[base]=found;
#endif
}
