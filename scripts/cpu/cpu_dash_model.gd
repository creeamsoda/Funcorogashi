class_name CpuDashModel
## 突進の到達距離の予測(CPU用)。Player と同じ BalanceConfig の式から、
## 「溜め時間 → 届く距離」と、その逆の「距離 → 必要な溜め時間」を求める。
## 曲げなし・壁や相手に当たらない場合の直進距離。減速区間は線形減速として積分する。


## 保有サイズ size で hold 秒溜めたときの溜め量(0..1)。
static func ratio_for_hold(hold: float, size: float) -> float:
	var b := Config.balance
	return b.dash_charge_ratio(maxf(hold, b.dash_charge_min), b.charge_time_scale(size))


static func speed_for_ratio(ratio: float) -> float:
	var b := Config.balance
	return lerpf(b.dash_speed_min, b.dash_speed_max, ratio)


static func duration_for_ratio(ratio: float) -> float:
	var b := Config.balance
	return lerpf(b.dash_duration_min, b.dash_duration_max, ratio)


## 溜め量 ratio の突進が止まるまでに進む距離。
static func reach_for_ratio(ratio: float) -> float:
	var v := speed_for_ratio(ratio)
	return v * (duration_for_ratio(ratio) + maxf(Config.balance.dash_end_decel_time, 0.0) * 0.5)


## hold 秒溜めて離したときに届く距離。
static func reach_for_hold(hold: float, size: float) -> float:
	return reach_for_ratio(ratio_for_hold(hold, size))


## 最大まで溜める時間(秒)。保有サイズで延びる。
static func full_hold_time(size: float) -> float:
	var b := Config.balance
	return maxf(b.dash_charge_time * b.charge_time_scale(size), b.dash_charge_min)


static func min_reach(size: float) -> float:
	return reach_for_hold(Config.balance.dash_charge_min, size)


static func max_reach(size: float) -> float:
	return reach_for_hold(full_hold_time(size), size)


## distance 届くのに必要な最短の溜め時間。最大溜めでも届かなければ最大溜めの時間。
static func hold_for_reach(distance: float, size: float) -> float:
	var lo := Config.balance.dash_charge_min
	var hi := full_hold_time(size)
	if reach_for_hold(lo, size) >= distance:
		return lo
	if reach_for_hold(hi, size) <= distance:
		return hi
	for _i in 24: # 届く距離は溜め時間に対して単調増加なので二分探索
		var mid := (lo + hi) * 0.5
		if reach_for_hold(mid, size) < distance:
			lo = mid
		else:
			hi = mid
	return hi


## 保有サイズ size のときの突進加速の時間(この間は相手に当ててもドロップさせられない)。
static func accel_time(size: float) -> float:
	var b := Config.balance
	return maxf(b.dash_accel_time, 0.0) * b.accel_time_scale(size)


## 溜め量 ratio の突進で、離してから distance 進むまでの時間。届かなければ INF。
static func time_to_travel(distance: float, ratio: float) -> float:
	var v := speed_for_ratio(ratio)
	var dur := duration_for_ratio(ratio)
	var decel := maxf(Config.balance.dash_end_decel_time, 0.001)
	if distance <= v * dur:
		return distance / maxf(v, 0.001)
	# 減速区間: 速度 v(1 - s/decel) を積分した距離 v(s - s²/(2decel)) = distance - v*dur を s について解く
	var rest := distance - v * dur
	var max_rest := v * decel * 0.5
	if rest > max_rest:
		return INF
	var disc := maxf(1.0 - 2.0 * rest / (v * decel), 0.0)
	return dur + decel * (1.0 - sqrt(disc))
