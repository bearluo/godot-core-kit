extends RefCounted
## 粒子反馈 helper(P5)。按玩法动作 kind 建一次性 CPUParticles2D,挂到 parent、播完自 free。
## 零依赖、零二进制:纹理取自 ArtBank 程序化点贴图。headless 安全(dummy 驱动可创建,不渲染即不崩,已探针验)。

const ArtBank = preload("res://examples/farm-sim/gfx/art_bank.gd")


## 在 parent 坐标系的 world_pos 处爆一簇粒子。kind ∈ harvest/water/plant/till(其余按尘土处理)。
static func burst(parent, world_pos: Vector2, kind) -> void:
	if parent == null:
		return
	var cfg := _cfg(kind)
	var p := CPUParticles2D.new()
	p.position = world_pos
	p.local_coords = false          # 粒子留在世界,发射器随后 free 也不影响已发出的
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.6
	p.emitting = true
	p.texture = ArtBank.tex(cfg.tex)
	p.amount = cfg.amount
	p.direction = cfg.dir
	p.spread = cfg.spread
	p.gravity = cfg.gravity
	p.initial_velocity_min = cfg.vmin
	p.initial_velocity_max = cfg.vmax
	p.scale_amount_min = cfg.smin
	p.scale_amount_max = cfg.smax
	p.color = cfg.color
	parent.add_child(p)
	p.finished.connect(p.queue_free)   # one_shot 全部消亡后发 finished → 自毁


static func _cfg(kind) -> Dictionary:
	match kind:
		&"harvest":   # 向上迸金星,轻重力回落
			return {tex = &"fx_star", amount = 12, dir = Vector2(0, -1), spread = 55.0,
				gravity = Vector2(0, 140), vmin = 70.0, vmax = 130.0, smin = 0.6, smax = 1.2,
				color = Color(1, 1, 0.9)}
		&"water":     # 蓝水花,重力大快落
			return {tex = &"fx_drop", amount = 10, dir = Vector2(0, -1), spread = 40.0,
				gravity = Vector2(0, 260), vmin = 50.0, vmax = 110.0, smin = 0.5, smax = 1.0,
				color = Color(0.8, 0.9, 1)}
		&"plant":     # 播种:浅绿碎屑
			return {tex = &"fx_dust", amount = 8, dir = Vector2(0, -1), spread = 70.0,
				gravity = Vector2(0, 120), vmin = 30.0, vmax = 70.0, smin = 0.5, smax = 1.0,
				color = Color(0.7, 0.85, 0.5)}
		_:            # till 及默认:褐色尘土
			return {tex = &"fx_dust", amount = 10, dir = Vector2(0, -1), spread = 80.0,
				gravity = Vector2(0, 120), vmin = 30.0, vmax = 80.0, smin = 0.6, smax = 1.1,
				color = Color(0.75, 0.62, 0.45)}
