# KitTransition —— 可复用场景转场资源

> `class_name KitTransition`(off-facade,`extends Resource`)· `transitions/kit_transition.gd` · 由 `CoreKit.scenes.change_scene` 消费

## 职责

数据驱动的场景转场定义,对标 EasyTransition。描述「用什么遮罩动画覆盖 → 换场景 → 揭开」一次场景替换。`.new()` 现造或存成 `.tres` 资产 `@export` 到 Inspector 复用。三类:**FADE**(遮罩淡入淡出)、**SLIDE**(全屏色板按方向驶入覆盖 / 驶出揭开)、**MASK**(灰度遮罩图案驱动,圆形收缩、擦除、溶解等,0.27.0 起)。`SceneManager` 读它的字段驱动常驻遮罩,不再写死 fade 分支。

## 公开 API

```gdscript
enum Type { NONE, FADE, SLIDE, MASK }  # 新值只追加在末尾,旧 .tres 的枚举数字不变
enum Dir { LEFT, RIGHT, UP, DOWN }        # SLIDE 时色板运动方向

@export var type: Type = Type.FADE
@export var direction: Dir = Dir.LEFT
@export var duration: float = 0.3
@export var color: Color = Color.BLACK
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT       # 默认 = 现有 fade 手感
@export var trans_type: Tween.TransitionType = Tween.TRANS_LINEAR
@export var mask: Texture2D                     # MASK:灰度图,越暗越早被遮住;null → 回退 FADE
@export_range(0.0, 0.5) var smoothness := 0.05 # MASK:边缘羽化宽度
@export var invert := false                     # MASK:反转遮盖顺序(亮处先遮)

func is_none() -> bool                                          # type == NONE
func normalized() -> KitTransition                             # 返副本:夹 duration>=0、越界枚举回默认、MASK 缺 mask 回 FADE、smoothness 夹 [0,0.5]
func slide_cover_from(viewport_size: Vector2) -> Vector2       # SLIDE 覆盖段色板起点(终点恒 ZERO)
func slide_reveal_to(viewport_size: Vector2) -> Vector2        # SLIDE 揭开段色板终点(起点恒 ZERO)
static func mask_alpha(gray: float, progress: float, smooth: float, inverted: bool) -> float  # MASK 单像素遮盖度,与 shader 同公式
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

# MASK:圆形收缩(从中心往外遮住,揭开时按原路缩回)。图案不用图片文件,用 Godot 自带的 GradientTexture2D
var circle := GradientTexture2D.new()
circle.gradient = Gradient.new()            # 必须设!不设会退化成棋盘格占位图
circle.fill = GradientTexture2D.FILL_RADIAL
circle.fill_from = Vector2(0.5, 0.5)
circle.fill_to = Vector2(1.0, 0.5)
var iris := KitTransition.new()
iris.type = KitTransition.Type.MASK
iris.mask = circle
iris.duration = 0.6
await CoreKit.scenes.change_scene("res://levels/level_2.tscn", iris)
```

MASK 常用图案(都是 Inspector 里新建一个 `GradientTexture2D`、**再新建它的 `Gradient`**,然后改这几项;默认渐变黑→白):

| 效果 | `fill` | `fill_from` | `fill_to` | 备注 |
|---|---|---|---|---|
| 从左往右擦除 | `LINEAR` | `(0, 0)` | `(1, 0)` | 默认值就是这个 |
| 从上往下擦除 | `LINEAR` | `(0, 0)` | `(0, 1)` | |
| 对角擦除 | `LINEAR` | `(0, 0)` | `(1, 1)` | |
| 从中心向外扩 | `RADIAL` | `(0.5, 0.5)` | `(1, 0.5)` | 设 `invert = true` 变成从四周向中心收(经典 iris) |

任意灰度 png(溶解噪点、百叶窗、像素马赛克等)也能直接拖进 `mask`。kit 不内置图片:风格归游戏,也不给微信包体加东西。

```gdscript
# 预置成 .tres 资产,多处复用(Inspector 里配好后 @export 引用)
@export var boss_transition: KitTransition
```

## 注意事项

- **对称两段**:转场恒为「COVER 覆盖 → 换树 → REVEAL 揭开」两段,各 `duration` 秒;v1 无单程语义。
- **SLIDE 方向**:`direction` = 色板运动方向,整段朝同一方向单向掠过屏幕(LEFT 从右缘驶入、续向左驶出),四向对称。
- **缓动默认 = 现有 fade 手感**:`ease_type`/`trans_type` 默认 `EASE_IN_OUT`+`TRANS_LINEAR`(Godot Tween 默认),故 legacy fade 视觉零变化;要弹性/正弦手感显式设 `trans_type`。
- **`normalized()` 返副本**:校验(夹负 duration、越界枚举回默认)作用在副本上,不改原资产,`.tres` 多处共享安全。
- **向后兼容**:`change_scene` 仍接受 legacy `{"transition": CoreKit.scenes.Transition.FADE, ...}` 字典;新代码传 `KitTransition`。
- **MASK 渲染**:复用常驻遮罩 `ColorRect`,挂一个 kit 内置 shader(`transitions/kit_mask.gdshader`)。每像素 `alpha = smoothstep(m - s, m + s, p)`,`m` 是遮罩灰度(`invert` 时取 `1 - m`),`p` 是进度从 `[0,1]` 线性映射到 `[-s, 1+s]`,保证进度 0 全透明、1 全遮住。COVER 进度 0→1,REVEAL 同一张图 1→0、图案按原路退回;`color`、`ease_type`、`trans_type` 照常生效(缓动作用在进度上)。FADE/SLIDE 开头会清掉 `material`,MASK 不影响后续别的转场。
- **MASK 拉伸铺满**:遮罩图按视口 UV 拉伸,不保持宽高比(竖屏上圆会变椭圆)。需要固定比例的游戏自己出对应比例的图。
- **MASK 首次卡一帧**:WebGL 首次使用要编译 shader,可能卡一帧;卡顿落在 COVER 第一帧(仍透明),看起来就是转场晚开始一帧。不做预热,真成问题时在启动时跑一次 0 时长 `cover`/`reveal`。
- **MASK 平台**:gl_compatibility 渲染器 + 微信开发者工具(WebGL2)实测显示正确。
