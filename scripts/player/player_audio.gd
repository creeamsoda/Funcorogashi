class_name PlayerAudio
extends RefCounted
## プレイヤーのSE。AudioStreamPlayer はプレイヤー直下に名前付きで置く(テストから名前で参照する)。

const HIT_SE: AudioStream = preload("res://resources/audio/hit.wav")
const WALL_HIT_SE: AudioStream = preload("res://resources/audio/wallHit.wav")
const CHARGE_SE: AudioStream = preload("res://resources/audio/charge.wav")
const DASH_SE: AudioStream = preload("res://resources/audio/dash.wav")
const GET_NEUTRAL_SE: AudioStream = preload("res://resources/audio/getNeutral.wav")
const GET_HIGH_SE: AudioStream = preload("res://resources/audio/getHigh.wav")
const GET_HIGH_HIGH_SE: AudioStream = preload("res://resources/audio/getHighHigh.wav")
## 密集したフンを連続取得しても直前の取得音を打ち切らないための同時発音数。
const PICKUP_POLYPHONY := 4

var hit: AudioStreamPlayer
var wall_hit: AudioStreamPlayer
var charge: AudioStreamPlayer
var dash: AudioStreamPlayer
var get_neutral: AudioStreamPlayer
var get_high: AudioStreamPlayer
var get_high_high: AudioStreamPlayer


func _init(parent: Node) -> void:
	hit = _create(parent, "HitSE", HIT_SE)
	wall_hit = _create(parent, "WallHitSE", WALL_HIT_SE)
	charge = _create(parent, "ChargeSE", CHARGE_SE)
	dash = _create(parent, "DashSE", DASH_SE)
	get_neutral = _create(parent, "GetNeutralSE", GET_NEUTRAL_SE, PICKUP_POLYPHONY)
	get_high = _create(parent, "GetHighSE", GET_HIGH_SE, PICKUP_POLYPHONY)
	get_high_high = _create(parent, "GetHighHighSE", GET_HIGH_HIGH_SE, PICKUP_POLYPHONY)


## 先頭から鳴らし直す。
static func restart(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	player.play()


## 実際の獲得量に応じた取得SE(通常・大きめ・最大級)。前の音に重ねて鳴らす。
func play_pickup(amount: float) -> void:
	var neutral_max := maxf(Config.balance.pickup_se_neutral_max, 0.0)
	var high_high_min := maxf(Config.balance.pickup_se_high_high_min, neutral_max)
	if amount >= high_high_min:
		get_high_high.play()
	elif amount > neutral_max:
		get_high.play()
	else:
		get_neutral.play()


func stop_charge() -> void:
	charge.stop()


func stop_all() -> void:
	for p in [hit, wall_hit, charge, dash, get_neutral, get_high, get_high_high]:
		(p as AudioStreamPlayer).stop()


static func _create(parent: Node, node_name: String, stream: AudioStream, polyphony: int = 1) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.max_polyphony = polyphony
	parent.add_child(player)
	return player
