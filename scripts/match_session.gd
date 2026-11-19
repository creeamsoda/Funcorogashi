class_name MatchSession
extends RefCounted
## シーン遷移をまたぐ選択。共有BalanceConfigをモード切り替えで変更しない。
## mode: "versus"(みんなでバトル！) / "solo"(ひとりで遊ぶ = 人間1人+CPU3体)。

const GAME_SCENE := "res://scenes/Game.tscn"
const MENU_SCENE := "res://scenes/Main.tscn"
const TUTORIAL_SCENE := "res://scenes/Tutorial.tscn"

static var mode := "versus"

static func start(tree: SceneTree, selected_mode: String) -> void:
	mode = selected_mode
	tree.change_scene_to_file(GAME_SCENE)

## 「みんなでバトル！」: チュートリアルありならチュートリアルシーンを挟んでから試合へ。
static func start_versus(tree: SceneTree, with_tutorial: bool) -> void:
	mode = "versus"
	tree.change_scene_to_file(TUTORIAL_SCENE if with_tutorial else GAME_SCENE)

## 「ひとりで遊ぶ」: 人間1人+CPU3体で対戦する。
static func start_solo(tree: SceneTree) -> void:
	start(tree, "solo")

static func retry(tree: SceneTree) -> void:
	tree.change_scene_to_file(GAME_SCENE)

static func show_menu(tree: SceneTree) -> void:
	tree.change_scene_to_file(MENU_SCENE)
