// BC5 stores tangent-space XY only. Other textures retain their authored Z.
vec3 decode_surface_normal(vec3 encoded, bool xy_only) {
	vec3 normal=encoded*2.-1.;
	if (xy_only) { normal.z=sqrt(max(0.,1.-dot(normal.xy,normal.xy))); }
	return normal;
}
