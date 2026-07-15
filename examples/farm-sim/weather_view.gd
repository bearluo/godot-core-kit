extends Node2D
## 天气视觉(P2 占位)。订阅 weather:changed,雨天在视口铺半透明冷色 + 斜向雨线。
## 挂在 world 下的一个 CanvasLayer(layer=1:农田之上、HUD 之下),故按屏幕坐标绘制。
## 真素材/粒子雨留 P5,本层只做"看得出在下雨"的占位反馈。

var _rainy := false


func bind(weather) -> void:
	CoreKit.bus.subscribe(weather.EV_CHANGED, _on_weather)


func _exit_tree() -> void:
	CoreKit.bus.unsubscribe_all(self)


func _on_weather(payload: Dictionary) -> void:
	_rainy = payload.get("kind", &"") == &"rainy"
	queue_redraw()


func _draw() -> void:
	if not _rainy:
		return
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.3, 0.4, 0.6, 0.18))   # 冷色雨幕
	for i in range(24):
		var x := float((i * 53) % maxi(1, int(vp.x)))
		draw_line(Vector2(x, 0), Vector2(x - 12, vp.y), Color(0.7, 0.8, 1.0, 0.25), 1.0)  # 斜雨线
