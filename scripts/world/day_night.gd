class_name DayNight
extends Node
## Drives the sun, sky and ambient light from GameClock.game_hours.
## Attach to Main; expects sibling nodes "Sun" (DirectionalLight3D) and
## "WorldEnvironment".

const SUNRISE: float = 6.0
const SUNSET: float = 20.0

@onready var _sun: DirectionalLight3D = get_parent().get_node("Sun")
@onready var _world_env: WorldEnvironment = get_parent().get_node("WorldEnvironment")

var _sky_mat: ProceduralSkyMaterial


func _ready() -> void:
	var env := _world_env.environment
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		_sky_mat = env.sky.sky_material


func _process(_delta: float) -> void:
	var h: float = GameClock.game_hours
	var daylight := _daylight_factor(h)
	# Sun elevation: 0 at sunrise/sunset, peak at solar noon.
	var day_frac := clampf((h - SUNRISE) / (SUNSET - SUNRISE), 0.0, 1.0)
	var elevation := sin(day_frac * PI) * 65.0 + 4.0
	var azimuth := lerpf(-70.0, 70.0, day_frac)
	_sun.rotation_degrees = Vector3(-maxf(elevation, 4.0), azimuth - 30.0, 0)
	_sun.light_energy = lerpf(0.12, 1.25, daylight)
	_sun.light_color = Color(1.0, lerpf(0.75, 0.97, daylight), lerpf(0.6, 0.92, daylight))

	var env := _world_env.environment
	# Keep nights readable: moonlit-blue ambient instead of near-black.
	env.ambient_light_energy = lerpf(0.6, 1.0, daylight)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if daylight < 0.5 else Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.55, 0.62, 0.85)
	if _sky_mat:
		var day_top := Color(0.35, 0.58, 0.92)
		var day_hor := Color(0.78, 0.86, 0.95)
		var night_top := Color(0.02, 0.04, 0.10)
		var night_hor := Color(0.07, 0.09, 0.16)
		var dusk_hor := Color(0.95, 0.62, 0.38)
		var t := daylight
		_sky_mat.sky_top_color = night_top.lerp(day_top, t)
		var horizon := night_hor.lerp(day_hor, t)
		# Warm horizon near sunrise/sunset.
		var dusk_amount := clampf(1.0 - absf(t - 0.5) * 2.0, 0.0, 1.0)
		horizon = horizon.lerp(dusk_hor, dusk_amount * 0.7)
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = horizon


func _daylight_factor(h: float) -> float:
	## 0 at night, 1 at full day, smooth 1h ramps at sunrise/sunset.
	if h < SUNRISE - 0.5 or h > SUNSET + 0.5:
		return 0.0
	if h < SUNRISE + 0.5:
		return smoothstep(SUNRISE - 0.5, SUNRISE + 0.5, h)
	if h > SUNSET - 0.5:
		return 1.0 - smoothstep(SUNSET - 0.5, SUNSET + 0.5, h)
	return 1.0
