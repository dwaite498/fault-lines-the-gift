class_name ArrowCurve
## Curve math for order arrows. Pure and deterministic.

const BOW := 0.15


## Quadratic Bezier from a to b; the control point is the midpoint pushed BOW*length
## to the right of travel (clockwise), so a->b and b->a bow apart. samples points,
## the last one moved `stop` px back from b along the curve.
static func single_hop(a: Vector2, b: Vector2, samples := 20, stop := 6.0) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var ctrl := (a + b) * 0.5 + Vector2(-dir.y, dir.x) * a.distance_to(b) * BOW
	var pts := PackedVector2Array()
	for i in samples:
		var t := float(i) / (samples - 1)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return _trim(pts, stop)


## Uniform Catmull-Rom through centers (ends duplicated), with each segment bowed
## BOW*length to the right of travel at its middle. The bow uses 16t^2(1-t)^2, which
## has zero slope at the centers, so the path stays smooth through them.
## One point = nothing; two = single_hop. samples = points per segment.
static func through(centers: PackedVector2Array, samples := 16, stop := 6.0) -> PackedVector2Array:
	if centers.size() < 2:
		return PackedVector2Array()
	if centers.size() == 2:
		return single_hop(centers[0], centers[1], samples, stop)
	var segs := centers.size() - 1
	var pts := PackedVector2Array()
	for k in segs:
		var p0 := centers[maxi(k - 1, 0)]
		var p1 := centers[k]
		var p2 := centers[k + 1]
		var p3 := centers[mini(k + 2, segs)]
		var dir := (p2 - p1).normalized()
		var bow := Vector2(-dir.y, dir.x) * p1.distance_to(p2) * BOW
		for i in samples:
			var t := float(i) / samples
			var cr := 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)
			pts.append(cr + bow * 16.0 * t * t * (1.0 - t) * (1.0 - t))
	pts.append(centers[segs])
	return _trim(pts, stop)


## Ends the polyline `stop` px short of its last point, along the final tangent.
## Points closer than that are dropped first, so the last segment never reverses
## (that reversal made arrowheads point backwards).
static func _trim(pts: PackedVector2Array, stop: float) -> PackedVector2Array:
	var n := pts.size()
	var end := pts[n - 1]
	var dir := (end - pts[n - 2]).normalized()
	while pts.size() > 2 and pts[pts.size() - 2].distance_to(end) <= stop:
		pts.remove_at(pts.size() - 1)
	pts[pts.size() - 1] = end - dir * stop
	return pts


## Index in a through() result where the path reaches center `step` (the end of
## this turn's moves), given the number of centers and of returned points.
static func split_index(centers: int, step: int, points: int) -> int:
	if centers <= 2:
		return points - 1 if step >= 1 else 0
	return mini(step * (points - 1) / (centers - 1), points - 1)


## +1 if mid-curve lies right of travel a->b (screen coords), -1 left.
static func bow_side(pts: PackedVector2Array) -> int:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var m := pts[pts.size() / 2]
	var cross := (b - a).cross(m - a)
	return 1 if cross > 0.0 else -1
