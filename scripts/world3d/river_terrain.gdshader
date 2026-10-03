shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform float terrain_saturation = 1.;
uniform vec4 base_color : source_color = vec4(1.);
uniform vec2 base_tile = vec2(2.);
uniform float base_roughness = .9;
uniform float base_metallic = 0.;
uniform float base_strength = 1.;
uniform sampler2D base_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 sand_color : source_color = vec4(1.);
uniform vec2 sand_tile = vec2(2.);
uniform float sand_roughness = .9;
uniform float sand_metallic = 0.;
uniform float sand_strength = 1.;
uniform sampler2D sand_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 rock_color : source_color = vec4(1.);
uniform vec2 rock_tile = vec2(2.);
uniform float rock_roughness = .9;
uniform float rock_metallic = 0.;
uniform float rock_strength = 1.;
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool base_has_height = false;
uniform bool base_has_albedo = false;
uniform bool base_has_rough = false;
uniform bool base_has_metal = false;
uniform bool base_has_ao = false;
uniform bool sand_has_height = false;
uniform bool sand_has_albedo = false;
uniform bool sand_has_rough = false;
uniform bool sand_has_metal = false;
uniform bool sand_has_ao = false;
uniform bool rock_has_height = false;
uniform bool rock_has_albedo = false;
uniform bool rock_has_rough = false;
uniform bool rock_has_metal = false;
uniform bool rock_has_ao = false;
uniform vec4 soil_color : source_color = vec4(1.);
uniform vec2 soil_tile = vec2(2.);
uniform float soil_roughness = .9;
uniform float soil_metallic = 0.;
uniform float soil_strength = 1.;
uniform sampler2D soil_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_height : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool soil_has_height = false;
uniform bool soil_has_albedo = false;
uniform bool soil_has_rough = false;
uniform bool soil_has_metal = false;
uniform bool soil_has_ao = false;
uniform vec4 region_a_color : source_color = vec4(1.);
uniform vec2 region_a_tile = vec2(2.);
uniform float region_a_roughness = .9;
uniform float region_a_metallic = 0.;
uniform float region_a_strength = 1.;
uniform sampler2D region_a_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_a_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_a_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_a_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_a_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool region_a_has_albedo = false;
uniform bool region_a_has_rough = false;
uniform bool region_a_has_metal = false;
uniform bool region_a_has_ao = false;
uniform vec4 region_b_color : source_color = vec4(1.);
uniform vec2 region_b_tile = vec2(2.);
uniform float region_b_roughness = .9;
uniform float region_b_metallic = 0.;
uniform float region_b_strength = 1.;
uniform sampler2D region_b_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_b_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_b_metal : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_b_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool region_b_has_albedo = false;
uniform bool region_b_has_rough = false;
uniform bool region_b_has_metal = false;
uniform bool region_b_has_ao = false;
uniform bool ground_enabled = false;
uniform sampler2D ground_mask : filter_linear, repeat_disable;
uniform sampler2DArray batch_ground_masks : filter_linear, repeat_disable;
uniform float transition_width = 0.;
uniform float edge_noise = .3;
uniform float height_blend_strength = .5;
uniform sampler2D terrain_heights : filter_linear, repeat_disable;
uniform vec2 terrain_span = vec2(32.);
uniform bool batch_enabled = false;
uniform sampler2DArray batch_heights : filter_linear, repeat_disable;
uniform vec4 batch_origins[16];
uniform vec4 batch_spans[16];
uniform float water_level = -1.5;
uniform float shore_start = .25;
uniform float shore_end = 1.3;
uniform float rock_start = .6;
uniform float rock_end = 2.2;
uniform bool slope_aware = false;
uniform bool depth_enabled = true;
uniform float steep_start = 40.;
uniform float steep_end = 65.;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 local_position;
varying vec3 axis_x;
varying vec3 axis_y;
varying vec3 axis_z;
varying flat float height_layer;
varying flat vec2 local_span;
void vertex() {
	local_position=VERTEX;
	axis_x=MODEL_MATRIX[0].xyz; axis_y=MODEL_MATRIX[1].xyz; axis_z=MODEL_MATRIX[2].xyz;
	height_layer=CUSTOM0.r; local_span=terrain_span;
	if (batch_enabled) {
		int layer=int(CUSTOM0.r); vec4 span=batch_spans[layer];
		vec3 p=VERTEX-batch_origins[layer].xyz;
		local_position=vec3(span.z*p.x-span.w*p.z,p.y,span.w*p.x+span.z*p.z);
		axis_x=(MODEL_MATRIX*vec4(span.z,0.,-span.w,0.)).xyz;
		axis_z=(MODEL_MATRIX*vec4(span.w,0.,span.z,0.)).xyz;
		local_span=span.xy;
	}
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
vec3 projection_weights(vec3 geometric_normal) {
	vec3 w=pow(abs(geometric_normal),vec3(8.));
	return w/max(.00001,w.x+w.y+w.z);
}
vec4 sample_surface(sampler2D tex, vec2 tile, vec3 geometric_normal) {
	if (!slope_aware) { return texture(tex,world_position.xz/tile); }
	vec3 w=projection_weights(geometric_normal); vec4 result=vec4(0.);
	if (w.x>.00001) { result+=texture(tex,world_position.zy/tile)*w.x; }
	if (w.y>.00001) { result+=texture(tex,world_position.xz/tile)*w.y; }
	if (w.z>.00001) { result+=texture(tex,world_position.xy/tile)*w.z; }
	return result;
}
vec3 bump(sampler2D tex, vec2 uv, float strength) {
	vec3 n=texture(tex,uv).rgb*2.-1.;
	return vec3(n.xy*strength/max(.1,n.z),0.);
}
vec3 surface_normal(sampler2D tex, vec2 tile, float strength, vec3 geometric_normal) {
	vec3 n=geometric_normal; vec3 w=projection_weights(n); vec3 perturb=vec3(0.);
	if (w.x>.00001) { vec3 b=bump(tex,world_position.zy/tile,strength); perturb+=vec3(0.,b.y,b.x)*w.x; }
	if (w.y>.00001) { vec3 b=bump(tex,world_position.xz/tile,strength); perturb+=vec3(b.x,0.,b.y)*w.y; }
	if (w.z>.00001) { vec3 b=bump(tex,world_position.xy/tile,strength); perturb+=vec3(b.x,b.y,0.)*w.z; }
	return normalize(n+perturb-n*dot(perturb,n));
}
float terrain_height(vec2 p) {
	if (batch_enabled) {
		vec2 resolution=vec2(textureSize(batch_heights,0).xy);
		vec2 uv=(clamp(p/local_span+.5,0.,1.)*(resolution-1.)+.5)/resolution;
		return textureLod(batch_heights,vec3(uv,height_layer),0.).r;
	}
	vec2 resolution=vec2(textureSize(terrain_heights,0));
	vec2 uv=(clamp(p/terrain_span+.5,0.,1.)*(resolution-1.)+.5)/resolution;
	return textureLod(terrain_heights,uv,0.).r;
}
float hash_point(vec3 p) {
	p=fract(p*vec3(.1031,.11369,.13787));
	p+=dot(p,p.yzx+19.19);
	return fract((p.x+p.y)*p.z);
}
float variation(vec3 p) {
	vec3 cell=floor(p); vec3 f=fract(p); f=f*f*(3.-2.*f);
	return mix(mix(mix(hash_point(cell),hash_point(cell+vec3(1,0,0)),f.x),mix(hash_point(cell+vec3(0,1,0)),hash_point(cell+vec3(1,1,0)),f.x),f.y),mix(mix(hash_point(cell+vec3(0,0,1)),hash_point(cell+vec3(1,0,1)),f.x),mix(hash_point(cell+vec3(0,1,1)),hash_point(cell+vec3(1,1,1)),f.x),f.y),f.z);
}
vec4 height_weights(vec4 weights,vec3 n) {
	if (height_blend_strength<=0. || max(max(weights.x,weights.y),max(weights.z,weights.w))>.99999) { return weights; }
	vec4 heights=vec4(.5);
	if (base_has_height && weights.x>.00001) { heights.x=sample_surface(base_height,base_tile,n).r; }
	if (sand_has_height && weights.y>.00001) { heights.y=sample_surface(sand_height,sand_tile,n).r; }
	if (rock_has_height && weights.z>.00001) { heights.z=sample_surface(rock_height,rock_tile,n).r; }
	if (soil_has_height && weights.w>.00001) { heights.w=sample_surface(soil_height,soil_tile,n).r; }
	vec4 scores=mix(vec4(-1000.),weights+(heights-.5)*height_blend_strength,step(vec4(.00001),weights));
	float peak=max(max(scores.x,scores.y),max(scores.z,scores.w));
	vec4 shaped=max(scores-peak+.32,0.)*weights;
	// Strength also controls sharpening. Otherwise a tiny nonzero strength still
	// clips the soft coverage to a hard cutout, especially on gentle shorelines.
	return mix(weights,shaped/max(.00001,shaped.x+shaped.y+shaped.z+shaped.w),height_blend_strength);
}
void fragment() {
	vec3 up=normalize(world_normal);
	// At near-vertical cuts, interpolated crest normals stretch grass and XZ UVs
	// down long triangles. Use the true face normal increasingly on steep faces.
	vec3 face_normal=normalize(cross(dFdx(world_position),dFdy(world_position)));
	if (dot(face_normal,up)<0.) { face_normal=-face_normal; }
	float face_steep=1.-smoothstep(cos(radians(steep_end)),cos(radians(steep_start)),abs(face_normal.y));
	vec3 projection_normal=normalize(mix(up,face_normal,face_steep));
	float depth=water_level-world_position.y;
	float land=smoothstep(shore_start,shore_end,-depth);
	float stone=smoothstep(rock_start,rock_end,depth)*(1.-land);
	vec4 weights=vec4(land,1.-land-stone,stone,0.);
	if (!depth_enabled) { weights=vec4(1.,0.,0.,0.); }
	if (slope_aware) {
		float steep=1.-smoothstep(cos(radians(steep_end)),cos(radians(steep_start)),abs(projection_normal.y));
		float rim=0.; float grass_rim=0.; float foot=0.; float noise=0.;
		if (transition_width>0.) {
			// Material coverage is a continuous, metre-scale heightfield query.
			// It is independent of the face normal used to prevent UV stretching.
			float r=transition_width; vec2 p=local_position.xz;
			float hx0=terrain_height(p-vec2(r,0)); float hx1=terrain_height(p+vec2(r,0));
			float hz0=terrain_height(p-vec2(0,r)); float hz1=terrain_height(p+vec2(0,r));
			vec3 sx=axis_x*(2.*r)+axis_y*(hx1-hx0);
			vec3 sz=axis_z*(2.*r)+axis_y*(hz1-hz0);
			vec3 coverage_normal=normalize(cross(sz,sx));
			noise=(variation(world_position*.85)*.7+variation(world_position*3.7)*.3-.5)*2.*edge_noise;
			float angle=degrees(acos(clamp(abs(coverage_normal.y),0.,1.)))+noise*12.;
			steep=smoothstep(steep_start,steep_end,angle);
			vec4 neighbors=vec4(hx0,hx1,hz0,hz1)*axis_y.y+vec4(-r*axis_x.y,r*axis_x.y,-r*axis_z.y,r*axis_z.y);
			float crest=max(max(neighbors.x,neighbors.y),max(neighbors.z,neighbors.w));
			float bottom=min(min(neighbors.x,neighbors.y),min(neighbors.z,neighbors.w));
			float y=local_position.y*axis_y.y;
			rim=1.-smoothstep(-.2*r,1.5*r,crest-y+noise*r*2.);
			grass_rim=1.-smoothstep(-.35*r,.55*r,crest-y+noise*r*2.);
			foot=1.-smoothstep(.08*r,.85*r,y-bottom-noise*r);
			// Don't cover steep cut faces several metres below their source surface.
			float below=max(0.,terrain_height(p)-local_position.y)*abs(axis_y.y);
			steep=max(steep,face_steep*smoothstep(.25*r,r,below));
			if (depth_enabled) {
				// Gentle shores also expose soil between grass and sediment. Perturb
				// coverage in world metres, not patch UVs, so adjacent chunks agree.
				// The bounded offset cannot paint grass across deep riverbeds.
				float bank_height=-depth+noise*min(.45,r*.25);
				land=smoothstep(shore_start,shore_end,bank_height);
				stone=smoothstep(rock_start,rock_end,depth)*(1.-land);
				float soil=4.*land*(1.-land)*.75;
				weights=vec4(land,1.-land-stone,stone,0.);
				weights.xy*=1.-soil;
				weights.w=soil*(1.-stone);
			}
		}
		weights=mix(weights,vec4(0.,0.,1.,0.),steep);
		if (transition_width>0.) {
			float dry_bank=depth_enabled?smoothstep(-.35,.6,-depth):1.;
			float soil_cover=clamp(rim*(1.-grass_rim*.65)*.65+foot*.5,0.,.85)*steep;
			float grass_cover=grass_rim*.75*steep*dry_bank;
			weights.z-=min(weights.z,soil_cover+grass_cover);
			weights.w+=soil_cover; weights.x+=grass_cover;
			weights/=max(.00001,weights.x+weights.y+weights.z+weights.w);
			weights=height_weights(weights,projection_normal);
		}
	}
	// Evaluate only layers that survived coverage + height blending. Full PBR stays
	// together, without sampling invisible layers on large flat/rock-only regions.
	ALBEDO=vec3(0.); ROUGHNESS=0.; METALLIC=0.; AO=0.;
	vec3 surface=vec3(0.);
	vec2 region_weights=vec2(0.);
	if (ground_enabled && weights.x>.00001) {
		vec2 resolution=vec2(textureSize(ground_mask,0));
		if (batch_enabled) { resolution=vec2(textureSize(batch_ground_masks,0).xy); }
		vec2 uv=(clamp(local_position.xz/local_span+.5,0.,1.)*(resolution-1.)+.5)/resolution;
		vec2 coverage=batch_enabled?textureLod(batch_ground_masks,vec3(uv,height_layer),0.).rg:textureLod(ground_mask,uv,0.).rg;
		float edge_variation=(variation(world_position*.65)-.5)*.35;
		coverage=clamp(coverage+edge_variation*4.*coverage*(1.-coverage),0.,1.);
		coverage/=max(1.,coverage.x+coverage.y);
		region_weights=weights.x*coverage;
		weights.x*=max(0.,1.-coverage.x-coverage.y);
	}
	if (weights.x>.00001) {
		vec3 base_pigment=(base_has_albedo?sample_surface(base_albedo,base_tile,projection_normal).rgb:vec3(1.))*base_color.rgb;
		base_pigment=mix(vec3(dot(base_pigment,vec3(.2126,.7152,.0722))),base_pigment,terrain_saturation);
		ALBEDO+=base_pigment*weights.x;
		ROUGHNESS+=(base_has_rough?sample_surface(base_rough,base_tile,projection_normal).r:1.)*base_roughness*weights.x;
		if (base_metallic>0.) { METALLIC+=(base_has_metal?sample_surface(base_metal,base_tile,projection_normal).r:1.)*base_metallic*weights.x; }
		AO+=(base_has_ao?sample_surface(base_ao,base_tile,projection_normal).r:1.)*weights.x;
		if (slope_aware) {
			surface+=(base_strength>0.?surface_normal(base_normal,base_tile,base_strength,projection_normal):projection_normal)*weights.x;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (base_strength>0.) { n=texture(base_normal,world_position.xz/base_tile).rgb*2.-1.; n=normalize(vec3(n.xy*base_strength,max(.01,n.z))); }
			surface+=n*weights.x;
		}
	}
	if (region_weights.x>.00001) {
		ALBEDO+=(region_a_has_albedo?sample_surface(region_a_albedo,region_a_tile,projection_normal).rgb:vec3(1.))*region_a_color.rgb*region_weights.x;
		ROUGHNESS+=(region_a_has_rough?sample_surface(region_a_rough,region_a_tile,projection_normal).r:1.)*region_a_roughness*region_weights.x;
		if (region_a_metallic>0.) { METALLIC+=(region_a_has_metal?sample_surface(region_a_metal,region_a_tile,projection_normal).r:1.)*region_a_metallic*region_weights.x; }
		AO+=(region_a_has_ao?sample_surface(region_a_ao,region_a_tile,projection_normal).r:1.)*region_weights.x;
		if (slope_aware) {
			surface+=(region_a_strength>0.?surface_normal(region_a_normal,region_a_tile,region_a_strength,projection_normal):projection_normal)*region_weights.x;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (region_a_strength>0.) { n=texture(region_a_normal,world_position.xz/region_a_tile).rgb*2.-1.; n=normalize(vec3(n.xy*region_a_strength,max(.01,n.z))); }
			surface+=n*region_weights.x;
		}
	}
	if (region_weights.y>.00001) {
		ALBEDO+=(region_b_has_albedo?sample_surface(region_b_albedo,region_b_tile,projection_normal).rgb:vec3(1.))*region_b_color.rgb*region_weights.y;
		ROUGHNESS+=(region_b_has_rough?sample_surface(region_b_rough,region_b_tile,projection_normal).r:1.)*region_b_roughness*region_weights.y;
		if (region_b_metallic>0.) { METALLIC+=(region_b_has_metal?sample_surface(region_b_metal,region_b_tile,projection_normal).r:1.)*region_b_metallic*region_weights.y; }
		AO+=(region_b_has_ao?sample_surface(region_b_ao,region_b_tile,projection_normal).r:1.)*region_weights.y;
		if (slope_aware) {
			surface+=(region_b_strength>0.?surface_normal(region_b_normal,region_b_tile,region_b_strength,projection_normal):projection_normal)*region_weights.y;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (region_b_strength>0.) { n=texture(region_b_normal,world_position.xz/region_b_tile).rgb*2.-1.; n=normalize(vec3(n.xy*region_b_strength,max(.01,n.z))); }
			surface+=n*region_weights.y;
		}
	}
	if (weights.y>.00001) {
		ALBEDO+=(sand_has_albedo?sample_surface(sand_albedo,sand_tile,projection_normal).rgb:vec3(1.))*sand_color.rgb*weights.y;
		ROUGHNESS+=(sand_has_rough?sample_surface(sand_rough,sand_tile,projection_normal).r:1.)*sand_roughness*weights.y;
		if (sand_metallic>0.) { METALLIC+=(sand_has_metal?sample_surface(sand_metal,sand_tile,projection_normal).r:1.)*sand_metallic*weights.y; }
		AO+=(sand_has_ao?sample_surface(sand_ao,sand_tile,projection_normal).r:1.)*weights.y;
		if (slope_aware) {
			surface+=(sand_strength>0.?surface_normal(sand_normal,sand_tile,sand_strength,projection_normal):projection_normal)*weights.y;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (sand_strength>0.) { n=texture(sand_normal,world_position.xz/sand_tile).rgb*2.-1.; n=normalize(vec3(n.xy*sand_strength,max(.01,n.z))); }
			surface+=n*weights.y;
		}
	}
	if (weights.z>.00001) {
		ALBEDO+=(rock_has_albedo?sample_surface(rock_albedo,rock_tile,projection_normal).rgb:vec3(1.))*rock_color.rgb*weights.z;
		ROUGHNESS+=(rock_has_rough?sample_surface(rock_rough,rock_tile,projection_normal).r:1.)*rock_roughness*weights.z;
		if (rock_metallic>0.) { METALLIC+=(rock_has_metal?sample_surface(rock_metal,rock_tile,projection_normal).r:1.)*rock_metallic*weights.z; }
		AO+=(rock_has_ao?sample_surface(rock_ao,rock_tile,projection_normal).r:1.)*weights.z;
		if (slope_aware) {
			surface+=(rock_strength>0.?surface_normal(rock_normal,rock_tile,rock_strength,projection_normal):projection_normal)*weights.z;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (rock_strength>0.) { n=texture(rock_normal,world_position.xz/rock_tile).rgb*2.-1.; n=normalize(vec3(n.xy*rock_strength,max(.01,n.z))); }
			surface+=n*weights.z;
		}
	}
	if (weights.w>.00001) {
		ALBEDO+=(soil_has_albedo?sample_surface(soil_albedo,soil_tile,projection_normal).rgb:vec3(1.))*soil_color.rgb*weights.w;
		ROUGHNESS+=(soil_has_rough?sample_surface(soil_rough,soil_tile,projection_normal).r:1.)*soil_roughness*weights.w;
		if (soil_metallic>0.) { METALLIC+=(soil_has_metal?sample_surface(soil_metal,soil_tile,projection_normal).r:1.)*soil_metallic*weights.w; }
		AO+=(soil_has_ao?sample_surface(soil_ao,soil_tile,projection_normal).r:1.)*weights.w;
		if (slope_aware) {
			surface+=(soil_strength>0.?surface_normal(soil_normal,soil_tile,soil_strength,projection_normal):projection_normal)*weights.w;
		} else {
			vec3 n=vec3(0.,0.,1.);
			if (soil_strength>0.) { n=texture(soil_normal,world_position.xz/soil_tile).rgb*2.-1.; n=normalize(vec3(n.xy*soil_strength,max(.01,n.z))); }
			surface+=n*weights.w;
		}
	}
	if (!slope_aware) {
		vec3 tangent=normalize(vec3(1.,0.,0.)-up*up.x);
		vec3 bitangent=normalize(cross(tangent,up));
		surface=tangent*surface.x+bitangent*surface.y+up*surface.z;
	}
	NORMAL=normalize((VIEW_MATRIX*vec4(surface,0.)).xyz);
}
