class_name Player
extends CharacterBody3D

# Оружие: 4 штуки
const WEAPONS := [
	{"name": "Пистолет", "dmg": 25.0, "rate": 0.35, "mag": 12, "auto_fire": false, "pellets": 1, "spread": 0.005, "range": 200.0, "color": Color(0.85, 0.85, 0.85), "len": 0.4},
	{"name": "Автомат", "dmg": 12.0, "rate": 0.09, "mag": 30, "auto_fire": true, "pellets": 1, "spread": 0.02, "range": 300.0, "color": Color(0.15, 0.15, 0.15), "len": 0.9},
	{"name": "Дробовик", "dmg": 9.0, "rate": 0.9, "mag": 6, "auto_fire": false, "pellets": 8, "spread": 0.09, "range": 40.0, "color": Color(0.5, 0.3, 0.1), "len": 0.7},
	{"name": "Снайперка", "dmg": 90.0, "rate": 1.4, "mag": 5, "auto_fire": false, "pellets": 1, "spread": 0.0, "range": 500.0, "color": Color(0.1, 0.4, 0.2), "len": 1.1},
]
const TEAM_NAMES := ["Красные", "Синие"]
const TEAM_COLORS := [Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.95)]
const SPEED := 6.0
const JUMP_SPEED := 7.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.003
const TOUCH_LOOK_SENS := 0.006

# синхронизируется по сети
var team := 0
var health := 100.0
var weapon := 0
var aim_pitch := 0.0

var ammo: Array = []
var cooldown := 0.0
var reload_t := 0.0
var shown_weapon := -1

var is_local := false
var head: Node3D
var camera: Camera3D
var gun: MeshInstance3D
var body: MeshInstance3D
var sfx: AudioStreamPlayer3D
var hud_info: Label

# ввод (клавиатура/мышь + сенсор)
var fire_edge := false
var touch_fire := false
var joy_touch := -1
var look_touch := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO


static func spawn_point(team_id: int) -> Vector3:
	var x := -40.0 if team_id == 0 else 40.0
	return Vector3(x, 1.0, randf_range(-25.0, 25.0))


func _ready() -> void:
	is_local = is_multiplayer_authority()
	add_to_group("players")

	for w in WEAPONS:
		ammo.append(w.mag)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	body = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.4
	bm.height = 1.8
	body.mesh = bm
	body.position.y = 0.9
	body.material_override = _mat(TEAM_COLORS[team])
	add_child(body)

	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)

	camera = Camera3D.new()
	head.add_child(camera)
	camera.current = is_local

	gun = MeshInstance3D.new()
	gun.mesh = BoxMesh.new()
	gun.position = Vector3(0.25, -0.25, -0.5)
	camera.add_child(gun)

	sfx = AudioStreamPlayer3D.new()
	add_child(sfx)

	_setup_sync()

	if is_local:
		body.visible = false
		if not OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_build_hud()


func _setup_sync() -> void:
	var cfg := SceneReplicationConfig.new()
	for p in [":position", ":rotation", ":aim_pitch", ":health", ":team", ":weapon"]:
		cfg.add_property(NodePath(p))
	var sync := MultiplayerSynchronizer.new()
	sync.root_path = NodePath("..")
	sync.replication_config = cfg
	sync.replication_interval = 0.02
	add_child(sync)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# ---------- HUD (только для себя) ----------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud_info = Label.new()
	hud_info.position = Vector2(16, 16)
	hud_info.add_theme_font_size_override("font_size", 24)
	layer.add_child(hud_info)

	# выбор оружия: верхний правый угол
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_top = 16
	row.offset_right = -16
	layer.add_child(row)
	for i in WEAPONS.size():
		var b := Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(80, 80)
		b.pressed.connect(switch_weapon.bind(i))
		row.add_child(b)

	# огонь и перезарядка: нижний правый угол (для телефона)
	var fire := Button.new()
	fire.text = "ОГОНЬ"
	fire.custom_minimum_size = Vector2(170, 170)
	fire.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fire.grow_vertical = Control.GROW_DIRECTION_BEGIN
	fire.offset_right = -24
	fire.offset_bottom = -24
	fire.button_down.connect(_on_fire_down)
	fire.button_up.connect(_on_fire_up)
	fire.visible = OS.has_feature("mobile")
	layer.add_child(fire)

	var reload_btn := Button.new()
	reload_btn.text = "R"
	reload_btn.custom_minimum_size = Vector2(120, 80)
	reload_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reload_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	reload_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	reload_btn.offset_right = -24
	reload_btn.offset_bottom = -210
	reload_btn.pressed.connect(reload)
	reload_btn.visible = OS.has_feature("mobile")
	layer.add_child(reload_btn)


