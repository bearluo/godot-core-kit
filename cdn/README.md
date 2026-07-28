# CDN 下载探针素材

验 `CoreKit.updater` 的**下载段**在微信小游戏上能否跑通(挂载段由 `_probe_pack_mount` 单独验)。
模拟器 `project.config.json` 的 `urlCheck: false` 不校验合法域名,所以本地地址能通 —— **真机不成立**
(要合法域名白名单 + ICP 备案)。

## 两条投递通道(都实测通过)

| | 本地 py server | **filebrowser 公开分享**(推荐) |
|---|---|---|
| 起法 | `python3 cdn/serve.py`(前台占终端) | 常驻 Docker,不用起 |
| URL base | `http://127.0.0.1:8099/` | `http://172.25.50.135:8081/api/public/dl/<hash>/` |
| 局域网可达 | 否(绑 127.0.0.1) | **是** —— 真机也够得着 |
| 素材放哪 | `cdn/` | `E:\work\godot-core-kit\build\cdn\`(= 托管根 `build/` 下) |

filebrowser **有鉴权**,`/api/raw/…` 直链要 token。要免登录下载得建**公开分享**;
对**目录**建 share 后 hash 固定,之后往目录里丢新文件不用重建 share —— 正好是 CDN base URL 语义:

```bash
TOK=$(curl -s -X POST http://172.25.50.135:8081/api/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"<pw>"}')
curl -s -X POST "http://172.25.50.135:8081/api/share/cdn" -H "X-Auth: $TOK" -d '{}'
# → {"hash":"5MwZWGEX","path":"/cdn","expire":0,"hasPassword":false}
```

⚠️ `http://…/share/<hash>` 是**给人看的页面**;机器下载要走 `http://…/api/public/dl/<hash>/<文件>`。

## 跑一轮

```powershell
$G = "D:\Program Files\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe"

# 1. 起本地 CDN(前台占一个终端)
python3 cdn/serve.py

# 2. 造内容包 + manifest(版本号每轮 +1,否则 check 返回 up_to_date 不下载)
"pack-v7-from-cdn" | Out-File -NoNewline cdn/probe_cdn.txt
& $G --headless --path . --script res://cdn/make_pck.gd -- "<abs>/cdn/probe_cdn.txt" "<abs>/cdn/probe_pack-v7.pck"
#   改 cdn/spec.json 的 version / file / url 到 v7
& $G --headless --path . --script res://addons/godot-core-kit/tools/build_manifest.gd -- cdn/spec.json cdn/manifest.json

# 3. 本机基线(先在桌面确认探针本身对)
& $G --headless --path . --quit-after 300     # 看 PROBE CDN 各段

# 4. 导出到微信小游戏工程
& $G --headless --path . --export-debug "Web" "<abs>/dist/kit-demo.html"

# 5. 微信侧观测:见全局 skill wechat-minigame-cdp
```

## 坑

- **内容包必须是真 `.pck`(GDPC 头)**,不能拿 zip 改后缀。`_download_next` 硬编码 `.pck` 落盘名,
  而 Godot 的 `ZipArchive::try_open_pack` 按**扩展名**过滤(只收 `.zip`/`.pcz`)、`PackedSourcePCK`
  又要 `GDPC` magic,`.pck` 后缀的 zip 两边都不认 → `mount_failed`。
- **`cli.bat close` 关不掉模拟器**(报成功但 CDP target 还活着,游戏继续跑)。要换新代码必须
  `cli.bat quit` 退整个 IDE 再 `launch.ps1` 重启。
- `cdn/*` 已在 `export_presets.cfg` 的 `exclude_filter` 里,不会被打进游戏包。

## 实测结论(2026-07-28)

微信小游戏上 `check → download → sha256 → 落盘 → mount` 全链路通,详见
`docs/research/2026-07-28-subpack-runtime-vs-kit-updater.md` §3。
