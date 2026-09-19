class_name InputRouter
## 接続中の「認識済み(mapped)」joypadだけを接続順にプレイヤーへ割り当て、余りはキーボード。
## 幻のデバイス(is_joy_known=false)を除外して割り当てズレを防ぐ。
## 返り値: プレイヤーindex -> input_device
##   -1=キーボード矢印 / -2=WASD / 0..=joypadデバイスid / 9000+=待機(未割当)

static func known_pads() -> Array[int]:
	var pads: Array[int] = []
	for id in Input.get_connected_joypads():
		if Input.is_joy_known(id):
			pads.append(id)
	return pads

## プレイヤーindex -> {device:int, stick:int}
## 結合ペア(Joy-Con L/R)1台につき、左スティック(stick=0)と右スティック(stick=1)を別ソースにして
## 2人分に割り当てる。余りはキーボード。
static func sources(n: int) -> Array:
	var pads := known_pads()
	var srcs: Array = []
	for d in pads:
		srcs.append({"device": d, "stick": 0}) # 左スティック(Lジョイコン)
		srcs.append({"device": d, "stick": 1}) # 右スティック(Rジョイコン)
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
			out.append({"device": dev, "stick": 0})
	return out

static func devices(n: int) -> Array[int]:
	var out: Array[int] = []
	for s in sources(n):
		out.append(s["device"])
	return out

static func is_joypad(device: int) -> bool:
	return device >= 0 and device < 9000
