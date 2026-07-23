class_name FortuneDartsInput
extends Node
## 双端输入适配:桌面(鼠标左键)与触屏(屏幕触摸)统一走「旋臂瞄准 + 点住蓄力 + 松手投」,
## 都归结为 (aim,power) 一对量发 thrown 信号。纯映射数学是 static(可无头测);
## 节点部分维护蓄力状态供 view 用。model/经济与本层解耦。

signal thrown(aim: float, power: float)
signal aim_changed(aim: float)
signal power_changed(power: float)

const POWER_SWEET := 0.6     ## 与 FortuneWheelLayout.POWER_SWEET 对齐
const POWER_PERIOD := 1.2    ## 力度摆动周期(秒)
const DRAG_MAX := 240.0      ## 触屏拉弓最大有效拖距(px)

var _mode: StringName = &"desktop"
var _charging: bool = false
var _hold: float = 0.0
var _aim: float = 0.5


# --- 纯映射(static,可测) ---

static func desktop_aim(mouse_y: float, view_h: float) -> float:
	if view_h <= 0.0:
		return 0.5
	return clampf(mouse_y / view_h, 0.0, 1.0)


## 蓄力三角摆动:hold 秒 → [0,1] 往返(逼玩家把握时机)。
static func desktop_power(hold_seconds: float, _sweet: float) -> float:
	var phase := fposmod(hold_seconds / POWER_PERIOD, 1.0)
	return 1.0 - absf(phase * 2.0 - 1.0)   # 0→1→0 三角波


## 触屏:拖向量的纵向分量 → aim(0..1);中点 0.5。
static func touch_aim(drag: Vector2) -> float:
	return clampf(0.5 + drag.y / (DRAG_MAX * 2.0), 0.0, 1.0)


## 触屏:拖长 → power(0..1),封顶。
static func touch_power(drag: Vector2, max_len: float) -> float:
	if max_len <= 0.0:
		return 0.0
	return clampf(drag.length() / max_len, 0.0, 1.0)


# --- 节点侧(view 用) ---

## 平台判定:移动/触屏 → touch,否则 desktop。
## 设置覆盖(CoreKit.settings 的 darts_input)由 view(world.gd)读取后 set_mode() 施加——
## 本适配器不依赖 settings 子系统,保持纯净可无头测(不引用 CoreKit 全局标识)。
func detect_mode() -> StringName:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return &"touch"
	return &"desktop"


func set_mode(mode: StringName) -> void:
	_mode = mode


func current_mode() -> StringName:
	return _mode


func _ready() -> void:
	_mode = detect_mode()


func _process(delta: float) -> void:
	if _charging:   # 桌面与触屏统一:begin_charge 后即按三角波蓄力,松手投
		_hold += delta
		power_changed.emit(desktop_power(_hold, POWER_SWEET))


## 桌面与触屏一致:旋臂每帧 set_aim(当前扫描角),点住 begin_charge 蓄力、松开 release 投掷。
## (按下/松开事件由 view 的 _unhandled_input 接鼠标左键/屏幕触摸,见 darts_room_view)
func set_aim(aim: float) -> void:
	_aim = clampf(aim, 0.0, 1.0)
	aim_changed.emit(_aim)


func begin_charge() -> void:
	_charging = true
	_hold = 0.0


func release() -> void:
	if not _charging:
		return
	_charging = false
	thrown.emit(_aim, desktop_power(_hold, POWER_SWEET))


## touch 一次性投掷(view 从 drag 算好 aim/power 直接投)。
func fire(aim: float, power: float) -> void:
	thrown.emit(clampf(aim, 0.0, 1.0), clampf(power, 0.0, 1.0))
