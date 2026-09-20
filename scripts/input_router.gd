class_name InputRouter
## 接続中の「認識済み(mapped)」joypadだけを接続順にプレイヤーへ割り当て、余りはキーボード。
## 幻のデバイス(is_joy_known=false)を除外して割り当てズレを防ぐ。
## 返り値: プレイヤーindex -> input_device
##   -1=キーボード矢印 / -2=WASD / 0..=joypadデバイスid / 9000+=待機(未割当)

static func known_pads() -> Array[int]:
	var pads: Array[int] = []
	for id in Input.get_connected_joypads():
		if Input.is_joy_known(id) and not is_combined_joycon(id):
			pads.append(id)
	return pads

## SDL既定のL/R結合状態は1人単位の入力・振動に使えないため検出する。
static func is_combined_joycon(device: int) -> bool:
	return is_combined_joycon_name(Input.get_joy_name(device))

static func is_combined_joycon_name(device_name: String) -> bool:
	return "Joy-Con" in device_name and "(L/R)" in device_name

## プレイヤーindex -> {device:int}
## 横持ちのJoy-Conを個別デバイスとして扱い、1デバイスを1人だけに割り当てる。
## SDLのJoy-Con自動結合を起動前に無効化し、4人なら4デバイスを公開すること。
static func sources(n: int) -> Array:
	return sources_from_pads(n, known_pads())

## 実デバイス列挙と切り離した割当本体。headlessテストから疑似デバイス列で検証できる。
static func sources_from_pads(n: int, pads: Array[int]) -> Array:
	var srcs: Array = []
	for d in pads:
		srcs.append({"device": d})
	var out: Array = []
	var kb := 0
	for i in n:
		if i < srcs.size():
			out.append(srcs[i])
		else:
			var dev := 9000 + i
			match kb:
				0: dev = -1 # 矢印
				1: dev = -2 # WASD
			kb += 1
			out.append({"device": dev})
	return out

static func devices(n: int) -> Array[int]:
	var out: Array[int] = []
	for s in sources(n):
		out.append(s["device"])
	return out

static func is_joypad(device: int) -> bool:
	return device >= 0 and device < 9000
