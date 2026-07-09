class_name ParkedCarPlacer
extends RefCounted
## Parks cars along a seeded fraction of block curb edges, parallel to the kerb,
## clear of intersection corners. One MultiMesh per car variant (via MeshBatch)
## gives colour variety across the fleet. Cars are .gltf and face +X at rest.
## Deterministic; built under a "ParkedCars" group.

const V := "res://Cartoon City Massive Megapack/gLTF 2/Vehicles/"

const CARS: Array[String] = [
	V + "Car 5/Car_5_A.gltf", V + "Car 5/Car_5_B.gltf", V + "Car 5/Car_5_C.gltf", V + "Car 5/Car_5_D.gltf",
	V + "Car 1/Car_1_A.gltf", V + "Car 1/Car_1_B.gltf",
	V + "Taxi/Taxi_1.gltf", V + "Taxi/Taxi_2.gltf",
]

const SEED: int = 141421356
const CAR_OFFSET: float = 1.1     # kerb-to-car-centre, into the road
const CAR_Y: float = 0.24     # car mesh sits ~0.24 m below its origin (wheels)
const CAR_SPACING: float = 5.5
const CORNER_CLEAR: float = 7.0   # keep clear of intersections / crosswalks
const EDGE_PROB: float = 0.38     # fraction of eligible curb edges that get a row
const GAP_PROB: float = 0.82      # per-slot fill (leaves natural gaps)


static func build(root: Node3D) -> int:
	var grp := Node3D.new()
	grp.name = "ParkedCars"
	root.add_child(grp)
	var cache := {}
	var car_x: Array = []
	for _c in CARS:
		car_x.append([])

	var v_removed := CityBuilder.removed_v_segments()
	var h_removed := CityBuilder.removed_h_segments()
	for bi in range(CityBuilder.BLOCKS):
		for bj in range(CityBuilder.BLOCKS):
			var dist := CityBuilder.district(bi, bj)
			if dist == "" or dist == "X":
				continue
			var x0 := CityBuilder.line_x(bi) + 4.0
			var x1 := CityBuilder.line_x(bi + 1) - 4.0
			var z0 := CityBuilder.line_z(bj) + 4.0
			var z1 := CityBuilder.line_z(bj + 1) - 4.0
			var rng := RandomNumberGenerator.new()
			rng.seed = SEED ^ ((bi * 40503 ^ bj * 73856093) * 2654435761)
			if not h_removed.has("%d,%d" % [bi, bj]):
				_car_row(car_x, rng, x0, x1, z0 - CAR_OFFSET, true)
			if not h_removed.has("%d,%d" % [bi, bj + 1]):
				_car_row(car_x, rng, x0, x1, z1 + CAR_OFFSET, true)
			if not v_removed.has("%d,%d" % [bi, bj]):
				_car_row(car_x, rng, z0, z1, x0 - CAR_OFFSET, false)
			if not v_removed.has("%d,%d" % [bi + 1, bj]):
				_car_row(car_x, rng, z0, z1, x1 + CAR_OFFSET, false)

	var total := 0
	for v in range(CARS.size()):
		var xs: Array = car_x[v]
		if xs.is_empty():
			continue
		total += xs.size()
		MeshBatch.emit(grp, "Car%d" % v, CARS[v], xs, cache)
	return total


static func _car_row(car_x: Array, rng: RandomNumberGenerator, a0: float, a1: float,
		fixed: float, along_x: bool) -> void:
	if rng.randf() >= EDGE_PROB:
		return
	if a1 - a0 < 2.0 * CORNER_CLEAR + CAR_SPACING:
		return
	var t: float = a0 + CORNER_CLEAR + rng.randf_range(0.0, 3.0)
	while t < a1 - CORNER_CLEAR:
		if rng.randf() < GAP_PROB:
			var pos: Vector3 = Vector3(t, CAR_Y, fixed) if along_x else Vector3(fixed, CAR_Y, t)
			var v: int = rng.randi_range(0, CARS.size() - 1)
			var yaw: float
			if along_x:
				yaw = 0.0 if rng.randf() < 0.5 else PI
			else:
				yaw = PI * 0.5 if rng.randf() < 0.5 else -PI * 0.5
			car_x[v].append(Transform3D(Basis(Vector3.UP, yaw), pos))
		t += CAR_SPACING + rng.randf_range(0.0, 2.5)
