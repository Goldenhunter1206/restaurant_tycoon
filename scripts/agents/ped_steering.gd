class_name PedSteering
extends RefCounted
## Cheap shared pedestrian steering (all static, no node): local
## separation between walkers, a hard push-out from vehicle hulls so
## walkers never clip through cars, plus a persistent per-agent lane
## offset so sidewalks read as loose two-way flows instead of a bead
## chain.

const AVOID_RADIUS: float = 1.1
const PUSH_CLAMP: float = 0.4
const LANE_OFFSET_MAX: float = 0.45
## Vehicle hull: a segment along the car's axis (half length) with a
## lateral clearance radius. 1.7 m keeps sidewalk lanes (>= 1.9 m from
## a parked car's centre line) free of constant pushing.
const CAR_HALF_LEN: float = 1.6
const CAR_AVOID_RADIUS: float = 1.7
const CAR_PUSH_CLAMP: float = 0.7


static func lateral_avoid(agent: Node3D) -> Vector3:
	## Push-away from pedestrians closer than AVOID_RADIUS plus a firmer
	## push-out from any vehicle hull the agent is about to clip.
	var pos: Vector3 = agent.global_position
	var push: Vector3 = Vector3.ZERO
	for other: Node3D in TrafficManager.peds_near(pos, AVOID_RADIUS):
		if other == agent:
			continue
		var rel: Vector3 = pos - other.global_position
		rel.y = 0.0
		var d: float = rel.length()
		if d < 0.01:
			continue
		push += rel * ((AVOID_RADIUS - d) / d)
	push.y = 0.0
	return push.limit_length(PUSH_CLAMP) + vehicle_avoid(pos)


static func vehicle_avoid(pos: Vector3) -> Vector3:
	## Push away from the closest point on each nearby car's spine
	## segment (centre +/- CAR_HALF_LEN along its facing axis). Parked
	## and moving cars both count — walkers flow around, never through.
	var push: Vector3 = Vector3.ZERO
	for car: Node3D in TrafficManager.cars_near(pos, CAR_AVOID_RADIUS + CAR_HALF_LEN):
		var fwd: Vector3 = car.global_transform.basis.z
		var rel: Vector3 = pos - car.global_position
		rel.y = 0.0
		var along: float = clampf(rel.dot(fwd), -CAR_HALF_LEN, CAR_HALF_LEN)
		var away: Vector3 = rel - fwd * along
		away.y = 0.0
		var d: float = away.length()
		if d < 0.05 or d >= CAR_AVOID_RADIUS:
			continue
		push += away * ((CAR_AVOID_RADIUS - d) / d)
	return push.limit_length(CAR_PUSH_CLAMP)


static func lane_offset_for(id_value: int) -> float:
	## Deterministic offset in [-LANE_OFFSET_MAX, LANE_OFFSET_MAX].
	var h: int = posmod(id_value * 2654435761, 1000)
	return (float(h) / 1000.0 * 2.0 - 1.0) * LANE_OFFSET_MAX


static func offset_target(target: Vector3, from_pos: Vector3, off: float) -> Vector3:
	## Shift the waypoint sideways relative to the walking direction; near
	## the waypoint the shift fades out so arrivals still converge.
	var dir: Vector3 = target - from_pos
	dir.y = 0.0
	if dir.length_squared() < 0.25:
		return target
	dir = dir.normalized()
	return target + Vector3(-dir.z, 0.0, dir.x) * off
