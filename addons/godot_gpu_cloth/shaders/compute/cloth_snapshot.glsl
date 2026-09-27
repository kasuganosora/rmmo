#[compute]
#version 450
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer InputPositions {vec4 positions[];};
layout(set=0,binding=1,std430) writeonly buffer Snapshot {vec4 snapshot[];};
layout(push_constant,std430) uniform Params {uint count;uint p1;uint p2;uint p3;};
void main(){uint i=gl_GlobalInvocationID.x;if(i<count)snapshot[i]=positions[i];}
