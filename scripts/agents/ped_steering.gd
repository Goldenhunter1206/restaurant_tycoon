class_name PedSteering
extends RefCounted
## Cheap shared pedestrian steering (all static, no node): local
## separation between walkers plus a persistent per-agent lane offset so
## sidewalks read as loose two-way flows instead of a bead chain.

const AVOID_RADIUS: float = 1.1
const PUSH_CLAMP: float = 0.4
const LANE_OFFSET_MAX: float = 0.45


static func lateral_avoid(agent: Node3D) -> Vector3:
	## Sum of push-away vectors from pedestrians closer than AVOID_RADIUS.
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
	return push.limit_length(PUSH_CLAMP)


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
