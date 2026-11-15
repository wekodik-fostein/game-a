extends Node

const PORT := 7777
const MAP_NAMES := ["Арена", "Коридоры"]
const TEAM_NAMES := ["Красные", "Синие"]

var menu: Control
var map_opt: OptionButton
var team_opt: OptionButton
var ip_edit: LineEdit
var status_lbl: Label
var host_btn: Button
var join_btn: Button
var start_btn: Button
var game: Node3D
var players: Node3D
var spawner: MultiplayerSpawner
var in_match := false
var is_host := false


func _ready() -> void:
	_build_menu()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ---------- меню ----------

func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	box.add_child(_label("GAME A", 48))
	box.add_child(_label("Карта"))

	map_opt = OptionButton.new()
	for m in MAP_NAMES:
		map_opt.add_item(m)
	box.add_child(map_opt)

	box.add_child(_label("Команда"))
	team_opt = OptionButton.new()
	for t in TEAM_NAMES:
		team_opt.add_item(t)
	box.add_child(team_opt)

	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "IP сервера (для подключения)"
	box.add_child(ip_edit)

	host_btn = _add_button(box, "Создать сервер", _on_host)
	join_btn = _add_button(box, "Подключиться", _on_join)
	start_btn = _add_button(box, "НАЧАТЬ", _on_start)
	start_btn.visible = false

	status_lbl = _label("Выбери карту и команду, потом создай сервер или подключись.", 18)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_lbl)


func _label(text: String, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _add_button(box: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.find(":") == -1 and not a.begins_with("127."):
			return a
	return "?"


func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		status_lbl.text = "Не удалось создать сервер (код %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	host_btn.visible = false
	join_btn.visible = false
	start_btn.visible = true
	status_lbl.text = "Сервер запущен. Адрес для подключения: %s:%d" % [_local_ip(), PORT]


func _on_join() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_edit.text.strip_edges(), PORT)
	if err != OK:
		status_lbl.text = "Ошибка подключения (код %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	host_btn.visible = false
	join_btn.visible = false
	status_lbl.text = "Подключаемся..."


func _on_connected() -> void:
	status_lbl.text = "Подключено. Ждём, пока хост нажмёт НАЧАТЬ."


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	host_btn.visible = true
	join_btn.visible = true
	status_lbl.text = "Не удалось подключиться к серверу"


func _on_start() -> void:
	if is_host and not in_match:
		begin_match.rpc(map_opt.selected)


func _on_peer_connected(id: int) -> void:
	# Поздно присоединиться к идущему матчу нельзя (упрощение для первой версии)
	if is_host and in_match:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if players and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()


# ---------- матч ----------

@rpc("authority", "call_local", "reliable")
func begin_match(idx: int) -> void:
	if in_match:
		return
	in_match = true
	menu.visible = false

	game = Node3D.new()
	game.name = "Game"
	add_child(game)

	build_map(idx)

	players = Node3D.new()
	players.name = "Players"
	game.add_child(players)

	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	game.add_child(spawner)
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = Callable(self, "spawn_player")

	# Каждый клиент сообщает хосту свою команду, хост создаёт игрока
	request_spawn.rpc_id(1, team_opt.selected)


@rpc("any_peer", "call_local", "reliable")
func request_spawn(team: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	spawner.spawn({"id": id, "team": team})


func spawn_player(data: Dictionary) -> Node:
	var p := Player.new()
	p.name = str(data["id"])
	p.set_multiplayer_authority(data["id"])
	p.team = data["team"]
	p.position = Player.spawn_point(data["team"])
	return p


# ---------- карты ----------

func build_map(idx: int) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	game.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	game.add_child(we)

	var map := Node3D.new()
	map.name = "Map"
	game.add_child(map)

	var wall := Color(0.6, 0.55, 0.5)
	add_box(map, Vector3(0, -0.5, 0), Vector3(120, 1, 120), Color(0.35, 0.55, 0.35))
	# внешние стены
	add_box(map, Vector3(0, 3, -50), Vector3(100, 6, 2), wall)
	add_box(map, Vector3(0, 3, 50), Vector3(100, 6, 2), wall)
	add_box(map, Vector3(-50, 3, 0), Vector3(2, 6, 100), wall)
	add_box(map, Vector3(50, 3, 0), Vector3(2, 6, 100), wall)

	if idx == 0:
		# Арена: сетка колонн
		for x in [-25.0, 0.0, 25.0]:
			for z in [-25.0, 0.0, 25.0]:
				add_box(map, Vector3(x, 2.5, z), Vector3(3, 5, 3), wall)
	else:
		# Коридоры: перегородки
		add_box(map, Vector3(0, 3, -20), Vector3(60, 6, 2), wall)
		add_box(map, Vector3(0, 3, 20), Vector3(60, 6, 2), wall)
		add_box(map, Vector3(-15, 3, -10), Vector3(2, 6, 20), wall)
		add_box(map, Vector3(15, 3, 10), Vector3(2, 6, 20), wall)
		add_box(map, Vector3(0, 3, 0), Vector3(2, 6, 12), wall)


func add_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)

	parent.add_child(body)
