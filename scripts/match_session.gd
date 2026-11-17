class_name MatchSession
extends RefCounted
## シーン遷移をまたぐ選択。共有BalanceConfigをモード切り替えで変更しない。

const DEFAULT_COURSE := "res://resources/solo/default_course.tres"
const GAME_SCENE := "res://scenes/Game.tscn"
const MENU_SCENE := "res://scenes/Main.tscn"
const TUTORIAL_SCENE := "res://scenes/Tutorial.tscn"
const RULES_VERSION := 1

static var mode := "versus"
static var course_path := DEFAULT_COURSE
static var course_override: SoloCourse
static var _run_serial := 0

static func load_course() -> SoloCourse:
	return course_override if course_override != null else load(course_path) as SoloCourse

static func start(tree: SceneTree, selected_mode: String) -> void:
	mode = selected_mode
	tree.change_scene_to_file(GAME_SCENE)

## 「みんなでバトル！」: チュートリアルありならチュートリアルシーンを挟んでから試合へ。
static func start_versus(tree: SceneTree, with_tutorial: bool) -> void:
	mode = "versus"
	tree.change_scene_to_file(TUTORIAL_SCENE if with_tutorial else GAME_SCENE)

static func retry(tree: SceneTree) -> void:
	tree.change_scene_to_file(GAME_SCENE)

static func show_menu(tree: SceneTree) -> void:
	tree.change_scene_to_file(MENU_SCENE)

static func new_run_id() -> String:
	_run_serial += 1
	return "%s-%d-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec(), _run_serial]

static func score_profile(course: SoloCourse, balance: BalanceConfig) -> String:
	# パス/インスタンスIDではなく、実際のコース内容と調整値で条件を分ける。
	var rules := {"version": RULES_VERSION, "course": _encode(course), "balance": _encode(balance)}
	return "%s-v%d-%s" % [course.course_id, course.version, JSON.stringify(rules, "", true).sha256_text()]

static func _encode(value: Variant) -> Variant:
	if value is Resource:
		var fields := {}
		for property in value.get_property_list():
			var key: String = property["name"]
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE and not key.begins_with("resource_") and key != "script":
				fields[key] = _encode(value.get(key))
		return fields
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_encode(item))
		return items
	if value is Dictionary:
		var fields := {}
		for key in value:
			fields[str(key)] = _encode(value[key])
		return fields
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value
	return var_to_str(value)
