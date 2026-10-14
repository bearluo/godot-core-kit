class_name KitTransition
extends Resource
## 可复用场景转场定义(数据驱动,对标 EasyTransition)。描述"用什么遮罩动画覆盖→切换→揭开"
## 一次场景替换:由 SceneManager.change_scene 消费。可 .new() 现造,也可存成 .tres 资产
## @export 到 Inspector 复用。纯逻辑(校验 normalized / slide 几何)无副作用、可 headless 断言;
## 真正驱动常驻遮罩色板的活在 SceneManager 内(碰视口/场景树)。零依赖(不引 CoreKit)。

enum Type { NONE, FADE, SLIDE, MASK }  ## 新值只追加在末尾,已存 .tres 的枚举数字不变
enum Dir { LEFT, RIGHT, UP, DOWN }   ## SLIDE 时遮罩色板"驶入"的方向(= 色板运动方向)

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR
## MASK 用:灰度图,越暗的像素越早被遮住(拉伸铺满视口)。null 时 MASK 回退 FADE。
@export var mask: Texture2D
## MASK 用:边缘羽化宽度。
@export_range(0.0, 0.5) var smoothness: float = 0.05
## MASK 用:反转遮盖顺序(亮处先遮)。
@export var invert: bool = false


## type == NONE(无过渡直切)。
func is_none() -> bool:
	return type == Type.NONE


## 返回校验后的副本:duration 夹到 >= 0、越界 type/direction 回默认(FADE/LEFT)、
## MASK 缺 mask 回退 FADE、smoothness 夹到 [0, 0.5]。
## 不改原资产(保 .tres 共享安全)。
func normalized() -> KitTransition:
	var t := duplicate() as KitTransition
	if t.type < Type.NONE or t.type > Type.MASK:
		t.type = Type.FADE
	if t.type == Type.MASK and t.mask == null:
		t.type = Type.FADE
	t.smoothness = clampf(t.smoothness, 0.0, 0.5)
	if t.direction < Dir.LEFT or t.direction > Dir.DOWN:
		t.direction = Dir.LEFT
	if t.duration < 0.0:
		t.duration = 0.0
	return t


## SLIDE 覆盖段:色板起点(终点恒 Vector2.ZERO)。direction = 色板运动方向,从对侧边缘外驶入。
func slide_cover_from(viewport_size: Vector2) -> Vector2:
	match direction:
		Dir.LEFT:
			return Vector2(viewport_size.x, 0.0)
		Dir.RIGHT:
			return Vector2(-viewport_size.x, 0.0)
		Dir.UP:
			return Vector2(0.0, viewport_size.y)
		Dir.DOWN:
			return Vector2(0.0, -viewport_size.y)
		_:
			return Vector2.ZERO


## SLIDE 揭开段:色板终点(起点恒 Vector2.ZERO)。同 direction 续行驶出屏外。
func slide_reveal_to(viewport_size: Vector2) -> Vector2:
	match direction:
		Dir.LEFT:
			return Vector2(-viewport_size.x, 0.0)
		Dir.RIGHT:
			return Vector2(viewport_size.x, 0.0)
		Dir.UP:
			return Vector2(0.0, -viewport_size.y)
		Dir.DOWN:
			return Vector2(0.0, viewport_size.y)
		_:
			return Vector2.ZERO


## MASK 单像素遮盖度(0 透明 ~ 1 遮住),与 kit_mask.gdshader 同一公式。
## progress 先线性映射到 [-s, 1+s],保证 0 时全透明、1 时全遮住;s 取极小正值避免 smoothstep 退化。
static func mask_alpha(gray: float, progress: float, smooth: float, inverted: bool) -> float:
	if progress <= 0.0:
		return 0.0
	if progress >= 1.0:
		return 1.0
	var m := 1.0 - gray if inverted else gray
	var s := maxf(smooth, 0.0001)
	return smoothstep(m - s, m + s, lerpf(-s, 1.0 + s, progress))
