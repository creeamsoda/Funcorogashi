# フンコロガシ 3Dモデル

提供された三面図「背景.png」を基にしたゲーム用モデルです。前方の湾曲した2本を腕、側面の2対を脚として制作しています。

## ファイル

| ファイル | 用途 |
| --- | --- |
| `../../resources/models/beetle/beetle.glb` | Godot等へ読み込むモデル。マテリアル・画像を内包 |
| `beetle.blend` | Blender編集用。モデルと、書き出し対象外の撮影用コレクション |
| `textures/wing_basecolor.png` | 現在の羽の色と中央線。1024×1024 |
| `textures/wing_paint_blank.png` | 羽に貼る画像を制作する白紙。1024×1024 |
| `textures/wing_uv_guide.png` | 羽の上面UV線。透明背景なので画像編集ソフトで重ねて使用 |
| `textures/wing_uv_guide.svg` | 同じUV線のベクター版 |
| `preview/beetle_final.png` | 保存済みのゲーム用GLBを読み直して撮影した最終確認画像 |
| `preview/beetle_preview.png` | 斜め上からの完成見本 |
| `preview/beetle_front_oblique.png` | 腕の下向きの角度と平たい形を確認する前方からの見本 |
| `preview/beetle_top.png` / `beetle_side.png` / `beetle_front.png` | 三方向からの確認画像 |
| `preview/beetle_wire.png` | 三角形分割の確認画像 |
| `preview/beetle_arm_pose.png` | 腕を付け根から回転させた確認画像 |
| `model_stats.json` | 部品ごとの頂点数・三角形数・閉じたメッシュの検証結果 |
| `validation/validation.json` | Godotで実際に読み込んだモデルの検証結果 |
| `validation/blender_validation.json` | 保存済みBlenderデータの形状検査とGLBとの一致確認。検査したファイルのSHA-256を記録 |

## ポリゴン数

- 制作メッシュ: **890頂点**。
- GLB書き出し後: **922頂点、1,740三角形**。羽のマテリアル境界で分割される頂点も含めた数です。
- メッシュ10個、マテリアル3個。サブディビジョン不要。
- モデルの全メッシュは閉じており、非多様体の辺・面積ゼロの面はありません。
- Blenderの撮影用の床・カメラ・ライトはGLBに含みません。

## 羽に画像を貼る

`WingShell` の上面は、左右の羽を一続きにしたメッシュです。中央の谷間、隙間、段差はありません。中央線はテクスチャにだけ描いてあります。

上面には左右を反転しない連続した平面投影UVを設定しています。画像の上が頭側、下が尾側です。中央をまたぐ絵や文字も貼れます。上から見たときの画像の形を優先しているため、曲面の側端では貼った画像が伸びます。重要な絵や文字はUV外周から少し内側に置いてください。

1. `wing_paint_blank.png` を画像編集ソフトで開き、`wing_uv_guide.png` を別レイヤーとして重ねます。
2. ガイド内に絵や写真を配置します。ガイド線は書き出す前に非表示にします。UVの外側にも色を少しはみ出させると境界が目立ちません。
3. Blenderでは `WingShell` → `Wing_Image` マテリアルの `Replace_With_Your_Image` 画像テクスチャを新しい画像へ差し替えます。
4. 中央線を残す場合は、新しい画像の横幅中央にも線を描きます。画像を差し替えるだけなら現在の線は消えます。

Godotでは `WingShell` の**サーフェス0**が画像用、サーフェス1が裏面です。GLBインスタンスを `beetle` とすると、画像を差し替える例は以下です。

```gdscript
var wings := beetle.get_node("Beetle/WingShell") as MeshInstance3D
var material := wings.get_active_material(0).duplicate() as StandardMaterial3D
material.albedo_texture = load("res://your_wing_image.png")
wings.set_surface_override_material(0, material)
```

## 腕の回転

腕は付け根から地面方向へ下がる形状です。断面は幅に対して厚さ約32%の平たい楕円にし、腕と脚の先端は太さを残した丸い形にしています。

`Arm_L` と `Arm_R` はそれぞれ独立した剛体メッシュで、オブジェクトの原点が胸部内部の付け根にあります。オブジェクトを回転させれば腕全体が動きます。ボーン・ウェイト・肘用の関節は不要な構成です。完成モデルは初期姿勢で保存してあり、アニメーションクリップは含めていません。

GodotでGLBをインスタンス化すると、シーンのルート `beetle` の下に `Beetle` があり、その直下に各部品があります。左右はキャラクター自身から見た呼び方で、左腕はX負側、右腕はX正側です。

```gdscript
var left_arm := beetle.get_node("Beetle/Arm_L") as Node3D
var right_arm := beetle.get_node("Beetle/Arm_R") as Node3D
# Y軸: 平面内の開閉。X軸: 腕の上げ下げ。
left_arm.rotation.y = deg_to_rad(-15.0)
right_arm.rotation.y = deg_to_rad(15.0)
```

脚も `Leg_Middle_L` / `Leg_Middle_R` / `Leg_Rear_L` / `Leg_Rear_R` として独立し、付け根から回転できます。付け根は体内に差し込んでいます。大きく回転させる演出では腕と頭・胸の重なりを確認してください。

Godotでは **Y上・前方−Z**、Blenderでは **Z上・前方＋Y** です。

## 最終データの確認

保存済みの `.blend` と `.glb` を検査する場合は、リポジトリのルートで次を実行します。モデル自体は上書きせず、検証結果と `preview/beetle_final.png` を更新します。完成画像はGLBを読み直してレンダリングしています。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python-exit-code 1 --python art/beetle/validation/validate_blender.py
& 'C:\Users\sotak\OneDrive\デスクトップ\Godot_v4.7.2-stable_win64.exe' --headless --path art/beetle/validation --script validate.gd
```

Blender側では閉じたメッシュ、面の向き、面積ゼロの三角形、UVの反転、内包テクスチャ、初期姿勢、およびGLBとの頂点位置・回転軸・三角形数の一致を確認します。Godot側では実際のGLBを直接読み込み、頂点数、羽のUV・画像、腕と脚の回転軸、地面へのめり込みを確認します。各JSONの `passed` が `true`、コマンドの終了コードが `0` なら検査合格です。

## 再生成

Blender 5.2.1で制作しています。リポジトリのルートから以下を実行すると、モデル・テクスチャ・確認画像を再生成します。手作業で編集した同名ファイルも上書きするため、編集版は別名で保存してください。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/create_beetle_model.py
```

`art/beetle/.gdignore` により、編集用Blenderファイルや確認画像はGodotのインポート対象から除外しています。ゲームで使うGLBは `resources/models/beetle/` にあります。
