class_name Sfx
extends RefCounted

# Звуки генерируются кодом (нет внешних аудиофайлов).
static var cache := {}


static func make(freq: float, dur: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := pow(1.0 - float(i) / n, 2.0)
		var s := sin(TAU * freq * t) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clamp(s * env, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


static func for_weapon(i: int) -> AudioStreamWAV:
	if not cache.has(i):
		var params := [
			[900.0, 0.15, 0.9],
			[600.0, 0.08, 0.7],
			[150.0, 0.35, 0.95],
			[1200.0, 0.4, 0.5],
		]
		var p = params[i]
		cache[i] = make(p[0], p[1], p[2])
	return cache[i]
