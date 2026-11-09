extends RefCounted
## Delay the observed mixer-consumption timeline, including its plateaus.
## Unlike subtracting a constant sample count, this reaches the final sample after
## output drains and continues correctly through an underrun/rebuffer pause.
var points: Array[Vector2] = []
var audible := 0.0
func sample(now: float, consumed_seconds: float, output_latency: float) -> float:
	if points.is_empty(): points.append(Vector2(now, 0.0))
	points.append(Vector2(now, consumed_seconds))
	var target := now - maxf(0.0,output_latency)
	while points.size() > 2 and points[1].x <= target: points.pop_front()
	while points.size() > 256: points.pop_front()
	var value := float(points[0].y)
	if target < points[0].x: value = 0.0
	elif points.size() > 1:
		var width := float(points[1].x-points[0].x)
		var weight := clampf((target-points[0].x)/width,0.0,1.0) if width > 0.0 else 1.0
		value = lerpf(points[0].y,points[1].y,weight)
	audible = minf(consumed_seconds,maxf(audible,value))
	return audible
