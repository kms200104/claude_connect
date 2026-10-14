class_name HunterApp
extends PhoneApp
## 헌터넷 (v0.28, 헌터 협회 공식 앱): 헌터 자격증 · 오늘의 현상금 의뢰(진행 막대 · "완료 보고") · 길드(만들기 · 가입 · 탈퇴, 길드원 등급)
## · 등급표. 판정은 서버 (Net.hunter_claim · guild_create · guild_join · guild_leave). 마석 매각 · 재심사는 출장소 창구에서.

const NAVY: Color = Color("#2A3A5A")
const GOLD: Color = Color("#C89A20")

var _tab: int = 0
var _name_edit: LineEdit = null
var _gate_states: Dictionary[String, String] = {}


func _ready() -> void:
	_build()
	Net.hunter_changed.connect(func() -> void: _build.call_deferred())
	Net.guild_changed.connect(func(_i: Dictionary) -> void: _build.call_deferred())
	Net.gate_changed.connect(func(id: String) -> void:
		# 남은 시간은 1초마다 오므로 열림 · 닫힘 · 상태가 바뀔 때만 다시 그린다.
		var st: String = str(Net.gates.get(id, {}).get("st", ""))
		if not _gate_states.has(id) or _gate_states[id] != st:
			_gate_states[id] = st
			_build.call_deferred())


func _build() -> void:
	clear()
	add_child(HunterWindow.license_card(false))
	tabs(PackedStringArray(["의뢰", "길드", "등급표"]), _tab, func(i: int) -> void:
		_tab = i
		_build())
	match _tab:
		0:
			_build_bounties()
		1:
			_build_guild()
		_:
			_build_ranks()


