// Opak voxel yuzeyleri.
// UV: blok biriminde doku koordinati; UV2.x: doku katmani; UV2.y: hasar kademesi.
// COLOR.rgb: kose AO'su x blok tonu (ChunkMesher).
//
// YUMUSAK GORUNUM (29 Eylul 2026): `matte` renk doygunlugunu ve piksel
// kontrastini hafifce bastirir (mat palet); `distance_soften` uzaktaki
// yuzeyde bir ust mip seviyesini (ortalanmis renk) secer -- 16 px desen
// uzakta kum gibi titresmez. Yakin plan pixel-art olarak kalir.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray crack_tex : source_color, filter_nearest, repeat_enable;
uniform float distance_soften = 0.0;   // 0 = kapali; 1-2 = uzakta mip yanliligi
uniform float matte = 0.0;             // 0 = ham; 1 = tam mat palet

void fragment() {
	float dist = length(VERTEX);
	float bias = distance_soften * smoothstep(10.0, 70.0, dist);
	vec4 base = texture(albedo_tex, vec3(UV, UV2.x), bias);
	float stage = UV2.y;
	if (stage > 0.5) {
		vec4 crack = texture(crack_tex, vec3(UV, stage));
		base.rgb = mix(base.rgb, base.rgb * 0.25, crack.a);
		// Hasar arttikca yuzey tozlanir/kararir: uzaktan da okunur.
		base.rgb *= 1.0 - 0.06 * stage;
	}
	vec3 color = base.rgb * COLOR.rgb;
	if (matte > 0.0) {
		float lum = dot(color, vec3(0.299, 0.587, 0.114));
		color = mix(color, vec3(lum), 0.12 * matte);                 // hafif soluk
		color = mix(color, vec3(lum * 0.35 + 0.18), 0.06 * matte);   // kontrast yumusar
	}
	ALBEDO = color;
	ROUGHNESS = 0.96;
	SPECULAR = mix(0.18, 0.1, matte);
}
