#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Rest {vec4 rest[];};
layout(set=0,binding=1,std430) readonly buffer Anchors {vec4 anchors[];};
layout(set=0,binding=2,std430) readonly buffer Body {vec4 body[];};
layout(set=0,binding=3,std430) readonly buffer BodyNormals {vec4 body_normals[];};
layout(set=0,binding=4,std430) buffer PositionsA {vec4 pa[];};
layout(set=0,binding=5,std430) buffer PositionsB {vec4 pb[];};
layout(set=0,binding=6,std430) buffer Previous {vec4 previous[];};
layout(set=0,binding=7,std430) readonly buffer Spans {uvec2 spans[];};
layout(set=0,binding=8,std430) readonly buffer Links {vec4 links[];};
layout(set=0,binding=9,std430) readonly buffer TriSpans {uvec2 tri_spans[];};
layout(set=0,binding=10,std430) readonly buffer Triangles {uvec4 triangles[];};
layout(set=0,binding=11,std430) buffer Normals {vec4 normals[];};
layout(set=0,binding=12,std430) buffer Heads {int heads[];};
layout(set=0,binding=13,std430) buffer Next {int next_vertex[];};
layout(set=0,binding=14,std430) readonly buffer BodySpans {uvec2 body_spans[];};
layout(set=0,binding=15,std430) readonly buffer BodyTriangles {uvec4 body_triangles[];};
layout(set=0,binding=16,std430) readonly buffer HandContacts {vec4 hands[];};
layout(push_constant,std430) uniform Params {vec4 control;vec4 settings;} params;
// control: mode, particle count, iteration parity, time step
// settings: floor height, contact thickness, total body/layer point count, unused
ivec3 cell(vec3 p){return clamp(ivec3(floor((p+vec3(3.2))/.1)),ivec3(0),ivec3(63));}
int key(ivec3 c){return c.x+c.y*64+c.z*4096;}
vec3 target(uint id){
    ivec3 ids=ivec3(anchors[id*2].xyz);
    vec3 a=body[ids.x].xyz,b=body[ids.y].xyz,c=body[ids.z].xyz;
    vec3 n=-normalize(cross(b-a,c-a)),t=(a+b+c)/3.0-a;
    return a+mat3(t,cross(t,n),n)*anchors[id*2+1].xyz;
}
vec3 get_point(uint id,bool even){return even?pa[id].xyz:pb[id].xyz;}
vec3 segment_point(vec3 p,vec3 a,vec3 b){vec3 ab=b-a;return a+ab*clamp(dot(p-a,ab)/max(dot(ab,ab),1e-12),0.0,1.0);}
vec3 triangle_point(vec3 p,vec3 a,vec3 b,vec3 c){
    vec3 ab=b-a,ac=c-a,n=cross(ab,ac);float nn=dot(n,n);
    if(nn>1e-16){
        vec3 q=p-n*dot(p-a,n)/nn;
        float u=dot(cross(q-a,ac),n)/nn,v=dot(cross(ab,q-a),n)/nn;
        if(u>=0.0 && v>=0.0 && u+v<=1.0)return q;
    }
    vec3 q=segment_point(p,a,b),r=segment_point(p,b,c),s=segment_point(p,c,a);
    if(dot(r-p,r-p)<dot(q-p,q-p))q=r;
    if(dot(s-p,s-p)<dot(q-p,q-p))q=s;
    return q;
}
vec3 contact(vec3 p){
    ivec3 origin=cell(p);float closest=1e10;int nearest=-1;
    float layer_distance=1e10;int nearest_layer=-1;
    for(int z=-1;z<=1;z++)for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
        ivec3 c=origin+ivec3(x,y,z);
        if(any(lessThan(c,ivec3(0)))||any(greaterThan(c,ivec3(63))))continue;
        int id=heads[key(c)];int guard=0;
        while(id>=0 && guard++<int(params.settings.z)){
            vec3 delta=p-body[id].xyz;float distance2=dot(delta,delta);
            if(id<21556){if(distance2<closest){closest=distance2;nearest=id;}}
            else if(distance2<layer_distance){layer_distance=distance2;nearest_layer=id;}
            id=next_vertex[id];
        }
    }
    if(nearest>=0 && closest<.12*.12){
        vec3 surface=body[nearest].xyz,normal=normalize(body_normals[nearest].xyz);
        uvec2 span=body_spans[nearest];
        for(uint j=0;j<span.y;j++){
            uvec3 ids=body_triangles[span.x+j].xyz;
            vec3 a=body[ids.x].xyz,b=body[ids.y].xyz,c=body[ids.z].xyz;
            vec3 q=triangle_point(p,a,b,c);float d=dot(p-q,p-q);
            if(d<closest){closest=d;surface=q;normal=normalize(body_normals[ids.x].xyz+body_normals[ids.y].xyz+body_normals[ids.z].xyz);}
        }
        float signed_distance=dot(p-surface,normal);
        if(signed_distance<params.settings.y)p+=normal*min(.04,params.settings.y-signed_distance);
    }
    // An inner garment is an open, often folded sheet, not a closed body volume.
    // Signed body penetration rules would inflate an entire ruffle on its back side.
    if(nearest_layer>=0){
        vec3 delta=p-body[nearest_layer].xyz;float distance=length(delta);
        if(distance<params.settings.y && distance>1e-8)p+=delta/distance*(params.settings.y-distance);
    }
    p.y=max(p.y,params.settings.x+params.settings.y);
    return p;
}
vec3 probe_push(vec3 p,float rest_y,int hand){
    vec3 correction=vec3(0);
        vec4 sphere=hands[hand*2],medial=hands[hand*2+1];
        vec3 delta=p-sphere.xyz;float radius=sphere.w+params.settings.y;
        float axial=dot(delta,medial.xyz);
        vec3 lateral=delta-medial.xyz*axial;
        float lateral2=dot(lateral,lateral);
        if(rest_y<medial.w && lateral2<radius*radius && axial>-2.0*radius && axial<radius){
            float depth=sqrt(max(0.0,radius*radius-lateral2))-axial;
            vec3 push=medial.xyz*max(0.0,depth);
            if(dot(push,push)>dot(correction,correction))correction=push;
        }else if(rest_y>=medial.w && length(delta)<radius && length(delta)>1e-8){
            vec3 push=normalize(delta)*(radius-length(delta));
            if(dot(push,push)>dot(correction,correction))correction=push;
        }
    return correction;
}
vec3 hand_push(vec3 p,float rest_y){
    vec3 correction=vec3(0);
    for(int hand=0;hand<int(params.settings.w);hand++){
        vec3 push=probe_push(p,rest_y,hand);
        if(dot(push,push)>dot(correction,correction))correction=push;
    }
    return correction;
}
void main(){
    uint id=gl_GlobalInvocationID.x;int mode=int(params.control.x);uint count=uint(params.control.y);
    if(mode==0){if(id<262144)heads[id]=-1;return;}
    if(mode==1){if(id<uint(params.settings.z))next_vertex[id]=atomicExchange(heads[key(cell(body[id].xyz))],int(id));return;}
    if(id>=count)return;
    if(mode==2){vec3 p=target(id);pa[id]=pb[id]=previous[id]=vec4(p,1);return;}
    if(mode==3){
        vec3 p=pa[id].xyz,velocity=(p-previous[id].xyz)*.97;previous[id]=vec4(p,1);
        float dt=params.control.w;
        p+=velocity+vec3(0,-9.81,0)*dt*dt;
        float pin=rest[id].w;
        p=mix(p,target(id),pin);
        pa[id]=vec4(p,1);return;
    }
    if(mode==4){
        bool even=int(params.control.z)%2==0;vec3 p=get_point(id,even);float pin=rest[id].w;
        vec3 correction=vec3(0);float divisor=0;
        uvec2 span=spans[id];
        for(uint j=0;j<span.y;j++){
            vec4 edge=links[span.x+j];uint other=uint(edge.x);
            vec3 d=p-get_point(other,even);float length_now=length(d);
            if(length_now<1e-9)continue;
            float wi=1.0-pin,wj=1.0-rest[other].w;
            float fraction=wi/max(wi+wj,1e-8);
            correction-=d*(1.0-edge.y/length_now)*fraction*edge.z;
            divisor+=edge.z;
        }
        p+=correction/max(divisor,1.0)*1.6;
        // Soft follow belongs to integration, once per physical time step.
        // Reapplying it for every constraint iteration hardens the skirt and
        // fights contact. Only authored fully fixed points are projected here.
        if(pin>=.999)p=target(id);
        if(pin<.999 && int(params.control.z)%8==7)p=mix(p,contact(p),1.0-pin);
        if(pin<.999 && int(params.control.z)%4==3)p+=hand_push(p,rest[id].y)*(1.0-pin);
        // A hand can pass through the middle of a coarse cloth triangle while
        // all its vertices are outside. Probe triangle interiors as well.
        if(pin<.999 && int(params.control.z)%8==7){
            uvec2 faces=tri_spans[id];vec3 face_correction=vec3(0);float hits=0;vec3 hand_correction=vec3(0);
            for(uint j=0;j<faces.y;j++){
                uvec3 ids=triangles[faces.x+j].xyz;
                vec3 center=(get_point(ids.x,even)+get_point(ids.y,even)+get_point(ids.z,even))/3.0;
                vec3 delta=contact(center)-center;
                if(dot(delta,delta)>1e-12){face_correction+=delta;hits+=1.0;}
                vec3 a=get_point(ids.x,even),b=get_point(ids.y,even),c=get_point(ids.z,even);
                float triangle_radius=max(max(length(a-center),length(b-center)),length(c-center));
                for(int hand=0;hand<int(params.settings.w);hand++){
                    vec3 hand_center=hands[hand*2].xyz;float radius=hands[hand*2].w+params.settings.y;
                    if(distance(center,hand_center)>radius+triangle_radius)continue;
                    vec3 q=triangle_point(hand_center,a,b,c);vec3 direction=q-hand_center;float distance=length(direction);
                    vec3 push=probe_push(q,rest[id].y,hand);
                    if(dot(push,push)>dot(hand_correction,hand_correction))hand_correction=push;
                }
            }
            if(hits>0.0)p+=face_correction/hits*(1.0-pin);
            p+=hand_correction*(1.0-pin);
        }
        if(even)pb[id]=vec4(p,1);else pa[id]=vec4(p,1);
        return;
    }
    if(mode==5){
        vec3 normal=vec3(0);uvec2 span=tri_spans[id];
        for(uint j=0;j<span.y;j++){
            uvec3 t=triangles[span.x+j].xyz;
            normal-=cross(pa[t.y].xyz-pa[t.x].xyz,pa[t.z].xyz-pa[t.x].xyz);
        }
        normals[id]=vec4(length(normal)>1e-10?normalize(normal):vec3(0,1,0),0);
    }
}
