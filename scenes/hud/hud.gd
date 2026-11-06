extends CanvasLayer

var health_bar    : ProgressBar
var health_label  : Label
var score_label   : Label
var lat_label     : Label
var lon_label     : Label
var joy_label     : Label
var game_over_lbl : Label
var takeoff_label : Label
var target_lbl    : Label
var missile_label : Label
var lock_label    : Label
var engine_label  : Label
var mute_label    : Label
var kills_label   : Label
var _muted        : bool = false

# ── Horizonte Artificial ──────────────────────────────────────────────────────
class AttitudeIndicator extends Control:
	func _process(_d: float) -> void: queue_redraw()

	func _draw() -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var basis  : Basis   = player.global_transform.basis
		var fwd    : Vector3 = -basis.z
		var pitch  : float   = asin(clamp(fwd.y, -1.0, 1.0))
		var roll   : float   = atan2(basis.x.y, basis.y.y)

		var w   : float = size.x
		var h   : float = size.y
		var cx  : float = w * 0.5
		var cy  : float = h * 0.5
		var pxd : float = h / 50.0
		var hy  : float = rad_to_deg(pitch) * pxd

		# Fondo negro
		draw_rect(Rect2(0.0, 0.0, w, h), Color.BLACK)

		# ── Cielo y Tierra: polígonos clippeados al rect del control ──
		# Un punto de control (px,py) está en el "cielo" si:
		#   (px-cx)*sin(roll) + (py-cy)*cos(roll) < hy
		var sr : float = sin(roll)
		var cr : float = cos(roll)
		var rv := PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(0.0, h)
		])
		var sky_pts := PackedVector2Array()
		var gnd_pts := PackedVector2Array()
		for i in 4:
			var A := rv[i]
			var B := rv[(i + 1) % 4]
			var dA : float = (A.x - cx) * sr + (A.y - cy) * cr - hy
			var dB : float = (B.x - cx) * sr + (B.y - cy) * cr - hy
			if dA < 0.0: sky_pts.append(A)
			else:        gnd_pts.append(A)
			if (dA < 0.0) != (dB < 0.0):
				var ip := A.lerp(B, dA / (dA - dB))
				sky_pts.append(ip)
				gnd_pts.append(ip)
		if sky_pts.size() >= 3:
			draw_colored_polygon(sky_pts, Color(0.07, 0.32, 0.72))
		if gnd_pts.size() >= 3:
			draw_colored_polygon(gnd_pts, Color(0.42, 0.26, 0.07))

		# ── Horizonte y escalera de cabeceo (en espacio rotado) ──
		var R : float = Vector2(cx, cy).length() + 4.0
		draw_set_transform(Vector2(cx, cy), -roll)
		# Línea de horizonte
		draw_line(Vector2(-R, hy), Vector2(R, hy),
				  Color(1.0, 1.0, 1.0, 0.95), 2.0)

		# Escala de cabeceo
		var fnt := ThemeDB.fallback_font
		for deg in range(-25, 26, 5):
			if deg == 0: continue
			var y    : float = hy + float(-deg) * pxd
			var len2 : float = 48.0 if abs(deg) % 10 == 0 else 26.0
			var alp  : float = 0.80 if abs(deg) % 10 == 0 else 0.40
			draw_line(Vector2(-len2, y), Vector2(len2, y),
					  Color(1.0, 1.0, 1.0, alp), 1.5)
			if abs(deg) % 10 == 0:
				var tick : float = 6.0 if deg > 0 else -6.0
				draw_line(Vector2(-len2, y), Vector2(-len2, y + tick),
						  Color(1.0, 1.0, 1.0, alp), 1.5)
				draw_line(Vector2(len2, y), Vector2(len2, y + tick),
						  Color(1.0, 1.0, 1.0, alp), 1.5)
				draw_string(fnt, Vector2(-len2 - 22.0, y + 4.0), str(abs(deg)),
							HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
							Color(1.0, 1.0, 1.0, 0.75))
				draw_string(fnt, Vector2(len2 + 4.0, y + 4.0), str(abs(deg)),
							HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
							Color(1.0, 1.0, 1.0, 0.75))

		# ── OVERLAY FIJO ──
		draw_set_transform(Vector2.ZERO, 0.0)

		# Símbolo de avión (amarillo fijo)
		var sym := Color(1.0, 0.95, 0.1)
		draw_line(Vector2(cx - 55.0, cy), Vector2(cx - 10.0, cy), sym, 3.0)
		draw_line(Vector2(cx + 10.0, cy), Vector2(cx + 55.0, cy), sym, 3.0)
		draw_circle(Vector2(cx, cy), 4.0, sym)
		draw_line(Vector2(cx, cy - 12.0), Vector2(cx, cy), sym, 2.0)

		# Arco de banco
		var arc_r   : float = cx * 0.80
		var arc_col         := Color(0.75, 0.9, 0.75, 0.70)
		draw_arc(Vector2(cx, cy), arc_r,
				 deg_to_rad(-150.0), deg_to_rad(-30.0), 60, arc_col, 1.5)

		# Ticks de banco (fijos)
		for ang in [-60.0, -45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0, 60.0]:
			var rad2 : float = -PI * 0.5 + deg_to_rad(ang)
			var d    : Vector2 = Vector2(cos(rad2), sin(rad2))
			var tl   : float = 11.0 if int(abs(ang)) % 30 == 0 else 6.0
			draw_line(Vector2(cx, cy) + d * (arc_r - tl),
					  Vector2(cx, cy) + d * arc_r, arc_col, 1.5)

		# Puntero de banco (móvil)
		var roll_rad : float = -PI * 0.5 - roll
		var dir  : Vector2 = Vector2(cos(roll_rad), sin(roll_rad))
		var perp : Vector2 = Vector2(-dir.y, dir.x)
		var tip  : Vector2 = Vector2(cx, cy) + dir * arc_r
		draw_colored_polygon(PackedVector2Array([
			tip,
			tip + perp * 6.0 - dir * 13.0,
			tip - perp * 6.0 - dir * 13.0
		]), Color(1.0, 1.0, 1.0, 0.92))

		# Ángulos en esquinas
		draw_string(fnt, Vector2(5.0, 15.0),
					"P%+.0f°" % rad_to_deg(pitch),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					Color(0.4, 1.0, 0.5) if pitch >= 0.0 else Color(1.0, 0.5, 0.3))
		draw_string(fnt, Vector2(w - 46.0, 15.0),
					"R%+.0f°" % (-rad_to_deg(roll)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					Color(0.9, 0.9, 0.4))

		# Marco EFIS
		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.1, 0.65, 0.2, 0.8), false, 1.5)


