#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Points { float points[]; };
layout(set=0,binding=1,std430) readonly buffer Adjacency { uvec2 adjacency[]; };
layout(set=0,binding=2,std430) readonly buffer Triangles { uvec4 triangles[]; };
layout(rgba32f,set=0,binding=3) uniform image2D positions;
layout(rgba32f,set=0,binding=4) uniform writeonly image2D normals;
layout(push_constant,std430) uniform Parameters { vec4 offset_mode; } params;
ivec2 coord(uint id){return ivec2(id%512u,id/512u);}
vec3 point(uint id){precise vec3 p=vec3(points[id*3u],points[id*3u+1u],points[id*3u+2u])+params.offset_mode.xyz;return p;}
void main(){
 uint id=gl_GlobalInvocationID.x;if(id>=21556u)return;
 imageStore(positions,coord(id),vec4(point(id),0));
 uvec2 span=adjacency[id];vec3 normal=vec3(0);
 for(uint j=0u;j<span.y;j++){
  uvec3 t=triangles[span.x+j].xyz;
  precise vec3 a=point(t.x),b=point(t.y),c=point(t.z);
  precise vec3 ab=b-a,ac=c-a;
  normal-=cross(ab,ac);
 }
 imageStore(normals,coord(id),vec4(normalize(normal),0));
}
