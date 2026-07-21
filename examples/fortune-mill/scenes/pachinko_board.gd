extends Node2D
## 柏青哥物理表现层(juice,仅非 smoke 路径实例化)。RigidBody2D 落球从 CoreKit.pool 取,
## 碰钉子落进底部 Area2D 槽 → 回调 FortuneMill.pachinko_land(slot)(权威入账在 model);
## 落槽 SFX 走 CoreKit.audio。在场球数封顶 + 到底即回收。经济权威全在 PachinkoRoom,本节点只做真物理表现。

const BALL_POOL := "pachinko_ball"
const MAX_BALLS := 64
const BOARD_W := 240.0
const PEG_ROWS := 7
const SLOT_COUNT := 5   ## 须与 PachinkoRoom.SLOT_VALUES 长度一致

var _slots: Array = []
var _sfx: AudioStreamWAV
var _live: int = 0
var _slot_top_y: float = 0.0


func _ready() -> void:
	position = Vector2(820, 40)
	_sfx = _make_tick()
	_register_ball_pool()
	_build_pegs()
	_build_slots()
	_add_frame()


## 退出时清球池,释放预热/在场球体(否则 RigidBody2D 的 RID 会在退出时报 leaked)。
func _exit_tree() -> void:
	if CoreKit.pool.has_pool(BALL_POOL):
		CoreKit.pool.clear(BALL_POOL)


## 落 count 个物理球(手动落球经真物理落槽回调 award）。
func drop(count: int) -> void:
	for _i in count:
		if _live >= MAX_BALLS:
			return
		var ball = CoreKit.pool.acquire(BALL_POOL)
		if ball == null:
			return
		if ball.get_parent() == null:
			add_child(ball)
		ball.freeze = true
		ball.position = Vector2(BOARD_W * 0.5 + randf_range(-16.0, 16.0), -8.0)
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0
		ball.set_meta("landed", false)
		ball.freeze = false
		_live += 1


func _physics_process(_dt: float) -> void:
	# 兜底:极少数卡住/漏检的球,掉出底边即按最近槽回收(避免泄漏 + 不吞收益)。
	var floor_y := _slot_top_y + 60.0
	for child in get_children():
		if child is RigidBody2D and child.visible and not child.get_meta("landed", false):
			if child.position.y > floor_y:
				_land(child, _nearest_slot(child.position.x))


func _on_slot_entered(body: Node, idx: int) -> void:
	if body is RigidBody2D and not body.get_meta("landed", false):
		_land(body, idx)


func _land(ball, idx: int) -> void:
	ball.set_meta("landed", true)
	FortuneMill.pachinko_land(idx)
	if _sfx != null:
		CoreKit.audio.play_sfx(_sfx, -8.0, randf_range(0.9, 1.15))
	_live = maxi(0, _live - 1)
	CoreKit.pool.release(ball)


func _nearest_slot(x: float) -> int:
	return clampi(int(x / (BOARD_W / float(SLOT_COUNT))), 0, SLOT_COUNT - 1)


# --- 构建 ---

func _register_ball_pool() -> void:
	if CoreKit.pool.has_pool(BALL_POOL):
		return
	var ball := RigidBody2D.new()
	ball.gravity_scale = 1.2
	var pm := PhysicsMaterial.new(); pm.bounce = 0.25; pm.friction = 0.4
	ball.physics_material_override = pm
	var shape := CircleShape2D.new(); shape.radius = 6.0
	var col := CollisionShape2D.new(); col.shape = shape
	ball.add_child(col)
	var vis := Polygon2D.new(); vis.polygon = _circle_pts(6.0, 10); vis.color = Color(1.0, 0.85, 0.2)
	ball.add_child(vis)
	var ps := PackedScene.new()
	ps.pack(ball)
	ball.free()
	CoreKit.pool.register(BALL_POOL, ps, 8, MAX_BALLS)


func _build_pegs() -> void:
	for row in PEG_ROWS:
		var y := 44.0 + float(row) * 30.0
		var x := 26.0 + (18.0 if row % 2 == 1 else 0.0)
		while x < BOARD_W - 20.0:
			_peg(Vector2(x, y))
			x += 36.0


func _peg(pos: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CircleShape2D.new(); shape.radius = 4.0
	var col := CollisionShape2D.new(); col.shape = shape
	body.add_child(col)
	var vis := Polygon2D.new(); vis.polygon = _circle_pts(4.0, 8); vis.color = Color(0.6, 0.6, 0.72)
	body.add_child(vis)
	add_child(body)


func _build_slots() -> void:
	_slot_top_y = 44.0 + float(PEG_ROWS) * 30.0 + 20.0
	var w := BOARD_W / float(SLOT_COUNT)
	for i in SLOT_COUNT:
		var area := Area2D.new()
		area.position = Vector2(w * (float(i) + 0.5), _slot_top_y + 15.0)
		var shape := RectangleShape2D.new(); shape.size = Vector2(w - 2.0, 30.0)
		var col := CollisionShape2D.new(); col.shape = shape
		area.add_child(col)
		var half := w * 0.5 - 1.0
		var vis := Polygon2D.new()
		vis.polygon = PackedVector2Array([Vector2(-half, -15), Vector2(half, -15), Vector2(half, 15), Vector2(-half, 15)])
		vis.color = Color(0.2, 0.3, 0.5, 0.55)
		area.add_child(vis)
		var lbl := Label.new()
		lbl.text = "%d" % int(PachinkoRoom.SLOT_VALUES[i])
		lbl.position = Vector2(-6, -8)
		area.add_child(lbl)
		var idx := i
		area.body_entered.connect(func(b) -> void: _on_slot_entered(b, idx))
		add_child(area)
		_slots.append(area)


## 两侧 + 底边挡墙,别让球飞出。
func _add_frame() -> void:
	var bottom := _slot_top_y + 34.0
	_wall(Vector2(4, bottom * 0.5), Vector2(4, bottom))
	_wall(Vector2(BOARD_W - 4, bottom * 0.5), Vector2(4, bottom))
	_wall(Vector2(BOARD_W * 0.5, bottom), Vector2(BOARD_W, 4))


func _wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := RectangleShape2D.new(); shape.size = size
	var col := CollisionShape2D.new(); col.shape = shape
	body.add_child(col)
	add_child(body)


func _circle_pts(r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


## 程序化短 tick(落槽音效)。
func _make_tick() -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var n := 1400
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / 22050.0
		var env := 1.0 - float(i) / float(n)
		var s := sin(TAU * 880.0 * t) * env * env * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	w.data = data
	return w