# ── Cinta de Velocidad ────────────────────────────────────────────────────────
class SpeedTape extends Control:
	func _process(_d: float) -> void: queue_redraw()

	func _draw() -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var spd : float = player.speed * 3.6  # km/h
		var w   : float = size.x
		var h   : float = size.y
		var cx  : float = w * 0.5
		var cy  : float = h * 0.5
		var pxd : float = h / 120.0            # px por km/h

		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.03, 0.0, 0.88))

		var fnt := ThemeDB.fallback_font
		var base : int = int(floor((spd - 65.0) / 20.0)) * 20
		for s in range(base - 20, base + 160, 20):
			if s < 0: continue
			var y : float = cy + (spd - float(s)) * pxd
			if y < 2.0 or y > h - 2.0: continue
			draw_line(Vector2(w - 10.0, y), Vector2(w - 1.0, y),
					  Color(0.5, 0.9, 0.5, 0.8), 1.0)
			draw_string(fnt, Vector2(2.0, y + 4.0), "%d" % s,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
						Color(0.65, 1.0, 0.65))

		# Caja de velocidad actual
		draw_rect(Rect2(0.0, cy - 13.0, w, 26.0), Color(0.0, 0.0, 0.0, 0.9))
		draw_rect(Rect2(0.0, cy - 13.0, w, 26.0),
				  Color(0.1, 0.85, 0.3, 0.95), false, 1.5)
		draw_string(fnt, Vector2(3.0, cy + 6.0), "%d" % int(spd),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

		# Etiqueta
		draw_string(fnt, Vector2(2.0, 11.0), "IAS",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					Color(0.4, 0.9, 0.5, 0.75))
		draw_string(fnt, Vector2(2.0, h - 2.0), "km/h",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
					Color(0.4, 0.8, 0.5, 0.6))
		draw_rect(Rect2(0.0, 0.0, w, h),
				  Color(0.1, 0.65, 0.2, 0.7), false, 1.0)


# ── Cinta de Altitud ──────────────────────────────────────────────────────────
class AltitudeTape extends Control:
	var _prev_alt : float = 0.0
	var _vspd     : float = 0.0

	func _process(delta: float) -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if is_instance_valid(player):
			var alt   : float = player.global_position.y
			_vspd = (alt - _prev_alt) / max(delta, 0.001)
			_prev_alt = alt
		queue_redraw()

	func _draw() -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var alt : float = player.global_position.y
		var w   : float = size.x
		var h   : float = size.y
		var cy  : float = h * 0.5
		var pxd : float = h / 300.0  # px por metro

		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.03, 0.0, 0.88))

		var fnt  := ThemeDB.fallback_font
		var base : int = int(floor((alt - 160.0) / 50.0)) * 50
		for a in range(base - 50, base + 350, 50):
			var y : float = cy + (alt - float(a)) * pxd
			if y < 2.0 or y > h - 2.0: continue
			draw_line(Vector2(1.0, y), Vector2(10.0, y),
					  Color(0.5, 0.9, 0.5, 0.8), 1.0)
			draw_string(fnt, Vector2(12.0, y + 4.0), "%d" % a,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
						Color(0.65, 1.0, 0.65))

		# Caja de altitud actual
		draw_rect(Rect2(0.0, cy - 13.0, w, 26.0), Color(0.0, 0.0, 0.0, 0.9))
		draw_rect(Rect2(0.0, cy - 13.0, w, 26.0),
				  Color(0.1, 0.85, 0.3, 0.95), false, 1.5)
		draw_string(fnt, Vector2(3.0, cy + 6.0), "%d" % int(alt),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

		# Variación de altitud
		var vs_col := Color(0.3, 1.0, 0.5) if _vspd >= 0.0 else Color(1.0, 0.45, 0.2)
		var vs_sym : String = "▲" if _vspd > 1.0 else ("▼" if _vspd < -1.0 else "─")
		draw_string(fnt, Vector2(w - 16.0, cy + 6.0), vs_sym,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vs_col)
		if abs(_vspd) > 1.0:
			draw_string(fnt, Vector2(2.0, h - 2.0), "%+.0fm/s" % _vspd,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9, vs_col)

		draw_string(fnt, Vector2(2.0, 11.0), "ALT",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					Color(0.4, 0.9, 0.5, 0.75))
		draw_rect(Rect2(0.0, 0.0, w, h),
				  Color(0.1, 0.65, 0.2, 0.7), false, 1.0)


# ── Indicador de Motor ────────────────────────────────────────────────────────
class ThrottleGauge extends Control:
	func _process(_d: float) -> void: queue_redraw()

	func _draw() -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var thr  : float = player.throttle if player.get("throttle") != null else 0.0
		var w    : float = size.x
		var h    : float = size.y
		var cx   : float = w * 0.5
		var cy   : float = h * 0.5
		var r    : float = min(cx, cy) - 8.0
		var fnt          := ThemeDB.fallback_font

		# Fondo
		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.03, 0.0, 0.85))

		# Pista de fondo (arco gris)
		draw_arc(Vector2(cx, cy), r, deg_to_rad(135.0), deg_to_rad(405.0), 64,
				 Color(0.08, 0.15, 0.08), 7.0)

		# Relleno (verde → naranja → rojo)
		if thr > 0.0:
			var fill_end : float = deg_to_rad(135.0) + thr * deg_to_rad(270.0)
			var fill_col : Color
			if thr < 0.70:
				fill_col = Color(0.1, 0.9, 0.3)
			elif thr < 0.88:
				fill_col = Color(0.9, 0.55, 0.1)
			else:
				fill_col = Color(1.0, 0.18, 0.05)
			draw_arc(Vector2(cx, cy), r, deg_to_rad(135.0), fill_end, 64, fill_col, 7.0)

		# Ticks de referencia (25%, 50%, 75%, 100%)
		for pct in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var ta  : float = deg_to_rad(135.0) + pct * deg_to_rad(270.0)
			var td  : Vector2 = Vector2(cos(ta), sin(ta))
			draw_line(Vector2(cx, cy) + td * (r - 10.0),
					  Vector2(cx, cy) + td * (r + 2.0),
					  Color(0.6, 0.8, 0.6, 0.6), 1.5)

		# Aguja
		if thr > 0.0:
			var na   : float = deg_to_rad(135.0) + thr * deg_to_rad(270.0)
			var nd   : Vector2 = Vector2(cos(na), sin(na))
			draw_line(Vector2(cx, cy), Vector2(cx, cy) + nd * (r - 2.0),
					  Color.WHITE, 2.0)

		# Valor central
		draw_string(fnt, Vector2(cx - 14.0, cy + 5.0),
					"%d%%" % int(thr * 100.0),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		draw_string(fnt, Vector2(cx - 10.0, cy + 18.0), "ENG",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					Color(0.4, 0.9, 0.5, 0.8))

		# Marco
		draw_rect(Rect2(0.0, 0.0, w, h),
				  Color(0.1, 0.65, 0.2, 0.65), false, 1.0)


# ── Brújula ───────────────────────────────────────────────────────────────────
class CompassDisplay extends Control:
	func _process(_d: float) -> void: queue_redraw()

	func _draw() -> void:
		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var fwd_v   : Vector3 = -player.global_transform.basis.z
		var heading : float   = fmod(rad_to_deg(atan2(fwd_v.x, -fwd_v.z)) + 360.0, 360.0)

		var w   : float = size.x
		var h   : float = size.y
		var cx  : float = w * 0.5
		var fnt         := ThemeDB.fallback_font
		var pxd : float = w / 90.0

		draw_rect(Rect2(0.0, 0.0, w, h), Color(0.0, 0.03, 0.0, 0.84))
		draw_line(Vector2(0.0, h - 1.0), Vector2(w, h - 1.0),
				  Color(0.1, 0.65, 0.2, 0.6), 1.0)

		var int_hdg : int = int(heading)
		for i in range(int_hdg - 50, int_hdg + 51):
			if i % 5 != 0: continue
			var deg_w : int = ((i % 360) + 360) % 360
			var x     : float = cx + float(i - int_hdg) * pxd
			if x < 2.0 or x > w - 2.0: continue
			var card := _card(deg_w)
			if card != "":
				draw_line(Vector2(x, 2.0), Vector2(x, h * 0.58),
						  Color(0.1, 1.0, 0.35, 0.9), 2.0)
				draw_string(fnt, Vector2(x - 6.0, h - 4.0), card,
							HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 1.0, 0.4))
			elif deg_w % 30 == 0:
				draw_line(Vector2(x, 2.0), Vector2(x, h * 0.42),
						  Color(0.3, 0.85, 0.4, 0.8), 1.0)
				draw_string(fnt, Vector2(x - 9.0, h - 4.0), "%03d" % deg_w,
							HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
							Color(0.4, 0.9, 0.5, 0.75))
			elif deg_w % 10 == 0:
				draw_line(Vector2(x, 2.0), Vector2(x, h * 0.28),
						  Color(0.2, 0.75, 0.3, 0.6), 1.0)
			else:
				draw_line(Vector2(x, 2.0), Vector2(x, h * 0.16),
						  Color(0.15, 0.6, 0.25, 0.4), 1.0)

		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, h - 2.0), Vector2(cx - 8.0, 4.0), Vector2(cx + 8.0, 4.0)
		]), Color(1.0, 0.9, 0.1, 0.92))
		draw_rect(Rect2(cx - 24.0, 1.0, 48.0, h * 0.38), Color(0.0, 0.0, 0.0, 0.78))
		draw_string(fnt, Vector2(cx - 19.0, h * 0.35), "%03d°" % int(heading),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.95, 0.1))

	static func _card(deg: int) -> String:
		match deg:
			0:   return "N"
			45:  return "NE"
			90:  return "E"
			135: return "SE"
			180: return "S"
			225: return "SW"
			270: return "W"
			315: return "NW"
		return ""


