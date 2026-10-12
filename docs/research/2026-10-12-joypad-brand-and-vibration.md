# Godot 4.7 手柄品牌/布局识别与震动 —— 调研

> 工单:GitLab #3(Part of #1)。日期:2026-10-12。
> 一手来源:Godot `4.7-stable` 源码(commit `5b4e0cb`)与其类参考源文件 `doc/classes/Input.xml`、SDL `release-3.2.28` 源码(Godot 4.7 内置版本)、nathanhoad/godot_input_helper `main@ccfad58`、本仓库 kit 代码。
> 链接前缀约定:`G/` = `https://github.com/godotengine/godot/blob/4.7-stable/`;`IH` = `https://github.com/nathanhoad/godot_input_helper/blob/ccfad58f7eea997e3d4f0903dcac9212da2b2208/addons/input_helper/input_helper.gd`。
> 本文所有「未确认」均指:没有在一手源码/官方文档里找到依据,也未实机验证。

## 结论速览

- **4.5 起桌面/iOS 换成了 SDL3 输入后端**:`drivers/sdl/joypad_sdl.cpp` 在 `4.4-stable` 不存在、`4.5-stable` 存在;同时 `platform/windows/joypad_windows.cpp` 在 4.5 被删。4.7 内置 SDL 3.2.28。Android 与 Web **不走 SDL**,各有自己的驱动。
- **品牌识别最可靠的依据是 `get_joy_info()` 里的 `vendor_id`**(Windows/Linux/macOS/iOS 可用);**Android 与 Web 上它恒为空字典**,只能退回到名字关键字。
- **Web 上 `get_joy_name()` 对标准映射手柄会被改写成 `"Standard Gamepad Mapping"`**,品牌信息在 Godot API 层面完全丢失。
- **手柄震动 `start_joy_vibration` 只在 SDL 平台(Windows/Linux/macOS/iOS)生效**;Android、Web 的手柄震动在 4.7 源码里没有实现。`vibrate_handheld` 只在 Android/iOS/Web 生效;微信小游戏是否映射到 `wx.vibrateShort`:**未确认**。

## 1. 相关 API 一览(4.7)

