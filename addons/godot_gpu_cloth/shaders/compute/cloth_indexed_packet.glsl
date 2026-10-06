#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Points {float points[];};
layout(set=0,binding=1,std430) readonly buffer Indices {uint indices[];};
layout(set=0,binding=2,std430) readonly buffer Extras {float extras[];};
layout(set=0,binding=3,std430) writeonly buffer Output {
#ifdef RMMO_PACKED_STATUS
 layout(offset=16) vec4 output_points[];
#else
 vec4 output_points[];
#endif
};
layout(set=0,binding=4,std430) buffer Invalid {uint invalid;};
layout(push_constant,std430) uniform Params {uint body_count;uint extra_count;uint p0;uint p1;vec4 offset;};
void main(){
 uint face=gl_GlobalInvocationID.x;if(face>=body_count+extra_count)return;
 vec3 p[3];
 for(uint corner=0;corner<3;corner++){
  if(face<body_count){
   uint i=indices[face*3+corner]*3;
   p[corner]=vec3(points[i],points[i+1],points[i+2])+offset.xyz;
  }else{
   uint i=((face-body_count)*3+corner)*3;
   p[corner]=vec3(extras[i],extras[i+1],extras[i+2]);
  }
  if(any(isnan(p[corner]))||any(isinf(p[corner])))atomicOr(invalid,1u);
  output_points[face*3+corner]=vec4(p[corner],0);
 }
 vec3 n=cross(p[1]-p[0],p[2]-p[0]);
 if(dot(n,n)<1e-16)atomicOr(invalid,1u);
}