# ── Radar ─────────────────────────────────────────────────────────────────────
class RadarDisplay extends Control:
	const RADAR_R     : float = 82.0
	const WORLD_RANGE : float = 700.0

	func _process(_d: float) -> void: queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, RADAR_R + 4.0, Color(0.0, 0.0, 0.0, 0.88))
		for pct in [0.33, 0.66]:
			draw_arc(c, RADAR_R * float(pct), 0.0, TAU, 40,
					 Color(0.0, 0.55, 0.15, 0.35), 1.0)
		draw_arc(c, RADAR_R, 0.0, TAU, 72, Color(0.1, 0.9, 0.3, 0.9), 2.0)
		var gc := Color(0.0, 0.55, 0.15, 0.3)
		draw_line(c + Vector2(0.0, -RADAR_R), c + Vector2(0.0, RADAR_R), gc, 1.0)
		draw_line(c + Vector2(-RADAR_R, 0.0), c + Vector2(RADAR_R, 0.0), gc, 1.0)

		var st := Engine.get_main_loop() as SceneTree
		if not st: return
		var player : Node3D = st.get_first_node_in_group("player") as Node3D
		if not is_instance_valid(player): return

		var basis : Basis   = player.global_transform.basis
		var fwd   : Vector3 = -basis.z
		var right : Vector3 =  basis.x
		var sc    : float   = RADAR_R / WORLD_RANGE
		var fnt           := ThemeDB.fallback_font

		# Norte
		var nw  : Vector3 = Vector3(0.0, 0.0, -1.0)
		var nsc := Vector2(nw.dot(right), -nw.dot(fwd)).normalized()
		var np  := c + nsc * (RADAR_R - 8.0)
		draw_line(c, np, Color(1.0, 0.25, 0.1, 0.85), 2.0)
		draw_circle(np, 5.0, Color(1.0, 0.2, 0.1))
		draw_string(fnt, np + Vector2(-4.0, 5.0), "N",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.9))

		for cd in [["E", Vector3(1,0,0)], ["S", Vector3(0,0,1)], ["W", Vector3(-1,0,0)]]:
			var wd  : Vector3 = cd[1]
			var csc := Vector2(wd.dot(right), -wd.dot(fwd)).normalized()
			draw_string(fnt, c + csc * (RADAR_R - 8.0) + Vector2(-4.0, 4.0),
						cd[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
						Color(0.4, 0.9, 0.5, 0.75))

		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -9.0), c + Vector2(6.0, 6.0), c + Vector2(-6.0, 6.0)
		]), Color(0.25, 1.0, 0.4))

		for e in st.get_nodes_in_group("enemy"):
			if not is_instance_valid(e): continue
			var rel  : Vector3 = (e as Node3D).global_position - player.global_position
			var rx   : float   = rel.dot(right)
			var rz   : float   = rel.dot(fwd)
			var dalt : float   = rel.y
			var bp   := c + Vector2(rx, -rz) * sc
			var dv   := bp - c
			if dv.length() > RADAR_R - 4.0:
				bp = c + dv.normalized() * (RADAR_R - 4.0)
			var r2 : float = clamp(4.5 + dalt * 0.012, 2.5, 7.0)
			draw_circle(bp, r2 + 1.5, Color(0.0, 0.0, 0.0, 0.5))
			draw_circle(bp, r2, Color(1.0, 0.18, 0.05))
			draw_circle(bp, r2 * 0.4, Color(1.0, 0.65, 0.1))

		draw_string(fnt, c + Vector2(-RADAR_R, RADAR_R + 2.0), "%dm" % int(WORLD_RANGE),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.2, 0.8, 0.3, 0.6))


