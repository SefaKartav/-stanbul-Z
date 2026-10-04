class_name GameEnvironment
extends Node3D
## Gokyuzu, gunes, sis ve ortam isigi. Gun/gece dongusu bu dugumu surer.
##
## Sis yalnizca atmosfer degil: gorus yaricapinin (chunk akisi) kenarini
## gizler. Uzakta birden biten dunya yerine sise karisan silüet gorunur.

var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var world_environment: WorldEnvironment


func _ready() -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.52, 0.72)
	sky_material.sky_horizon_color = Color(0.72, 0.74, 0.74)
	sky_material.ground_horizon_color = Color(0.6, 0.6, 0.58)
	sky_material.ground_bottom_color = Color(0.2, 0.2, 0.2)
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	# YUMUSAK GORUNUM (29 Eylul 2026): AO daha genis ama hafif (koseler kir
	# degil golge), parlama yumusak, palet mat (dusuk doygunluk, kontrast ~1).
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.1
	environment.ssao_power = 1.3
	environment.ssao_detail = 0.3
	environment.ssao_sharpness = 0.9
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.glow_bloom = 0.03
	environment.glow_hdr_threshold = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.66, 0.68, 0.7)
	environment.fog_density = 0.0045
	environment.fog_sky_affect = 0.35
	environment.fog_sun_scatter = 0.15
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.86
	environment.adjustment_contrast = 0.98
	environment.adjustment_brightness = 1.02

	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.rotation_degrees = Vector3(-52, -38, 0)
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_energy = 0.0
	moon.light_color = Color(0.55, 0.62, 0.85)
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-60, 140, 0)
	add_child(moon)
	apply_quality()
	Settings.changed.connect(apply_quality)


func apply_quality() -> void:
	var q := Settings.shadow_quality
	sun.shadow_enabled = q > 0
	sun.directional_shadow_max_distance = [0.0, 60.0, 110.0, 160.0][q]
	environment.ssao_enabled = q >= 2
	# Yumusak golge: kenar bulanikligi + gunesin acisal boyu (yuksekte PCSS).
	sun.shadow_blur = [1.0, 1.4, 1.8, 1.6][q]
	sun.light_angular_distance = [0.0, 0.0, 0.0, 0.8][q]
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	apply_antialiasing(get_viewport())
	if Settings.legacy_look:
		sun.shadow_blur = 1.0
		sun.light_angular_distance = 0.0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		environment.ssao_radius = 1.2
		environment.ssao_intensity = 1.6
		environment.ssao_power = 1.5
		environment.ssao_detail = 0.5
		environment.ssao_sharpness = 0.98
	if not Settings.soft_look:
		environment.adjustment_saturation = 0.94
		environment.adjustment_contrast = 1.05
	else:
		environment.adjustment_saturation = 0.86
		environment.adjustment_contrast = 0.98
	var chunks := Settings.view_distance
	# DERINLIK sisi: yakin sokak net, yalnizca son chunk halkasi sise gomulur.
	# Ustel sis 25 m'deki binayi bile soldururdu.
	var reach := chunks * 16.0
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_density = 1.0
	environment.fog_depth_begin = reach * 0.45
	environment.fog_depth_end = reach * 0.95
	environment.fog_depth_curve = 1.6


static func apply_antialiasing(viewport: Viewport) -> void:
	## Kenar yumusatma (Ayarlar > Grafik): 0 kapali, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x.
	## MSAA voxel kenarlarini keskin tutarak merdivenlenmeyi giderir; FXAA
	## ucuzdur ama hafif bulaniktir.
	if viewport == null:
		return
	var mode := Settings.aa_mode
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][mode]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if mode == 1 else Viewport.SCREEN_SPACE_AA_DISABLED


func set_time_of_day(normalized: float, darkness: float) -> void:
	## normalized: 0..1 (0.5 = ogle). darkness: 0 gunduz .. 1 en koyu gece.
	var sun_angle := (normalized - 0.25) * TAU     # 06:00 dogar, 18:00 batar
	var elevation := sin(sun_angle)
	sun.rotation = Vector3(-maxf(0.08, elevation) * PI * 0.5 - 0.05, -0.65 + normalized * 0.8, 0)
	var day := clampf(1.0 - darkness, 0.0, 1.0)
	# Gunes ISIGI gercek yukseklige bagli: ufkun altindayken yanmaz. Gece
	# "biraz loş gunduz" degil, fenersiz gorulemeyen bir karanliktir.
	var sun_up := clampf(elevation * 4.0 + 0.25, 0.0, 1.0)
	sun.light_energy = lerpf(0.0, 1.3, smoothstep(0.05, 0.6, day)) * sun_up
	sun.visible = sun.light_energy > 0.02
	day *= lerpf(0.35, 1.0, sun_up)
	var dusk := clampf(1.0 - absf(elevation) * 3.0, 0.0, 1.0) * day
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.42), dusk)
	moon.light_energy = lerpf(0.0, 0.22, darkness)
	moon.visible = moon.light_energy > 0.02
	sky_material.sky_top_color = Color(0.05, 0.07, 0.14).lerp(Color(0.36, 0.52, 0.72), day)
	sky_material.sky_horizon_color = Color(0.1, 0.12, 0.18).lerp(Color(0.72, 0.74, 0.74), day).lerp(Color(0.9, 0.56, 0.4), dusk * 0.7)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color.darkened(0.15)
	environment.ambient_light_energy = lerpf(0.08, 0.9, day)
	environment.fog_light_color = Color(0.08, 0.09, 0.13).lerp(Color(0.66, 0.68, 0.7), day)
