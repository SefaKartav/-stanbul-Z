// Saydam voxel yuzeyleri (cam, su, korkuluk). Opak yuzeylerden ayri
// cizilir ki derinlik siralamasi opak dunyayi bozmasin.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, diffuse_lambert, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray crack_tex : source_color, filter_nearest, repeat_enable;
uniform float time_scale = 1.0;
uniform float distance_soften = 0.0;
uniform float matte = 0.0;

void fragment() {
	vec2 uv = UV;
	float bias = distance_soften * smoothstep(10.0, 70.0, length(VERTEX));
	vec4 base = texture(albedo_tex, vec3(uv, UV2.x), bias);
	if (base.a < 0.02) {
		discard;
	}
	float stage = UV2.y;
	if (stage > 0.5) {
		vec4 crack = texture(crack_tex, vec3(uv, stage));
		base.rgb = mix(base.rgb, vec3(0.9), crack.a * 0.8);
		base.a = max(base.a, crack.a * 0.9);
	}
	ALBEDO = base.rgb * COLOR.rgb;
	ALPHA = base.a;
	ROUGHNESS = mix(0.08, 0.2, matte);
	SPECULAR = mix(0.6, 0.4, matte);
}