# ── Construcción ──────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_P and ke.pressed and not ke.echo:
			_toggle_mute()

func _toggle_mute() -> void:
	_muted = not _muted
	if _muted:
		AudioServer.set_bus_volume_db(0, -INF)
		mute_label.text = "[P] MUDO"
		mute_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.1, 0.95))
	else:
		AudioServer.set_bus_volume_db(0, 0.0)
		mute_label.text = "[P] SON"
		mute_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5, 0.80))

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Panel de fondo (franja oscura en la parte inferior) ──
	var bg := ColorRect.new()
	bg.color        = Color(0.0, 0.02, 0.0, 0.84)
	bg.anchor_left  = 0.0;  bg.anchor_right  = 1.0
	bg.anchor_top   = 1.0;  bg.anchor_bottom = 1.0
	bg.offset_left  = 0;    bg.offset_right  = 0
	bg.offset_top   = -228; bg.offset_bottom = 0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var sep := ColorRect.new()
	sep.color        = Color(0.1, 0.65, 0.2, 0.55)
	sep.anchor_left  = 0.0;  sep.anchor_right  = 1.0
	sep.anchor_top   = 1.0;  sep.anchor_bottom = 1.0
	sep.offset_top   = -228; sep.offset_bottom = -226
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sep)

	# ── Brújula (franja completa, parte baja del panel) ──
	var compass := CompassDisplay.new()
	compass.anchor_left  = 0.0;  compass.anchor_right  = 1.0
	compass.anchor_top   = 1.0;  compass.anchor_bottom = 1.0
	compass.offset_left  = 0;    compass.offset_right  = 0
	compass.offset_top   = -52;  compass.offset_bottom = 0
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(compass)

	# ── Radar (izquierda del panel) ──
	var radar := RadarDisplay.new()
	radar.anchor_left  = 0.0;  radar.anchor_right  = 0.0
	radar.anchor_top   = 1.0;  radar.anchor_bottom = 1.0
	radar.offset_left  = 5;    radar.offset_right  = 200
	radar.offset_top   = -225; radar.offset_bottom = -55
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar)

	# ── Cinta de velocidad (izquierda del AI) ──
	var spd_tape := SpeedTape.new()
	spd_tape.anchor_left  = 0.5;  spd_tape.anchor_right  = 0.5
	spd_tape.anchor_top   = 1.0;  spd_tape.anchor_bottom = 1.0
	spd_tape.offset_left  = -232; spd_tape.offset_right  = -162
	spd_tape.offset_top   = -225; spd_tape.offset_bottom = -55
	spd_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spd_tape)

	# ── Horizonte artificial (centro del panel, con clip) ──
	var ai_wrap := Control.new()
	ai_wrap.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	ai_wrap.anchor_left   = 0.5;  ai_wrap.anchor_right  = 0.5
	ai_wrap.anchor_top    = 1.0;  ai_wrap.anchor_bottom = 1.0
	ai_wrap.offset_left   = -158; ai_wrap.offset_right  = 158
	ai_wrap.offset_top    = -225; ai_wrap.offset_bottom = -55
	ai_wrap.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(ai_wrap)

	var ai := AttitudeIndicator.new()
	ai.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ai.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ai_wrap.add_child(ai)

	# ── Cinta de altitud (derecha del AI) ──
	var alt_tape := AltitudeTape.new()
	alt_tape.anchor_left  = 0.5;  alt_tape.anchor_right  = 0.5
	alt_tape.anchor_top   = 1.0;  alt_tape.anchor_bottom = 1.0
	alt_tape.offset_left  = 162;  alt_tape.offset_right  = 232
	alt_tape.offset_top   = -225; alt_tape.offset_bottom = -55
	alt_tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(alt_tape)

	# ── Medidor de motor (derecha del alt) ──
	var eng_gauge := ThrottleGauge.new()
	eng_gauge.anchor_left  = 0.5;  eng_gauge.anchor_right  = 0.5
	eng_gauge.anchor_top   = 1.0;  eng_gauge.anchor_bottom = 1.0
	eng_gauge.offset_left  = 237;  eng_gauge.offset_right  = 337
	eng_gauge.offset_top   = -225; eng_gauge.offset_bottom = -120
	eng_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(eng_gauge)

	# ── Misiles (columna derecha del panel) ──
	missile_label = Label.new()
	missile_label.text = "● ● ● ●"
	missile_label.add_theme_font_size_override("font_size", 16)
	missile_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.1))
	missile_label.anchor_left  = 1.0;  missile_label.anchor_right  = 1.0
	missile_label.anchor_top   = 1.0;  missile_label.anchor_bottom = 1.0
	missile_label.offset_left  = -255; missile_label.offset_right  = -5
	missile_label.offset_top   = -120; missile_label.offset_bottom = -97
	missile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(missile_label)

	var mis_lbl := _add_label(root, "MSLS", Rect2(0, 0, 60, 14))
	mis_lbl.anchor_left  = 1.0;  mis_lbl.anchor_right  = 1.0
	mis_lbl.anchor_top   = 1.0;  mis_lbl.anchor_bottom = 1.0
	mis_lbl.offset_left  = -255; mis_lbl.offset_right  = -195
	mis_lbl.offset_top   = -97;  mis_lbl.offset_bottom = -83
	mis_lbl.add_theme_font_size_override("font_size", 10)

	# ── LAT / LON (columna derecha) ──
	lat_label = _add_label(root, "LAT  28.0000° N", Rect2(0, 0, 250, 20))
	lat_label.anchor_left  = 1.0;  lat_label.anchor_right  = 1.0
	lat_label.anchor_top   = 1.0;  lat_label.anchor_bottom = 1.0
	lat_label.offset_left  = -255; lat_label.offset_right  = -5
	lat_label.offset_top   = -82;  lat_label.offset_bottom = -63
	lat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lat_label.add_theme_font_size_override("font_size", 12)
	lat_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))

	lon_label = _add_label(root, "LON  15.4000° W", Rect2(0, 0, 250, 20))
	lon_label.anchor_left  = 1.0;  lon_label.anchor_right  = 1.0
	lon_label.anchor_top   = 1.0;  lon_label.anchor_bottom = 1.0
	lon_label.offset_left  = -255; lon_label.offset_right  = -5
	lon_label.offset_top   = -62;  lon_label.offset_bottom = -55
	lon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lon_label.add_theme_font_size_override("font_size", 12)
	lon_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65))

	# ── Salud (esquina superior izquierda) ──
	health_bar = _add_bar(root, Rect2(10, 10, 200, 14), Color(0.1, 0.8, 0.2))
	health_bar.value = 100
	health_label = _add_label(root, "HP: 100", Rect2(10, 26, 200, 16))
	health_label.add_theme_font_size_override("font_size", 11)

	# ── Puntuación (esquina superior derecha) ──
	score_label = _add_label(root, "SCORE: 0", Rect2(0, 0, 300, 32))
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	score_label.position = Vector2(-310, 10)
	score_label.size     = Vector2(300, 32)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 24)

	# ── Contador de destruidos ──
	kills_label = Label.new()
	kills_label.text = "DESTRUIDOS: 0"
	kills_label.add_theme_font_size_override("font_size", 15)
	kills_label.add_theme_color_override("font_color", Color(1.0, 0.70, 0.15))
	kills_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	kills_label.add_theme_constant_override("shadow_offset_x", 2)
	kills_label.add_theme_constant_override("shadow_offset_y", 2)
	kills_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	kills_label.position = Vector2(-310, 42)
	kills_label.size     = Vector2(300, 22)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(kills_label)

	# ── Silencio (esquina superior derecha) ──
	mute_label = Label.new()
	mute_label.text = "[P] SON"
	mute_label.add_theme_font_size_override("font_size", 11)
	mute_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5, 0.80))
	mute_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mute_label.position = Vector2(-130, 48)
	mute_label.size     = Vector2(120, 18)
	mute_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(mute_label)

	# ── Info joystick (esquina superior derecha) ──
	joy_label = _add_label(root, "", Rect2(0, 0, 310, 65))
	joy_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	joy_label.position = Vector2(-320, 68)
	joy_label.size     = Vector2(310, 65)
	joy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	joy_label.add_theme_font_size_override("font_size", 10)

	# ── Mira ──
	_add_crosshair(root)

	# ── Indicador de enganche ──
	lock_label = Label.new()
	lock_label.text = ""
	lock_label.add_theme_font_size_override("font_size", 16)
	lock_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
	lock_label.anchor_left   = 0.5; lock_label.anchor_right  = 0.5
	lock_label.anchor_top    = 0.5; lock_label.anchor_bottom = 0.5
	lock_label.offset_left   = -120; lock_label.offset_right  = 120
	lock_label.offset_top    = 90;   lock_label.offset_bottom = 116
	lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_label.hide()
	root.add_child(lock_label)

	# ── Objetivo 3D→2D ──
	target_lbl = Label.new()
	target_lbl.text = "[  ]"
	target_lbl.add_theme_font_size_override("font_size", 26)
	target_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
	target_lbl.size = Vector2(70, 32)
	target_lbl.hide()
	root.add_child(target_lbl)

	# ── Instrucción despegue (justo encima del panel) ──
	takeoff_label = Label.new()
	takeoff_label.text = "[ ACELERA PARA DESPEGAR  —  W  /  gases joystick ]"
	takeoff_label.add_theme_font_size_override("font_size", 20)
	takeoff_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	takeoff_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	takeoff_label.add_theme_constant_override("shadow_offset_x", 2)
	takeoff_label.add_theme_constant_override("shadow_offset_y", 2)
	takeoff_label.anchor_left   = 0.5; takeoff_label.anchor_right  = 0.5
	takeoff_label.anchor_top    = 1.0; takeoff_label.anchor_bottom = 1.0
	takeoff_label.offset_left   = -440; takeoff_label.offset_right  = 440
	takeoff_label.offset_top    = -282; takeoff_label.offset_bottom = -246
	takeoff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(takeoff_label)

	# ── Estado motor ──
	engine_label = Label.new()
	engine_label.text = "MOTOR APAGADO  —  [ Enter ] o [ Espacio ] para arrancar"
	engine_label.add_theme_font_size_override("font_size", 22)
	engine_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
	engine_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	engine_label.add_theme_constant_override("shadow_offset_x", 2)
	engine_label.add_theme_constant_override("shadow_offset_y", 2)
	engine_label.anchor_left   = 0.5; engine_label.anchor_right  = 0.5
	engine_label.anchor_top    = 0.5; engine_label.anchor_bottom = 0.5
	engine_label.offset_left   = -380; engine_label.offset_right  = 380
	engine_label.offset_top    = -18;  engine_label.offset_bottom = 18
	engine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(engine_label)

	# ── Game over ──
	game_over_lbl = Label.new()
	game_over_lbl.text = "DERRIBADO\nReiniciando..."
	game_over_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game_over_lbl.position = Vector2(-200, -60)
	game_over_lbl.size     = Vector2(400, 120)
	game_over_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	game_over_lbl.add_theme_font_size_override("font_size", 48)
	game_over_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	game_over_lbl.hide()
	root.add_child(game_over_lbl)