func _on_fire_down() -> void:
	touch_fire = true
	fire_edge = true


func _on_fire_up() -> void:
	touch_fire = false


# ---------- ввод ----------

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * MOUSE_SENS)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			fire_edge = true
		elif not OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R:
			reload()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			switch_weapon(event.keycode - KEY_1)

	elif event is InputEventScreenTouch:
		var sz := get_viewport().get_visible_rect().size
		if event.pressed:
			# левая часть экрана — стик движения
			if joy_touch == -1 and event.position.x < sz.x * 0.45 and event.position.y > sz.y * 0.3:
				joy_touch = event.index
				joy_origin = event.position
				joy_vec = Vector2.ZERO
			# правая средняя часть — поворот камеры
			elif look_touch == -1 and event.position.x >= sz.x * 0.45 and event.position.y > sz.y * 0.2 and event.position.y < sz.y * 0.6:
				look_touch = event.index
		else:
			if event.index == joy_touch:
				joy_touch = -1
				joy_vec = Vector2.ZERO
			if event.index == look_touch:
				look_touch = -1

	elif event is InputEventScreenDrag:
		if event.index == joy_touch:
			joy_vec = ((event.position - joy_origin) / 90.0).limit_length(1.0)
		elif event.index == look_touch:
			look(event.relative * TOUCH_LOOK_SENS)


func look(d: Vector2) -> void:
	rotate_y(-d.x)
	aim_pitch = clamp(aim_pitch - d.y, -1.4, 1.4)
	head.rotation.x = aim_pitch


# ---------- физика и логика (только владелец) ----------

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	cooldown = max(cooldown - delta, 0.0)
	reload_t = max(reload_t - delta, 0.0)

	var input := joy_vec
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0
	input = input.limit_length(1.0)

	var dir := transform.basis * Vector3(input.x, 0.0, input.y)
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var w = WEAPONS[weapon]
	var holding := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or touch_fire
	if (w.auto_fire and holding) or fire_edge:
		try_shoot()
	fire_edge = false


func try_shoot() -> void:
	if cooldown > 0.0 or reload_t > 0.0:
		return
	if ammo[weapon] <= 0:
		reload()
		return

	ammo[weapon] -= 1
	var w = WEAPONS[weapon]
	cooldown = w.rate
	fire_fx.rpc(weapon)

	var cam := camera.global_transform
	var space := get_world_3d().direct_space_state
	for i in w.pellets:
		var dir: Vector3 = -cam.basis.z + cam.basis.x * randf_range(-w.spread, w.spread) + cam.basis.y * randf_range(-w.spread, w.spread)
		var to: Vector3 = cam.origin + dir.normalized() * w.range
		var q := PhysicsRayQueryParameters3D.create(cam.origin, to)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider.is_in_group("players") and hit.collider.team != team:
			# урон отправляем владельцу цели, он сам обновит своё HP
			hit.collider.apply_damage.rpc_id(hit.collider.get_multiplayer_authority(), w.dmg)


func reload() -> void:
	var w = WEAPONS[weapon]
	if ammo[weapon] >= w.mag or reload_t > 0.0:
		return
	reload_t = 1.2
	ammo[weapon] = w.mag


func switch_weapon(i: int) -> void:
	if i == weapon or i < 0 or i >= WEAPONS.size():
		return
	weapon = i
	cooldown = 0.3
	_refresh_gun()


func _refresh_gun() -> void:
	var w = WEAPONS[weapon]
	var bm := gun.mesh as BoxMesh
	bm.size = Vector3(0.08, 0.14, w.len)
	gun.material_override = _mat(w.color)


@rpc("any_peer", "call_local", "reliable")
func apply_damage(dmg: float) -> void:
	health -= dmg
	if health <= 0.0:
		respawn()


func respawn() -> void:
	health = 100.0
	position = Player.spawn_point(team)
	velocity = Vector3.ZERO
	for i in WEAPONS.size():
		ammo[i] = WEAPONS[i].mag


@rpc("authority", "call_local", "unreliable")
func fire_fx(w: int) -> void:
	sfx.stream = Sfx.for_weapon(w)
	sfx.play()


# ---------- кадр ----------

func _process(_delta: float) -> void:
	if is_local:
		hud_info.text = "Команда: %s | HP: %d | Патроны: %d/%d | %s | FPS: %d" % [
			TEAM_NAMES[team],
			int(health),
			ammo[weapon],
			WEAPONS[weapon].mag,
			WEAPONS[weapon].name,
			int(Engine.get_frames_per_second()),
		]
	else:
		head.rotation.x = aim_pitch

	if shown_weapon != weapon:
		shown_weapon = weapon
		_refresh_gun()
