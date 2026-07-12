# KitTransition —— 可复用场景转场资源

> `class_name KitTransition`(off-facade,`extends Resource`)· `transitions/kit_transition.gd` · 由 `CoreKit.scenes.change_scene` 消费

## 职责

数据驱动的场景转场定义,对标 EasyTransition。描述「用什么遮罩动画覆盖 → 换场景 → 揭开」一次场景替换。`.new()` 现造或存成 `.tres` 资产 `@export` 到 Inspector 复用。首版两类:**FADE**(遮罩淡入淡出)、**SLIDE**(全屏色板按方向驶入覆盖 / 驶出揭开)。`SceneManager` 读它的字段驱动常驻遮罩,不再写死 fade 分支。

## 公开 API

```gdscript
enum Type { NONE, FADE, SLIDE }
enum Dir { LEFT, RIGHT, UP, DOWN }        # SLIDE 时色板运动方向

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT       # 默认 = 现有 fade 手感
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR

func is_none() -> bool                                          # type == NONE
func normalized() -> KitTransition                             # 返副本:夹 duration>=0、越界枚举回默认
func slide_cover_from(viewport_size: Vector2) -> Vector2       # SLIDE 覆盖段色板起点(终点恒 ZERO)
func slide_reveal_to(viewport_size: Vector2) -> Vector2        # SLIDE 揭开段色板终点(起点恒 ZERO)
```

## 依赖

零依赖(纯 `Resource` + 纯几何/校验方法,不引 `CoreKit`、不碰场景树),故可脱离门面 headless 断言。转场的实际遮罩驱动在 `SceneManager` 内(见 [scene-manager](../systems/scene-manager.md))。

## 用法示例

```gdscript
# 现造一个向左滑动转场,原地等待切换完成
var t := KitTransition.new()
t.type = KitTransition.Type.SLIDE
t.direction = KitTransition.Dir.LEFT
t.duration = 0.4
await CoreKit.scenes.change_scene("res://levels/level_2.tscn", t)

# 淡入淡出(可配缓动曲线)
var fade := KitTransition.new()
fade.type = KitTransition.Type.FADE
fade.trans_type = Tween.TRANS_SINE
CoreKit.scenes.change_scene(preload("res://levels/boss.tscn"), fade)

# 预置成 .tres 资产,多处复用(Inspector 里配好后 @export 引用)
@export var boss_transition: KitTransition
```

## 注意事项

- **对称两段**:转场恒为「COVER 覆盖 → 换树 → REVEAL 揭开」两段,各 `duration` 秒;v1 无单程语义。
- **SLIDE 方向**:`direction` = 色板运动方向,整段朝同一方向单向掠过屏幕(LEFT 从右缘驶入、续向左驶出),四向对称。
- **缓动默认 = 现有 fade 手感**:`ease_type`/`trans_type` 默认 `EASE_IN_OUT`+`TRANS_LINEAR`(Godot Tween 默认),故 legacy fade 视觉零变化;要弹性/正弦手感显式设 `trans_type`。
- **`normalized()` 返副本**:校验(夹负 duration、越界枚举回默认)作用在副本上,不改原资产,`.tres` 多处共享安全。
- **纯色遮罩**:首版遮罩为纯色 `ColorRect`,无 shader;圆形擦除/溶解等留待后续按需扩(`Type` 已留扩展位)。
- **向后兼容**:`change_scene` 仍接受 legacy `{"transition": CoreKit.scenes.Transition.FADE, ...}` 字典;新代码传 `KitTransition`。
