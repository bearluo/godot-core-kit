# farm-sim 真素材放置约定

`art_bank.gd` 的取图接缝 `ArtBank.tex(key)` **优先读本目录下 `<key>.png`**,否则回退程序化贴图。
把真像素素材(如 [Sprout Lands](https://cupnooble.itch.io/sprout-lands-asset-pack))按下表命名丢进来,
**零改代码**即自动替换对应的程序化贴图。放进来后跑一次 `godot --headless --path . --import` 生成导入缓存。

## key → 文件名 → 尺寸

| key(丢文件名 `<key>.png`) | 用途 | 建议尺寸 |
|---|---|---|
| `tile_grass` | 空地瓦片 | 32×32 |
| `tile_tilled` | 已耕瓦片 | 32×32 |
| `tile_watered` | 已浇瓦片 | 32×32 |
| `crop` | 通用作物株(view 按生长比例缩放 + 绿→金着色;真素材建议近白剪影或自带配色) | 32×32 |
| `player_down_0` / `player_down_1` | 玩家朝下 静止/踏步帧 | 24×24 |
| `player_up_0` / `player_up_1` | 玩家朝上 | 24×24 |
| `player_left_0` / `player_left_1` | 玩家朝左 | 24×24 |
| `player_right_0` / `player_right_1` | 玩家朝右 | 24×24 |
| `npc` | NPC 小人 | 24×24 |
| `bed` | 农舍床 | 48×64 |
| `shop_sign` | 小镇商店牌 | 72×56 |
| `door` | 门(近白,door.gd 用 modulate 上各门颜色) | 40×40 |
| `fx_star` / `fx_drop` / `fx_dust` / `fx_gold` | 粒子点纹理 | 8×8 |

## 说明

- **透明底**:作物/角色/物件/粒子用带 alpha 的 PNG;瓦片可不透明。
- **逻辑不动**:素材只换表现,FarmGrid 等 model 与坐标换算(格 32px)不变。想换更大尺寸的角色/物件,
  贴图会按 renderer 里的目标矩形缩放,超出格子是允许的(如床占多格视觉)。
- **平面俯视**:当前为平面俯视。2.5D 方格 3/4 视角是后续独立项,届时 renderer 会换、素材约定另订。
