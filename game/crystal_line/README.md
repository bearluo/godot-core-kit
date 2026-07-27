# 晶核防线 (Crystal Line)

Green TD / Element TD 系路径塔防的手游竖屏 example。验证 `vision-first-slice` + `asset-bank`。

## 运行

```
godot --path . res://game/crystal_line/main.tscn
```

## 目录

| 路径 | 作用 |
|---|---|
| `sim/crystal_line_sim.gd` | 纯逻辑(headless 可测) |
| `gfx/art_bank.gd` | 美术三级接缝 |
| `sfx/sound_bank.gd` | 音效三级接缝 |
| `assets/generated/` | bake_assets.gd 烘焙基线 |
| `main.tscn` | 生产场景 |

## 烘焙资源

```
godot --headless --path . -s res://.claude/skills/asset-bank/bake_assets.gd -- \
  --art res://game/crystal_line/gfx/art_bank.gd \
  --sound res://game/crystal_line/sfx/sound_bank.gd
```

## 愿景

见 `docs/vision/vision-one-pager.md`。