| API | 作用 | 出处 |
|---|---|---|
| `Input.get_joy_name(device)` | 设备名;映射库命中时被替换为库里的名字 | [G/core/input/input.cpp#L616](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L616)、[#L2251](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L2251) |
| `Input.get_joy_guid(device)` | SDL 兼容 GUID;GUID 为空时用名字前 16 字符的 hex 代替 | [G/core/input/input.cpp#L697-L731](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L697-L731) |
| `Input.get_joy_info(device)` | 平台附加信息字典 | [G/doc/classes/Input.xml#L178](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Input.xml#L178) |
| `Input.is_joy_known(device)` | 是否有映射(按钮/轴索引符合标准常量) | [G/core/input/input.cpp#L2272](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L2272) |
| `Input.has_joy_vibration(device)` | 驱动是否声明支持震动(`4.4-stable` 类参考中尚无此方法;同族还有 `has_joy_light`、`has_joy_motion_sensors`) | [G/doc/classes/Input.xml#L301](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Input.xml#L301) |
| `Input.start_joy_vibration / stop_joy_vibration / is_joy_vibrating` | 手柄双马达震动 | [G/core/input/input.cpp#L1292](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L1292) |
| `Input.vibrate_handheld(duration_ms, amplitude)` | 设备本体(手机)震动 | [G/doc/classes/Input.xml#L807](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Input.xml#L807) |
| `Input.joy_connection_changed` 信号 | 热插拔 | 类参考 |

注意:`get_joy_info()` 里的 `vendor_id` / `product_id` 是 **String**(`itos(...)`),不是 int —— 比较时要 `.to_int()`。见 [G/drivers/sdl/joypad_sdl.cpp#L176](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L176)。

## 2. SDL3 后端(Windows / Linux / macOS / iOS)

- 构建开关 `sdl` 默认开("Enable the SDL3 input driver"):[G/SConstruct#L204](https://github.com/godotengine/godot/blob/4.7-stable/SConstruct#L204)。Windows 在 `DisplayServerWindows` 里 `memnew(JoypadSDL)`:[G/platform/windows/display_server_windows.cpp#L8155](https://github.com/godotengine/godot/blob/4.7-stable/platform/windows/display_server_windows.cpp#L8155);iOS 走 `drivers/apple_embedded/os_apple_embedded.mm`。
- SDL 版本 3.2.28:[G/thirdparty/README.md#L1005](https://github.com/godotengine/godot/blob/4.7-stable/thirdparty/README.md#L1005)。Windows 端启用了 WGI / DInput / HIDAPI / RawInput / XInput 五个后端:[G/drivers/sdl/SDL_build_config_private.h#L64-L69](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/SDL_build_config_private.h#L64-L69)。HIDAPI 意味着 PS4/PS5/Switch Pro 等直连识别与震动由 SDL 自己的驱动处理。
- **映射**:启动时把 Godot 内置映射库(`gamecontrollerdb.txt` + `godotcontrollerdb.txt` 生成的 `DefaultControllerMappings`)喂给 SDL:[joypad_sdl.cpp#L74](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L74)。SDL 认得的手柄标 `mapping_handled=true`,Godot 跳过自己的映射逻辑、直接 `is_known=true`:[joypad_sdl.cpp#L174](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L174)、[input.cpp#L715](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L715)。
- **名字**:SDL gamepad 用 `SDL_GetGamepadName`([joypad_sdl.cpp#L144](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L144)),如 SDL HIDAPI 驱动设的 `"Nintendo Switch Joy-Con (L)"` / `"Nintendo Switch Pro Controller"`([SDL_hidapi_switch.c#L1414-L1425](https://github.com/libsdl-org/SDL/blob/release-3.2.28/src/joystick/hidapi/SDL_hidapi_switch.c#L1414-L1425))、`"DualSense Edge Wireless Controller"`([SDL_hidapi_ps5.c#L536](https://github.com/libsdl-org/SDL/blob/release-3.2.28/src/joystick/hidapi/SDL_hidapi_ps5.c#L536))。名字是 SDL 内部字符串,**不是稳定契约**。
- **`get_joy_info` 键**([joypad_sdl.cpp#L172-L197](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L172-L197)):`raw_name`、`vendor_id`、`product_id`、`serial_number`(可选)、`steam_input_index`(Win/Linux/macOS,Steam Input 设备才有)、`xinput_index`(仅 Windows XInput 设备)。
- **GUID**:`SDL_GUIDToString(SDL_GetJoystickGUID(...))`,内含 VID/PID。类参考里「Windows 上 XInput GUID 一律被改写成 `__XINPUT_DEVICE__`」那句([Input.xml#L156](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Input.xml#L156))**是旧 `joypad_windows` 驱动的遗留描述**:4.7 的 Windows 平台已无该驱动,`__XINPUT_DEVICE__` 只剩 `_set_joypad_mapping` 里的一个判断和 `godotcontrollerdb.txt` 第 10 行的条目。
- **厂商 ID**(SDL `usb_ids.h`):Microsoft `0x045e`、Nintendo `0x057e`、Sony `0x054c`。[SDL usb_ids.h#L42-L55](https://github.com/libsdl-org/SDL/blob/release-3.2.28/src/joystick/usb_ids.h#L42-L55)。
- **布局**:SDL3 的 gamepad 按钮是**位置语义**(南/东/西/北),Godot `JOY_BUTTON_A` = 底部键 = Sony ×、Xbox A、**Nintendo B**;`JOY_BUTTON_B` = 右侧键 = Nintendo **A**。见 [G/doc/classes/@GlobalScope.xml#L2471-L2476](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/@GlobalScope.xml#L2471-L2476)。即:**逻辑按位置统一,图标/文字要按品牌换**(Switch 上「确认」若想用 A 键,是游戏自己的设计选择)。Godot 没有暴露 SDL 的 `SDL_GetGamepadType` / `SDL_GetGamepadButtonLabel`(4.7 源码中 `joypad_sdl.cpp` 未调用),品牌只能自己由 VID/名字推断。

**可靠性**:Windows 上 VID 可靠(USB/蓝牙 HID 都能拿到);Steam Input 开启时手柄可能以虚拟 Xbox 设备出现,此时 VID 与真实品牌不一致,`steam_input_index` 存在 —— 实际表现**未实机确认**。

## 3. Android(不走 SDL)

- 连接回调只传名字:`joy_connection_changed(p_device, p_connected, name)`,**无 GUID、无 info 字典**:[G/platform/android/java_godot_lib_jni.cpp#L447-L455](https://github.com/godotengine/godot/blob/4.7-stable/platform/android/java_godot_lib_jni.cpp#L447-L455)。名字来自 `InputDevice.getName()`:[GodotInputHandler.java#L402](https://github.com/godotengine/godot/blob/4.7-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/input/GodotInputHandler.java#L402)。
- 于是 `get_joy_guid()` = 名字前 16 字符的 hex(如 `58626f7820576972656c65737320436f` = "Xbox Wireless Co"),`godotcontrollerdb.txt` 里的 Android 条目正是按这种「名字 hex」做键的:[godotcontrollerdb.txt#L13-L22](https://github.com/godotengine/godot/blob/4.7-stable/core/input/godotcontrollerdb.txt#L13-L22);匹配不上就落到 `Default Android Gamepad` 回退映射([os_android.cpp#L144](https://github.com/godotengine/godot/blob/4.7-stable/platform/android/os_android.cpp#L144))。
- `get_joy_info()` **恒为空**(类参考明说,源码也印证)。
- 按钮是 Java 侧按 Android `KEYCODE_BUTTON_*` 直接换算成 Godot 按钮号([GodotInputHandler.java#L456](https://github.com/godotengine/godot/blob/4.7-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/input/GodotInputHandler.java#L456)),注释写明「Android A is SNES B」——同样是位置语义。
- **可靠性**:品牌只能靠 `get_joy_name()` 关键字,名字由手柄固件/系统给出,**不同机型和连接方式下的字符串未确认**。

## 4. Web(含微信小游戏)

- 连接时 `name = pad.id`,`guid = pad.mapping`(浏览器认作标准布局时就是 `"standard"`),否则拼成 `<OS><vendor><product>`:[library_godot_input.js#L233-L298](https://github.com/godotengine/godot/blob/4.7-stable/platform/web/js/libs/library_godot_input.js#L233-L298)。
- `godotcontrollerdb.txt` 有一条 `standard,Standard Gamepad Mapping,...,platform:Web`([#L28](https://github.com/godotengine/godot/blob/4.7-stable/core/input/godotcontrollerdb.txt#L28)),命中后 `_set_joypad_mapping` 用映射名覆盖设备名([input.cpp#L2251-L2258](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L2251-L2258))。**结果:Chrome 等浏览器上主流手柄的 `get_joy_name()` 一律返回 `"Standard Gamepad Mapping"`,`get_joy_guid()` 返回 `"standard"`,`get_joy_info()` 为空 —— Godot API 层面拿不到品牌。** 绕路只能 `JavaScriptBridge` 读 `navigator.getGamepads()[i].id`(Chrome 格式含 `Vendor: xxxx Product: xxxx`)。
- **微信小游戏**:没有 DOM `navigator.getGamepads`,手柄支持取决于所用 Godot 微信运行时/适配层,**未确认**。

## 5. 震动

| 平台 | `start_joy_vibration`(手柄) | `vibrate_handheld`(机身) |
|---|---|---|
| Windows / Linux / macOS | ✅ SDL `SDL_RumbleJoystick`,`has_joy_vibration` 取 SDL `CAP_RUMBLE` 属性([joypad_sdl.cpp#L85-L120、#L166](https://github.com/godotengine/godot/blob/4.7-stable/drivers/sdl/joypad_sdl.cpp#L85-L120))。macOS 限制见类参考 | ❌ 无效果(类参考:仅 Android/iOS/Web) |
| iOS | ✅ 同走 SDL(实机未确认) | ✅(时长需 iOS 13+) |
| Android | ❌ 4.7 Android 驱动未调用 `set_joy_features`,也无读取 `get_joy_vibration_*` 的代码;`has_joy_vibration` 恒 false | ✅ `VibrationEffect.createOneShot`,**需导出预设勾 `VIBRATE` 权限**,amplitude 生效:[GodotNativeBridge.kt#L179](https://github.com/godotengine/godot/blob/4.7-stable/platform/android/java/lib/src/main/java/org/godotengine/godot/nativeapi/GodotNativeBridge.kt#L179) |
| Web | ❌ 无 `vibrationActuator` 相关代码 | ⚠️ `navigator.vibrate(ms)`,忽略 amplitude,Safari / Firefox Android 不支持:[library_godot_input.js#L737-L743](https://github.com/godotengine/godot/blob/4.7-stable/platform/web/js/libs/library_godot_input.js#L737-L743) |
| 微信小游戏 | 未确认 | **是否映射到 `wx.vibrateShort/Long`:未确认**(Godot 官方 Web 实现只调 `navigator.vibrate`,微信环境下该函数是否存在取决于运行时适配层) |

补充:`start_joy_vibration` 本身只把参数存进 `joy_vibration`([input.cpp#L1292-L1308](https://github.com/godotengine/godot/blob/4.7-stable/core/input/input.cpp#L1292-L1308)),由驱动轮询时消费;参数越界(<0 或 >1)**静默丢弃**;`duration=0` 在 SDL 上等于 65.535 秒。weak→高频马达、strong→低频马达。

## 6. Input Helper 怎么判定设备

源码:[IH#L70-L99](https://github.com/nathanhoad/godot_input_helper/blob/ccfad58f7eea997e3d4f0903dcac9212da2b2208/addons/input_helper/input_helper.gd#L70-L99)(`_input`)、[IH#L102-L106](https://github.com/nathanhoad/godot_input_helper/blob/ccfad58f7eea997e3d4f0903dcac9212da2b2208/addons/input_helper/input_helper.gd#L102-L106)(`get_joy_name`)、[IH#L128-L154](https://github.com/nathanhoad/godot_input_helper/blob/ccfad58f7eea997e3d4f0903dcac9212da2b2208/addons/input_helper/input_helper.gd#L128-L154)(`get_simplified_device_name`)、[IH#L573-L598](https://github.com/nathanhoad/godot_input_helper/blob/ccfad58f7eea997e3d4f0903dcac9212da2b2208/addons/input_helper/input_helper.gd#L573-L598)(震动)。

1. `_input` 里:键盘/鼠标按键/鼠标移动(超过 `mouse_motion_threshold`)→ `keyboard`;手柄按键或摇杆超过死区 → 用 `Input.get_joy_name(event.device)` 算品牌。
2. 名字为空且 `get_joy_info` 第一个键含 `"xinput"` 时补成 `"XInput"`(旧 Windows 驱动时代的兼容;4.7 的 info 第一个键是 `raw_name`,这条基本走不到)。
3. **纯名字子串匹配(忽略大小写)**,字典按插入顺序首个命中即返回:普通模式 `xbox ← "XBox","XInput"`、`playstation ← "Sony","PS3","PS4","PS5","DUALSHOCK 4","DualSense","Nacon…"`、`steamdeck ← "Steam"`、`switch ← "Switch","Joy-Con","PowerA Core Controller"`,都不中 → `generic`;「granular」模式再细分 xbox_one/xbox_series/ps3/ps4/ps5/左右 Joy-Con。
4. 防抖:1 秒内不重复切换(注释说 Windows 上有手柄注册两次)。
5. 按钮显示名按品牌选标签表;`generic` 当 Xbox 标签处理。
6. 震动只是 `Input.start_joy_vibration` 的三档薄封装(small 0.4 weak / medium 0.7 strong / large 1.0 strong,时长 0.1s),不做平台判断,不碰 `vibrate_handheld`。

**它的弱点**(由上面源码与第 2–4 节推出):
- 完全不用 `vendor_id`,依赖 SDL/OS 给的名字字符串;
- **Web 上恒判 `generic`**(名字被改成 "Standard Gamepad Mapping");
- granular 模式下 `"Switch"` 在 `"Joy-Con (L)"` 之前,而 SDL 的 Joy-Con 名字是 `"Nintendo Switch Joy-Con (L)"`,所以**左右 Joy-Con 子类型实际不会命中**(按源码推断,未实机确认);
- `"Steam"` 会把 Steam Input 虚拟手柄也判成 Steam Deck(名字是否含 Steam 未实机确认)。

## 7. kit 现状与差距

现状 —— [addons/godot-core-kit/systems/input_manager.gd#L12](../../addons/godot-core-kit/systems/input_manager.gd)、`_update_device` 第 155 行:

- `enum DeviceType { KEYBOARD_MOUSE, GAMEPAD, TOUCH }`,按事件类别判来源,摇杆有 0.2 死区,变化时发 `device_changed(device_type)`。
- 只区分「是不是手柄」,**不区分品牌、不记录哪个 device index**,没有震动封装,没有热插拔处理。

差距:
1. 无品牌/布局字段 → UI 无法换 Xbox/PS/Switch 图标与确认键提示;
2. 无 device index → 多手柄时不知道该震哪个、该显示哪个的图标;
3. 无震动 API → 消费方要自己写平台判断(手柄 vs 机身);
4. 无防抖(Input Helper 有 1 秒防抖,kit 没有;是否需要取决于 Windows 是否真有重复注册,4.7 SDL 下**未确认**)。

## 8. 对 kit 的建议

**品牌/布局识别**——分层取证,第一层命中即止:
1. `get_joy_info(d).get("vendor_id","").to_int()`:`0x045e`→Xbox、`0x054c`→PlayStation、`0x057e`→Switch(Windows/Linux/macOS/iOS 可用,最可靠);
2. 名字关键字(`get_joy_name` + `info.raw_name`),关键词表参考 Input Helper,但**更具体的词放前面**(Joy-Con 先于 Switch);Android 只能走这层;
3. 都不中 → `GENERIC`,图标用位置语义(南/东/西/北)或 Xbox 风格兜底。
4. Web:`get_joy_name()=="Standard Gamepad Mapping"` 时可选地经 `JavaScriptBridge` 读 `navigator.getGamepads()[i].id` 再走第 2 层;不做也行,直接 `GENERIC`。微信:`GENERIC`。
- 产出建议:`DeviceType` 不动(仍是来源类别),新增 `get_joypad_brand(device) -> JoypadBrand { XBOX, PLAYSTATION, SWITCH, GENERIC }` 纯函数 + `current_joypad_index`;品牌在 `joy_connection_changed` 时算一次缓存,不在 `_input` 里逐事件算。判定函数纯输入(vid 字符串 + 名字)→ 好写 headless 单测。
- 布局:按钮逻辑统一用 Godot 的位置语义,**不按品牌交换 A/B**;品牌只影响图标与文字。

**各平台降级**:Windows/桌面 = VID→名字→GENERIC;Android = 名字→GENERIC;Web/微信 = GENERIC(可选 JS 补救)。

**震动统一程度**:可以统一成一个 `CoreKit.input.rumble(strength, duration, device := -1)`:
- 有手柄且 `Input.has_joy_vibration(device)` → `start_joy_vibration`(桌面/iOS 生效);
- 否则(触屏或手柄不支持)→ `vibrate_handheld(ms, amplitude)`(Android 需 VIBRATE 权限;Web 不管强度;桌面无效果);
- 微信:接口留 `wx.vibrateShort` 钩子,是否需要由 kit-wechat 实测后再定(当前**未确认** Godot 微信运行时的行为)。
- 能统一的只有「强度 0–1 + 时长」这一层;双马达区分、Android 手柄震动、Web 手柄震动在 4.7 都做不到,文档里明确写成平台限制即可,不要自己补原生实现。
