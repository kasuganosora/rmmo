#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) buffer Cloth {vec4 predicted[];};
layout(set=0,binding=1,std430) readonly buffer Indices {uint indices[];};
layout(set=0,binding=2,std430) readonly buffer Counts {uint counts[];};
layout(set=0,binding=3,std430) readonly buffer Offsets {uint offsets[];};
layout(set=0,binding=4,std430) readonly buffer Adjacent {uint faces[];};
layout(set=0,binding=5,std430) readonly buffer Corrections {vec4 corrections[];};
layout(set=0,binding=6,std430) buffer BodyDirections {vec4 body_directions[];};
layout(push_constant,std430) uniform Params {uint count;uint pad;uint pad2;uint pad3;};
void main(){
 uint i=gl_GlobalInvocationID.x;if(i>=count||predicted[i].w<.001)return;
 vec3 delta=vec3(0);float contact_count=0;
 for(uint j=0;j<counts[i];j++){
  uint face=faces[offsets[i]+j],slot=face*3;
  if(indices[slot]!=i)slot+=indices[slot+1]==i?1:2;
  vec4 value=corrections[slot];delta+=value.xyz;contact_count+=value.w;
 }
 if(contact_count>0){
  predicted[i].xyz+=delta/contact_count;
  if(dot(delta,delta)>1e-18)body_directions[i*2u]=vec4(normalize(delta),1);
 }
}