# ── Proceso ───────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var eng_on      : bool  = player.get("engine_on")    == true
		var eng_startup : float = player.get("_eng_startup") if player.get("_eng_startup") != null else 0.0

		# LAT / LON
		var osm = get_tree().get_first_node_in_group("osm_tiles")
		var lat   : float = 28.0
		var lon_v : float = -15.4
		if is_instance_valid(osm) and osm.has_method("get_coords"):
			var origin : Vector2 = osm.get_coords()
			var tm     : float   = osm.get_tile_meters()
			if tm > 0.0:
				var lat_per_m : float = 1.0 / 111320.0
				var lon_per_m : float = 1.0 / (111320.0 * cos(deg_to_rad(origin.x)))
				lat   = origin.x + player.global_position.z * (-lat_per_m)
				lon_v = origin.y + player.global_position.x * lon_per_m
		else:
			lat   = 28.0 + (player.global_position.z * -0.0001)
			lon_v = -15.4 + (player.global_position.x *  0.0001)
		lat_label.text = "LAT  %.4f° %s" % [abs(lat), ("N" if lat >= 0.0 else "S")]
		lon_label.text = "LON  %.4f° %s" % [abs(lon_v), ("E" if lon_v >= 0.0 else "W")]

		# Estado motor
		if eng_on:
			engine_label.hide()
			takeoff_label.visible = (player.get("on_ground") == true)
		elif eng_startup > 0.0:
			var pct : int = int(clamp(eng_startup / 1.5, 0.0, 1.0) * 100.0)
			engine_label.text = "ARRANCANDO...  %d%%" % pct
			engine_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
			engine_label.show()
			takeoff_label.hide()
		else:
			engine_label.text = "MOTOR APAGADO  —  [ Enter ] o [ Espacio ] para arrancar"
			engine_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
			engine_label.show()
			takeoff_label.hide()

		# Misiles
		var ml      : int   = player.get("_missiles_left")   if player.get("_missiles_left")   != null else 4
		var lt      : float = player.get("_lock_timer")       if player.get("_lock_timer")       != null else 0.0
		var lk_time : float = player.get("missile_lock_time") if player.get("missile_lock_time") != null else 1.5
		var locked_tgt      = player.get("_locked_target")
		var dots := ""
		for i in 4:
			dots += ("● " if i < ml else "○ ")
		missile_label.text = dots.strip_edges()

		if is_instance_valid(locked_tgt) and ml > 0:
			if lt >= lk_time:
				lock_label.text = "▶  BLOQUEADO  ◀"
				lock_label.add_theme_color_override("font_color", Color(0.1, 1.0, 0.2))
			else:
				lock_label.text = "ADQUIRIENDO  %d%%" % int((lt / lk_time) * 100.0)
				lock_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
			lock_label.show()
		else:
			lock_label.hide()

	# Joystick / teclado info
	if Input.get_connected_joypads().size() > 0:
		joy_label.text = "%s\nX:%.2f  Y:%.2f\nZ:%.2f  Th:%.2f" % [
			Input.get_joy_name(0),
			Input.get_joy_axis(0, 0), Input.get_joy_axis(0, 1),
			Input.get_joy_axis(0, 2), Input.get_joy_axis(0, 3)
		]
	else:
		joy_label.text = "↑↓←→ rotar  Q/E guiñar\nW/S/PgUp/PgDn gases  F boost\nEsp=fuego  M=misil"

	# Indicador objetivo
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return
	var nearest      : Node3D = null
	var nearest_dist : float  = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e): continue
		var d : float = (e as Node3D).global_position.distance_to(camera.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e as Node3D
	if is_instance_valid(nearest) and camera.is_position_in_frustum(nearest.global_position):
		var sp      := camera.unproject_position(nearest.global_position)
		var vp_size := get_viewport().get_visible_rect().size
		target_lbl.position = sp + Vector2(-35.0, -16.0)
		target_lbl.add_theme_color_override("font_color",
			Color(0.1, 1.0, 0.2) if (sp - vp_size * 0.5).length() < 70.0 else Color(1.0, 0.3, 0.1))
		target_lbl.show()
	else:
		target_lbl.hide()


# ── API pública ───────────────────────────────────────────────────────────────
func update_health(value: int) -> void:
	health_bar.value  = value
	health_label.text = "HP: %d" % value
	health_bar.modulate = Color(0.1, 0.8, 0.2) if value > 40 else Color(0.9, 0.2, 0.1)

func update_score(value: int) -> void:
	score_label.text = "SCORE: %d" % value

func update_kills(value: int) -> void:
	kills_label.text = "DESTRUIDOS: %d" % value

func show_game_over() -> void:
	game_over_lbl.show()


# ── Helpers ───────────────────────────────────────────────────────────────────
func _add_crosshair(root: Control) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.8)
	for x in [[-24, -7], [7, 24]]:
		var bar := ColorRect.new()
		bar.color = col
		bar.anchor_left = 0.5; bar.anchor_right  = 0.5
		bar.anchor_top  = 0.5; bar.anchor_bottom = 0.5
		bar.offset_left = x[0]; bar.offset_right  = x[1]
		bar.offset_top  = -1;   bar.offset_bottom = 1
		root.add_child(bar)
	for y in [[-24, -7], [7, 24]]:
		var bar := ColorRect.new()
		bar.color = col
		bar.anchor_left = 0.5; bar.anchor_right  = 0.5
		bar.anchor_top  = 0.5; bar.anchor_bottom = 0.5
		bar.offset_left = -1;  bar.offset_right  = 1
		bar.offset_top  = y[0]; bar.offset_bottom = y[1]
		root.add_child(bar)

func _add_bar(parent: Control, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position        = rect.position
	bar.size            = rect.size
	bar.max_value       = 100
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = color
	bar.add_theme_stylebox_override("fill", style)
	parent.add_child(bar)
	return bar

func _add_label(parent: Control, text: String, rect: Rect2) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = rect.position
	lbl.size     = rect.size
	lbl.add_theme_color_override("font_color",        Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(lbl)
	return lbl
