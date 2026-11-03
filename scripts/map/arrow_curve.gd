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


## Uniform Catmull-Rom through centers, ends duplicated.
## One point = nothing; two = single_hop.
static func through(centers: PackedVector2Array, samples := 24, stop := 6.0) -> PackedVector2Array:
	if centers.size() < 2:
		return PackedVector2Array()
	if centers.size() == 2:
		return single_hop(centers[0], centers[1], samples, stop)
	var segs := centers.size() - 1
	var pts := PackedVector2Array()
	for i in samples:
		var u := float(i) / (samples - 1) * segs
		var k := mini(int(u), segs - 1)
		var t := u - k
		var p0 := centers[maxi(k - 1, 0)]
		var p1 := centers[k]
		var p2 := centers[k + 1]
		var p3 := centers[mini(k + 2, segs)]
		pts.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	return _trim(pts, stop)


## Pulls the last point `stop` px back along the end tangent.
static func _trim(pts: PackedVector2Array, stop: float) -> PackedVector2Array:
	var n := pts.size()
	var dir := (pts[n - 1] - pts[n - 2]).normalized()
	pts[n - 1] = pts[n - 1] - dir * stop
	return pts


## +1 if mid-curve lies right of travel a->b (screen coords), -1 left.
static func bow_side(pts: PackedVector2Array) -> int:
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var m := pts[pts.size() / 2]
	var cross := (b - a).cross(m - a)
	return 1 if cross > 0.0 else -1
