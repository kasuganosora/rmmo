#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Rest { vec4 rest[]; };
layout(set=0,binding=1,std430) readonly buffer Weights { vec4 weights[]; };
layout(set=0,binding=2,std430) readonly buffer Bones { vec4 bones[]; };
layout(set=0,binding=3,std430) buffer Positions { vec4 positions[]; };
layout(set=0,binding=4,std430) readonly buffer Adjacency { uvec2 adjacency[]; };
layout(set=0,binding=5,std430) readonly buffer Triangles { uvec4 triangles[]; };
layout(set=0,binding=6,std430) writeonly buffer Normals {
#ifdef RMMO_PACKED_OUTPUT
 layout(offset=352256)
#endif
 vec4 normals[]; };
// Tightly packed CPU contact points (vec3 arrays in std430 would have 16-byte stride).
layout(set=0,binding=7,std430) writeonly buffer ContactPoints {
#ifdef RMMO_PACKED_OUTPUT
 layout(offset=704512)
#endif
 float contact_points[]; };
layout(set=0,binding=8,std430) writeonly buffer GroupBounds {
#ifdef RMMO_PACKED_OUTPUT
 layout(offset=963184)
#endif
 float group_min_y[]; };
shared float local_min_y[64];
layout(push_constant,std430) uniform Parameters { vec4 offset_mode; } params;
const ivec3 orders[6]=ivec3[6](ivec3(2,1,0),ivec3(1,2,0),ivec3(2,0,1),ivec3(0,2,1),ivec3(1,0,2),ivec3(0,1,2));
mat4 matrix_at(int start) {return mat4(bones[start],bones[start+1],bones[start+2],bones[start+3]);}
vec3 rotate_axis(vec3 p,int axis,float a) {
    float s=sin(a),c=cos(a);
    if(axis==0)return vec3(p.x,c*p.y-s*p.z,s*p.y+c*p.z);
    if(axis==1)return vec3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);
    return vec3(c*p.x-s*p.y,s*p.x+c*p.y,p.z);
}
vec3 deform(uint id) {
    vec3 p=rest[id].xyz;
    for(int j=0;j<int(rest[id].w);j++) {
        int base=int(id)*24+j*3;
        vec4 first=weights[base],second=weights[base+1],third=weights[base+2];
        int bone=int(first.x)*16;
        if(first.y>0.5) {p=(matrix_at(bone+8)*vec4(p,1.0)).xyz;continue;}
        vec4 angle_order=bones[bone+12];vec3 weighted=angle_order.xyz*vec3(first.zw,second.x);
        if(dot(angle_order.xyz,angle_order.xyz)<1e-14)continue;
        p=(matrix_at(bone+4)*vec4(p,1.0)).xyz;
        ivec3 order=orders[int(angle_order.w)];
        for(int k=0;k<3;k++) {
            int axis=order[k];p=rotate_axis(p,axis,weighted[axis]);
            float expansion=(1.0+bones[bone+13][axis]*second[axis+1])*(1.0+bones[bone+14][axis]*third[axis]);
            for(int c=0;c<3;c++)if(c!=axis)p[c]*=expansion;
        }
        p=(matrix_at(bone)*vec4(p,1.0)).xyz;
    }
    return p;
}
void main() {
    uint id=gl_GlobalInvocationID.x;
    if(params.offset_mode.w>0.5) {
        if(id>=21556u)return;
        uvec2 span=adjacency[id];vec3 normal=vec3(0.0);
        for(uint j=0u;j<span.y;j++) {
            uvec3 t=triangles[span.x+j].xyz;
            normal-=cross(positions[t.y].xyz-positions[t.x].xyz,positions[t.z].xyz-positions[t.x].xyz);
        }
        normals[id]=vec4(normalize(normal),0.0);return;
    }
    uint lane=gl_LocalInvocationID.x;
    float y=1e30;
    if(id<21556u) {
        vec3 p=deform(id);
        positions[id]=vec4(p+params.offset_mode.xyz,0.0);
        contact_points[id*3u]=p.x;
        contact_points[id*3u+1u]=p.y;
        contact_points[id*3u+2u]=p.z;
        y=p.y;
    }
    local_min_y[lane]=y;
    barrier();
    for(uint step=32u;step>0u;step>>=1u) {
        if(lane<step)local_min_y[lane]=min(local_min_y[lane],local_min_y[lane+step]);
        barrier();
    }
    if(lane==0u)group_min_y[gl_WorkGroupID.x]=local_min_y[0];
}
