# InputManager —— 重绑定持久化 + 设备检测 + 输入前缓冲 + 手柄品牌/图标/震动

> `CoreKit.input` · `systems/input_manager.gd`

## 职责

动作(action)仍在工程 Input Map 里定义,本子系统不发明第二套动作系统,只补这些事:

1. **按设备分槽的重绑定**:每个动作有键盘鼠标(`KEYBOARD_MOUSE`)和手柄(`GAMEPAD`)两个绑定槽。`rebind_action` 只替换新事件所在的槽,另一个槽原样保留;经注入的 Settings 持久化(section `"input"`),`bind_settings` 时恢复。
2. **设备检测**:`device_changed` 在输入来源(键鼠/手柄/触屏)变化时广播。
3. **前缓冲**:`is_action_buffered` 在窗口期内查询动作是否按下过。
4. **手柄品牌、按键图标键名、统一震动**(0.25.0):`joypad_changed` 告诉 UI 当前手柄是什么品牌;`glyph_key` 给出稳定的图标键名,游戏用它查自己的贴图;`rumble` 能震手柄就震手柄,否则震手机机身。

不做:多玩家按手柄号分开路由、组合键、多个副槽、触屏虚拟键重绑、coyote time。

## 公开 API

```gdscript
enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }
enum JoypadBrand { GENERIC, XBOX, PLAYSTATION, SWITCH }

signal device_changed(device_type: DeviceType)        # 输入设备变化时广播(仅变化时)
signal action_rebound(action: String)                 # 某动作被重绑定/清空/重置后广播(UI 收到后重新查询)
signal joypad_changed(device: int, brand: JoypadBrand) # 当前手柄或它的品牌变化时广播

var current_device: int = DeviceType.KEYBOARD_MOUSE
var current_joypad: int = -1      # 最近产生手柄输入的设备号
var rumble_enabled: bool = true   # 震动总开关,赋值即持久化(input._rumble_enabled)

# 绑定
func bind_settings(settings) -> void
func slot_of(event: InputEvent) -> int                # 事件所属槽;不可绑定返回 -1
func rebind_action(action: String, event: InputEvent) -> bool   # 只替换 slot_of(event) 那个槽
func unbind_action(action: String, device: int) -> bool         # 清空一个槽,并持久化「清空」
func reset_action(action: String, device := -1) -> void         # -1 整个动作复位;传槽只复位该槽
func reset_all() -> void
func get_action_event(action: String, device := -1) -> InputEvent  # -1 第一个事件;传槽取该槽第一个,空槽 null
func action_for_event(event: InputEvent, among := PackedStringArray()) -> String

# 缓冲
func is_action_buffered(action: String, window_sec: float) -> bool
func consume_buffer(action: String) -> void

# 手柄
func brand_from(vendor_id: String, joy_name: String) -> JoypadBrand  # 纯函数:VID → 名字关键字 → GENERIC
func get_joypad_brand(device: int) -> JoypadBrand                   # 读缓存(连接时算好)
func glyph_key(event: InputEvent, brand := JoypadBrand.GENERIC) -> String   # 如 xbox/a、kbm/key_space
func glyph_text(event: InputEvent, brand := JoypadBrand.GENERIC) -> String  # 文字兜底,如 "A"、"✕"、"Space"
func rumble(strength: float, duration_sec: float, device := -1) -> void
func stop_rumble(device := -1) -> void
```

## 依赖

被门面经 `input.bind_settings(settings)` 注入 `Settings` 引用。未注入时 `_settings` 为 `null`——重绑、清空、复位仍会即时作用于 `InputMap`,只是不持久化。

## 用法示例

