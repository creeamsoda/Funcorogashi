class_name ToonMaterial
extends RefCounted

## トゥーン調の見た目を作るマテリアルの共通窓口。
## 陰影とハイライトを段階的にする(StandardMaterial3D の TOON モード)。
## 型は StandardMaterial3D のままなので、色の書き換え・点滅処理はそのまま使える。

## GLB由来の共有マテリアルをトゥーン化した複製。元マテリアルごとに1つだけ作る。
static var _shared_cache: Dictionary = {}


## 指定色のトゥーンマテリアルを新規に作る。
static func create(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	apply(mat)
	return mat


## 既存マテリアルの陰影設定をトゥーンにする(色やテクスチャは変えない)。
static func apply(mat: BaseMaterial3D) -> void:
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	# 金属感を消し、ハイライトを小さくはっきりさせる。
	mat.metallic = 0.0
	mat.roughness = 0.6


## 複数個体で共有してよいマテリアルを、元を書き換えずにトゥーン化して返す。
static func shared_from(source: BaseMaterial3D) -> BaseMaterial3D:
	if _shared_cache.has(source):
		return _shared_cache[source]
	var mat := source.duplicate() as BaseMaterial3D
	apply(mat)
	_shared_cache[source] = mat
	return mat
