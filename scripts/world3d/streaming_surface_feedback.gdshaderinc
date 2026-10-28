// Match Godot 4.8's material feedback convention: 4096 reference size, 16x
// anisotropic footprint. Callers supply derivatives of ACTUAL sampled UVs.
float rmmo_streaming_footprint(vec2 dx,vec2 dy) {
	float x=dot(dx,dx),y=dot(dy,dy);
	return max(min(x,y),max(x,y)/256.);
}
float rmmo_streaming_lod(float footprint) {
	return .5*log2(max(footprint,1e-30))+12.;
}