```gdscript
# 键盘和手柄各自重绑,互不覆盖
CoreKit.input.rebind_action("jump", key_event)    # 只改键盘槽
CoreKit.input.rebind_action("jump", pad_event)    # 只改手柄槽
CoreKit.input.reset_action("jump", CoreKit.input.DeviceType.GAMEPAD)  # 只复位手柄槽

# 按当前手柄品牌换按键提示图标;没图就用文字兜底
CoreKit.input.joypad_changed.connect(func(device, brand):
    var ev := CoreKit.input.get_action_event("jump", CoreKit.input.DeviceType.GAMEPAD)
    var path := "res://ui/glyphs/%s.png" % CoreKit.input.glyph_key(ev, brand)
    if ResourceLoader.exists(path):
        $Prompt.texture = load(path)
    else:
        $PromptLabel.text = CoreKit.input.glyph_text(ev, brand))

# 受击震一下
CoreKit.input.rumble(0.6, 0.15)

# 输入前缓冲
if CoreKit.input.is_action_buffered("jump", 0.15):
    CoreKit.input.consume_buffer("jump")
```

## 注意事项

- **存档格式**(0.25.0):`input` 段 key 是动作名,value 是 `{"kbm": <事件 dict> | null, "gamepad": <事件 dict> | null}`,**只存改过的槽**。缺 key 表示用默认,`null` 表示被 `unbind_action` 显式清空。旧版本存的单事件 dict(带 `"type"`)照常读取,归到它所在的槽、另一个槽用默认;下次写这个动作时才转成新格式。某个槽的数据损坏时只跳过这个槽并 `push_warning`。
- **事件规范化**:重绑和读档都会把事件在序列化格式里走一遍,并统一设 `device = -1`(任意设备)。本局生效的绑定和重启后恢复的完全一致;改过的手柄键不会只认 0 号手柄(0.24 及以前的 bug)。
- **一个槽可以有多个默认键**(如 W 和 ↑)。玩家重绑后这个槽只剩一个键;按槽复位后恢复成多个。
- **品牌识别**:桌面和 iOS 按 `get_joy_info().vendor_id`(十进制字符串)→ 名字关键字 → GENERIC 判断;Android 只能靠名字,判不出就是 GENERIC;Web 和微信小游戏上名字是 `"Standard Gamepad Mapping"`,一律 GENERIC。品牌只影响显示,按键逻辑统一用 Godot 的位置语义(`JOY_BUTTON_A` 是底部键),**不按品牌交换 A/B**。Switch 的底部键印的是 B,所以 `glyph_key` 返回 `switch/b`。
- **图标**:kit 不带任何图标资源(主机厂按键图有商标问题,美术风格也该由游戏定)。推荐 Kenney Input Prompts(CC0),用一张映射表把 `glyph_key` 对到它的文件名即可。
- **震动**:`duration_sec <= 0` 什么都不做(SDL 上 duration=0 等于震 65 秒);`strength` 先 clamp 到 [0,1]。`device = -1` 时只在当前输入设备是手柄时震当前手柄,否则回退 `Input.vibrate_handheld`。手柄震动只在 SDL 平台(桌面、iOS)生效;Android 和 Web 上震的是手机机身;微信小游戏没有 `navigator.vibrate`,kit 在 Web 上能拿到 `wx` 时改调微信震动——微信只有短震(约 15ms,按 `strength` 三等分映射 light / medium / heavy)和长震(约 400ms,`duration_sec ≥ 0.2` 时用),所以 `duration_sec` 只用来选这两种,不能精确控制时长;Android 导出需勾选 `VIBRATE` 权限;桌面上没有可震设备时什么都不发生。
- 摇杆漂移噪声门限 `MOTION_DEADZONE = 0.2`:低于此幅值的摇杆事件不切换设备,也不切换当前手柄。
- 键盘绑定用 `physical_keycode`(布局无关)。
- `_snapshot_defaults()` 必须在应用任何覆盖之前调用;`_ready` 会自动调,脱离场景树的测试需手动调。
- 前缓冲是全动作线性扫描,**启动后新增的动作不在扫描列表内**。
- 测试接缝:`_ticks_msec_func`(假时钟)、`_input_backend`(替代 `Input` 单例,记录震动调用、伪造手柄信息)。