func _build_bounties() -> void:
	# 열린 게이트.
	for gid: String in Net.gates:
		var g: Dictionary = Net.gates[gid]
		var gc: VBoxContainer = card()
		gc.get_parent().name = "GateCard_%s" % gid
		var st: String = str(g["st"])
		var left: int = maxi(0, int(g["until"]) - Time.get_ticks_msec())
		var color: Color = WARN if st == "break" else GameData.hunter.gate_colors.get(str(g["rank"]), NAVY).darkened(0.2)
		gc.add_child(label("🌀 %s급 게이트 · %s" % [str(g["rank"]), str(g["name"])], 30, color))
		var mine: bool = GameData.hunter.can_enter(str(Net.hunter.get("rank", "E")), str(g["rank"]))
		var state_text: String = "던전 브레이크 중! 피하세요" if st == "break" else ("공략 중 · 웨이브 %d/%d" % [int(g["wave"]) + 1, int(g["waves"])] if st == "raid" else "브레이크까지 %d분 %d초" % [left / 60000, (left / 1000) % 60])
		gc.add_child(label("%s · %s" % [state_text, "진입 가능" if mine else "등급이 모자라요"], 22, SOFT))
	var list: Array = Net.hunter.get("bounties", [])
	if list.is_empty():
		add_child(label("오늘은 의뢰가 없어요.", 26, SOFT))
		return
	add_child(label("오늘의 현상금 의뢰 · 날마다 바뀌어요", 24, SOFT))
	for b: Variant in list:
		if not b is Dictionary:
			continue
		var bd: Dictionary = b
		var c: VBoxContainer = card()
		c.get_parent().name = "Bounty_%s" % str(bd.get("id", ""))
		var head: HBoxContainer = HBoxContainer.new()
		c.add_child(head)
		var t: Label = label(str(bd.get("name", "")), 30, INK, false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(label("%s · %d점" % [Money.short(int(bd.get("reward", 0))), int(bd.get("pts", 0))], 24, GOLD, false))
		c.add_child(label(str(bd.get("desc", "")), 22, SOFT))
		var got: int = int(bd.get("got", 0))
		var n: int = maxi(1, int(bd.get("n", 1)))
		c.add_child(meter(clampf(float(got) / float(n), 0.0, 1.0), NAVY))
		var row: HBoxContainer = HBoxContainer.new()
		c.add_child(row)
		var prog: Label = label("%d / %d" % [got, n], 24, INK, false)
		prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(prog)
		if bool(bd.get("done", false)):
			row.add_child(label("✔ 보고함", 24, GOOD, false))
		else:
			var claim: Button = button("완료 보고", 24, INK, got >= n)
			claim.name = "Claim_%s" % str(bd.get("id", ""))
			claim.disabled = got < n
			var bid: String = str(bd.get("id", ""))
			claim.pressed.connect(func() -> void:
				Audio.play_ui(Audio.SFX_CLICK)
				Net.hunter_claim(bid))
			row.add_child(claim)


func _build_guild() -> void:
	var rules: HunterRules = GameData.hunter
	if Net.guild.is_empty():
		var c: VBoxContainer = card()
		c.add_child(label("길드 만들기", 30, INK))
		c.add_child(label("같은 마을 친구와 둘이 길드를 만들어요. 함께 사냥하면(%dm 안) 처치 점수가 %d%% 더, 마석을 %d%% 더 받아요." % [roundi(rules.party_range), roundi((rules.party_mult - 1.0) * 100.0), roundi(rules.guild_sell_bonus * 100.0)], 22, SOFT))
		_name_edit = LineEdit.new()
		_name_edit.name = "GuildName"
		_name_edit.placeholder_text = "길드 이름 (%d~%d글자)" % [rules.guild_name_min, rules.guild_name_max]
		_name_edit.max_length = rules.guild_name_max
		_name_edit.custom_minimum_size = Vector2(0, 72)
		_name_edit.add_theme_font_size_override("font_size", 28)
		c.add_child(_name_edit)
		var make: Button = button("만들기", 28, INK, true)
		make.name = "GuildCreate"
		make.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.guild_create(_name_edit.text.strip_edges()))
		c.add_child(make)
		return
	var g: Dictionary = Net.guild
	var gc: VBoxContainer = card()
	gc.get_parent().name = "GuildCard"
	gc.add_child(label("⚔ %s" % str(g.get("name", "")), 34, INK))
	var nxt: int = int(g.get("next", 0))
	gc.add_child(label("%s (%d단계) · 길드 점수 %d%s" % [str(g.get("title", "")), int(g.get("level", 1)), int(g.get("pts", 0)), " / %d" % nxt if nxt > 0 else ""], 24, SOFT))
	if nxt > 0:
		gc.add_child(meter(clampf(float(g.get("pts", 0)) / float(nxt), 0.0, 1.0), GOLD))
	for m: Variant in g.get("members", []):
		if m is Dictionary:
			var r: HunterRules.Rank = rules.rank(str((m as Dictionary).get("rank", "E")))
			var who: int = int((m as Dictionary).get("id", 0))
			gc.add_child(label("%s급 · %s%s" % [r.id, GameData.player_name(who), " (나)" if who == Net.my_id else ""], 28, r.color.darkened(0.25)))
	if Net.in_guild():
		var leave: Button = button("길드 탈퇴", 24, WARN)
		leave.name = "GuildLeave"
		leave.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.guild_leave())
		gc.add_child(leave)
	elif (g.get("members", []) as Array).size() < 2:
		var join: Button = button("가입하기", 28, INK, true)
		join.name = "GuildJoin"
		join.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.guild_join())
		gc.add_child(join)


func _build_ranks() -> void:
	var rules: HunterRules = GameData.hunter
	var mine: String = str(Net.hunter.get("rank", "E"))
	add_child(label("점수가 기준을 넘으면 동사무소 옆 협회 출장소 창구에서 재심사를 받아요.", 22, SOFT))
	for r: HunterRules.Rank in rules.ranks:
		var c: VBoxContainer = card()
		var row: HBoxContainer = HBoxContainer.new()
		c.add_child(row)
		var t: Label = label("%s%s" % [r.name, "  ← 나" if r.id == mine else ""], 30, r.color.darkened(0.2), false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(label("%d점 · 마석 +%d%%" % [r.points, roundi(r.sell_bonus * 100.0)], 24, SOFT, false))
