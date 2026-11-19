# 外壁用の岩（試作）

大きなじゃがいものような輪郭を持つ、ステージ外壁用の岩モデル案です。形と色の方向性を見るための単体パーツで、壁一区画の組み合わせや配置はまだ含めていません。

## ファイル

| ファイル | 用途 |
| --- | --- |
| `../../resources/models/rock/rock.glb` | Godot用モデル |
| `../../resources/models/rock/rock_camel.glb` | 中央が少し凹んだ、二つのコブを持つ岩 |
| `../../resources/models/rock/rock_asymmetric.glb` | 左と右下にボリュームを加えた背の高い岩 |
| `rock.blend` | Blender編集用。撮影用カメラ・ライト・床を含む |
| `rock_variants.blend` | 3パターンを並べたBlenderシーン |
| `rock_preview.png` | 斜め上からの形状確認画像 |
| `rock_variants_preview.png` | 3パターンを並べた比較画像 |
| `model_stats*.json` | 頂点数・三角形数・寸法 |
| `../../tools/create_rock_model.py` / `create_rock_variants.py` | モデルの新規生成 |
| `../../tools/export_rock_variants.py` | 編集済みBlenderシーンからGLBと確認画像を更新 |

## 形状

- Blenderメッシュ: **70面 / 296三角形**（目安の約500三角形以内）
- 前面と上面は多角形面を細かく配置し、隠れる背面下側は大きな面にまとめています
- 複数の三角形で構成される多角形を平面として扱い、三角形ごとに向きが変わる印象を抑えています
- 横幅と奥行きに差をつけた丸い塊。大きな凹凸を付け、底面は少し平たくしています
- glTF書き出し時に多角形面は三角形へ分割されますが、各面の法線は共有されます
- 岩の大きな面が見えるよう、面ごとに不均一なグレーを付けています
- BlenderはZ上、GodotではglTF経由でY上に変換されます

## 追加パターン

- `rock_camel.glb`: 左右端寄りの幅広い頂部を持ち、中央が鞍状に下がる岩
- `rock_asymmetric.glb`: 元モデルより少し背を高くし、左側と右下側に膨らみを足した岩
- どちらも元モデルを変形せず、別々の向きと乱数で面分割したメッシュから作っています
- ラクダ型は左右端寄りに幅広い頂部を置き、中央の浅い鞍につないでいます。底面の最小Zは0です
- ラクダ型は72面中57面、非対称型は74面中56面が五角形以上です
- ラクダ型は304三角形、非対称型は310三角形です
- 非対称型の高さは元モデルより約9%高くしています
- どちらも元モデルと色合いをそろえ、約500三角形以内です
- 2つの追加モデルと元モデルを並べた確認画像は `rock_variants_preview.png` です

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python-exit-code 1 --python tools/create_rock_model.py
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python-exit-code 1 --python tools/create_rock_variants.py
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python-exit-code 1 --python tools/export_rock_variants.py
```
