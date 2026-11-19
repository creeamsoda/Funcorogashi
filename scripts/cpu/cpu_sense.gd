class_name CpuSense
extends RefCounted
## CPUの知覚。画面に見えている情報だけをまとめる:
## プレイヤー(位置・速度・保有サイズ・状態・向き)、地面のフン(種類・動いているか・速度)、壁/フェンス/杭。
## フンの速度は位置の差分から推定する(内部の逃走状態は読まない)。

## 前方を探るレイの高さ(地面から)。壁・フェンス・杭はどれもこれより高い。
const RAY_HEIGHT := 0.3

var body: Player
var _dung_last_pos: Dictionary = {}   ## instance_id -> Vector3
var _dung_vel: Dictionary = {}        ## instance_id -> Vector3
var _tracked_t := 0


func _init(p_body: Player) -> void:
	body = p_body


## 毎物理フレーム呼ぶ。フンの速度推定を更新する。
func update(delta: float) -> void:
	_tracked_t += 1
	var seen := {}
	for d in dungs():
		var id := d.get_instance_id()
		seen[id] = true
		var pos := flat(d.global_position)
		if _dung_last_pos.has(id) and delta > 0.0:
			var raw: Vector3 = (pos - _dung_last_pos[id]) / delta
			var prev: Vector3 = _dung_vel.get(id, raw)
			_dung_vel[id] = prev.lerp(raw, 0.5)
		_dung_last_pos[id] = pos
	for id in _dung_last_pos.keys():
		if not seen.has(id):
			_dung_last_pos.erase(id)
			_dung_vel.erase(id)


## 自分以外の、試合中のプレイヤー(人間とCPUを区別しない)。
func opponents() -> Array[Player]:
	var out: Array[Player] = []
	for node in body.get_tree().get_nodes_in_group("player"):
		var p := node as Player
		if p != null and p != body and p.gameplay_active and not p.is_queued_for_deletion():
			out.append(p)
	return out


## 今1位(保有サイズ最大)のプレイヤー。自分を含む。
func leader() -> Player:
	var best: Player = body
	for p in opponents():
		if p.size > best.size:
			best = p
	return best


## 回収できる地面のフン(自分のスタン明け前のドロップは除く)。
func dungs() -> Array[DungPickup]:
	var out: Array[DungPickup] = []
	var container := body.get_tree().get_first_node_in_group("dung_container")
	if container == null:
		return out
	var now := Time.get_ticks_msec() / 1000.0
	for node in container.get_children():
		var d := node as DungPickup
		if d == null or d.is_queued_for_deletion() or d._collected:
			continue
		if d.owner_id == body.player_id and now < d.collectible_at:
			continue
		out.append(d)
	return out


func dung_velocity(d: DungPickup) -> Vector3:
	return _dung_vel.get(d.get_instance_id(), Vector3.ZERO)


## 拾ったときに増える量(DungPickup._on_body_entered と同じ式)。
static func dung_gain(d: DungPickup) -> float:
	return d.size * Config.balance.size_gain_per_pickup if d.owner_id < 0 else d.size


## from から dir へ distance までの壁(フェンス・杭含む)までの距離。無ければ INF。
func wall_distance(from: Vector3, dir: Vector3, distance: float) -> float:
	var hit := wall_hit(from, dir, distance)
	return INF if hit.is_empty() else flat(hit["position"]).distance_to(flat(from))


## from から dir へ distance までのレイの交点(intersect_ray の結果)。無ければ空。
func wall_hit(from: Vector3, dir: Vector3, distance: float) -> Dictionary:
	if not body.is_inside_tree() or dir.is_zero_approx():
		return {}
	var origin := Vector3(from.x, from.y if from.y > RAY_HEIGHT else RAY_HEIGHT, from.z)
	if not Stage.has_elevation():
		origin.y = RAY_HEIGHT
	var to := origin + Vector3(dir.x, 0.0, dir.z).normalized() * distance
	var query := PhysicsRayQueryParameters3D.create(origin, to, Player.WALL_LAYER)
	return body.get_world_3d().direct_space_state.intersect_ray(query)


## a から b まで、太さ radius の球が壁に当たらずに通れるか(中心と左右の3本のレイで近似)。
func clear_path(a: Vector3, b: Vector3, radius: float) -> bool:
	var d := flat(b) - flat(a)
	var length := d.length()
	if length < 0.01:
		return true
	var dir := d / length
	var side := Vector3(-dir.z, 0.0, dir.x) * radius * 0.9
	for offset in [Vector3.ZERO, side, -side]:
		if wall_distance(a + offset, dir, length) < length:
			return false
	return true


## 点 p から一番近い壁の方向(単位ベクトル)と距離。8方向のレイで調べる。{dir, distance}
func nearest_wall(p: Vector3, max_distance: float = 14.0) -> Dictionary:
	var best_dir := Vector3.ZERO
	var best_d := INF
	for i in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / 16.0)
		var d := wall_distance(p, dir, max_distance)
		if d < best_d:
			best_d = d
			best_dir = dir
	return {"dir": best_dir, "distance": best_d}


## 点を場内(外壁から margin 内側)に収める。
static func clamp_inside(p: Vector3, margin: float) -> Vector3:
	return Stage.clamp_to_arena(Vector3(p.x, 0.0, p.z), margin)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## 動く相手の先読み位置: 今の速度のまま time 秒進んだ位置(場内に収める)。
static func predict(p: Node3D, velocity: Vector3, time: float, margin: float = 0.5) -> Vector3:
	return clamp_inside(flat(p.global_position) + flat(velocity) * time, margin)
