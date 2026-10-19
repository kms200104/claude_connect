class_name HunterApp
extends PhoneApp
## 헌터넷 (v0.28, 헌터 협회 공식 앱): 헌터 자격증 · 오늘의 현상금 의뢰(진행 막대 · "완료 보고") · 길드(만들기 · 가입 · 탈퇴, 길드원 등급)
## · 등급표 · v0.28.1 능력치(레벨 · 경험치 · 스탯 포인트 쓰기 · 기술). 판정은 서버 (Net.hunter_claim · guild_create · guild_join · guild_leave). 마석 매각 · 재심사는 출장소 창구에서.

const NAVY: Color = Color("#2A3A5A")
const GOLD: Color = Color("#C89A20")

var _tab: int = 0
var _name_edit: LineEdit = null
var _gate_states: Dictionary[String, String] = {}
## v0.28.8 전직 탭에서 고른 기술 (설명 · 배우기) · 전직 전에 살펴보는 직업.
var _node: String = ""
var _peek_job: String = ""


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
	tabs(PackedStringArray(["능력치", "전직", "의뢰", "길드", "등급표"]), _tab, func(i: int) -> void:
		_tab = i
		_build())
	match _tab:
		0:
			_build_stats()
		1:
			_build_job()
		2:
			_build_bounties()
		3:
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
	_build_missions()
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


## v0.28.17 협회 임무 (매일 · 매주): 진행 막대 · 다 채우면 '받기' → 헌터 마일리지.
func _build_missions() -> void:
	var ms: Dictionary = Net.hunter.get("missions", {}) if Net.hunter.get("missions") is Dictionary else {}
	for part: Array in [["daily", "오늘의 협회 임무 · 날마다 새로"], ["weekly", "이번 주 협회 임무 · 월요일에 새로"]]:
		var list: Array = ms.get(str(part[0]), []) if ms.get(str(part[0])) is Array else []
		if list.is_empty():
			continue
		add_child(label(str(part[1]), 24, SOFT))
		var c: VBoxContainer = card()
		c.get_parent().name = "Missions_%s" % str(part[0])
		for m: Variant in list:
			if not m is Dictionary:
				continue
			var md: Dictionary = m
			var mid: String = str(md.get("id", ""))
			var got: int = int(md.get("got", 0))
			var n: int = maxi(1, int(md.get("n", 1)))
			var row: HBoxContainer = HBoxContainer.new()
			row.name = "Mission_%s" % mid
			row.add_theme_constant_override("separation", 10)
			c.add_child(row)
			var t: Label = label("%s · %d/%d" % [str(md.get("name", "")), got, n], 24, INK, false)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			if bool(md.get("done", false)):
				row.add_child(label("✔ 받음", 22, GOOD, false))
			else:
				var claim: Button = button("+%d M" % int(md.get("mi", 0)), 22, INK, got >= n)
				claim.name = "MissionClaim_%s" % mid
				claim.disabled = got < n
				claim.pressed.connect(func() -> void:
					Audio.play_ui(Audio.SFX_CLICK)
					Net.mission_claim(mid))
				row.add_child(claim)
			c.add_child(meter(clampf(float(got) / float(n), 0.0, 1.0), GOLD if got >= n else NAVY))


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
	add_child(label("점수가 기준을 넘으면 동사무소 앞 협회 출장소 창구에서 재심사를 받아요.", 22, SOFT))
	for r: HunterRules.Rank in rules.ranks:
		var c: VBoxContainer = card()
		var row: HBoxContainer = HBoxContainer.new()
		c.add_child(row)
		var t: Label = label("%s%s" % [r.name, "  ← 나" if r.id == mine else ""], 30, r.color.darkened(0.2), false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(label("%d점 · 마석 +%d%%" % [r.points, roundi(r.sell_bonus * 100.0)], 24, SOFT, false))


# ---- v0.28.1 능력치 ----

const STAT_ORDER: PackedStringArray = ["str", "vit", "agi", "luk"]


## 스탯 정의의 값 하나 (예: agi · speed), 없으면 0.
static func stat_value(stat: String, field: String) -> float:
	return float((GameData.hunter.level_stats.get(stat, {}) as Dictionary).get(field, 0.0))


## 기술의 늘어나는 사거리 (m).
static func skill_reach(skill_id: String) -> float:
	for sk: Dictionary in GameData.hunter.skills:
		if str(sk.get("id", "")) == skill_id:
			return float(sk.get("reach", 0.0))
	return 0.0


func _build_stats() -> void:
	var h: Dictionary = Net.hunter
	var lv: int = int(h.get("lv", 1))
	var xp: int = int(h.get("xp", 0))
	var nxt: int = int(h.get("xpNext", 0))
	var sp: int = int(h.get("sp", 0))
	var st: Dictionary = h.get("st", {}) if h.get("st") is Dictionary else {}
	var c: VBoxContainer = card()
	c.get_parent().name = "LevelCard"
	c.add_child(label("Lv.%d%s" % [lv, " (최고)" if nxt <= 0 else ""], 40, NAVY))
	if nxt > 0:
		c.add_child(meter(clampf(float(xp) / float(nxt), 0.0, 1.0), GOLD))
		c.add_child(label("경험치 %d / %d — 크리처 처치 · 게이트 · 의뢰 · 빈집 뒤지기 · 보급 상자" % [xp, nxt], 22, SOFT))
	var pts: Label = label("남은 스탯 포인트 %d" % sp if sp > 0 else "레벨이 오르면 스탯 포인트 3을 받아요", 26, WARN if sp > 0 else SOFT)
	pts.name = "StatPoints"
	c.add_child(pts)
	for key: String in STAT_ORDER:
		var def: Dictionary = GameData.hunter.level_stats.get(key, {})
		if def.is_empty():
			continue
		var v: int = int(st.get(key, 0))
		var cap: int = int(def.get("cap", 99))
		var row_card: VBoxContainer = card()
		row_card.get_parent().name = "Stat_%s" % key
		var row: HBoxContainer = HBoxContainer.new()
		row_card.add_child(row)
		var name_label: Label = label("%s  %d" % [str(def.get("name", key)), v], 32, INK, false)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var plus: Button = button("＋", 32, INK, sp > 0 and v < cap)
		plus.name = "StatUp_%s" % key
		plus.custom_minimum_size = Vector2(96, 72)
		plus.disabled = sp <= 0 or v >= cap
		plus.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.stat_up(key))
		row.add_child(plus)
		row_card.add_child(label("%s · 지금 %s%s" % [str(def.get("desc", "")), _stat_effect(key, v), " (최대)" if v >= cap else ""], 22, SOFT))
	# v0.28.5 각성: 레벨 5 · 10 · 15 마다 하나 고른다 (바꿀 수 없다).
	var rules: HunterRules = GameData.hunter
	var picked: Array = h.get("aw", [])
	var slots: int = int(h.get("awSlots", 0))
	add_child(label("각성 %d / %d%s" % [picked.size(), rules.awaken_slots.size(), " — 고를 수 있어요!" if picked.size() < slots else ""], 30, WARN if picked.size() < slots else INK))
	var next_lv: int = 0
	for l: int in rules.awaken_slots:
		if l > lv:
			next_lv = l
			break
	if picked.size() >= slots and next_lv > 0:
		add_child(label("다음 각성은 Lv.%d 에" % next_lv, 22, SOFT))
	for e: Dictionary in rules.awakens:
		var aid: String = str(e.get("id", ""))
		var have: bool = picked.has(aid)
		var ac: VBoxContainer = card()
		ac.get_parent().name = "Awaken_%s" % aid
		var arow: HBoxContainer = HBoxContainer.new()
		ac.add_child(arow)
		var an: Label = label("%s %s%s" % ["✔" if have else "◇", str(e.get("name", aid)), " (늘 켜짐)" if not bool(e.get("active", false)) else ""], 30, GOOD if have else INK, false)
		an.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arow.add_child(an)
		if not have:
			var pick: Button = button("각성", 28, INK, picked.size() < slots)
			pick.name = "AwakenPick_%s" % aid
			pick.custom_minimum_size = Vector2(130, 68)
			pick.disabled = picked.size() >= slots
			pick.pressed.connect(func() -> void:
				Audio.play_ui(Audio.SFX_CLICK)
				Net.awaken_pick(aid))
			arow.add_child(pick)
		ac.add_child(label(str(e.get("desc", "")), 22, SOFT))
	add_child(label("기술", 30, INK))
	for sk: Dictionary in GameData.hunter.skills:
		var learned: bool = Net.has_skill(str(sk.get("id", "")))
		var kc: VBoxContainer = card()
		kc.get_parent().name = "Skill_%s" % str(sk.get("id", ""))
		kc.add_child(label("%s %s · Lv.%d" % ["✔" if learned else "🔒", str(sk.get("name", "")), int(sk.get("level", 1))], 28, GOOD if learned else SOFT))
		kc.add_child(label(str(sk.get("desc", "")), 22, SOFT))


# ---- v0.28.8 전직 · 기술 나무 ----

func _build_job() -> void:
	var rules: HunterRules = GameData.hunter
	var lv: int = int(Net.hunter.get("lv", 1))
	var job: String = Net.job_id()
	if job.is_empty():
		_build_job_pick(rules, lv)
		return
	var def: Dictionary = rules.job(job)
	var jc: Color = Color(str(def.get("color", "#E0603A")))
	var learned: Dictionary = Net.job_learned()
	var jp: int = int(Net.hunter.get("jp", 0))
	var head: VBoxContainer = card()
	head.get_parent().name = "JobCard"
	var title: String = str((def.get("advance", {}) as Dictionary).get("name", def.get("name", job))) if Net.is_advanced() else str(def.get("name", job))
	head.add_child(label("%s · Lv.%d" % [title, lv], 40, jc))
	var pts: Label = label("남은 기술 포인트 %d" % jp if jp > 0 else "레벨이 오를 때마다 기술 포인트 %d" % rules.job_per_level, 26, WARN if jp > 0 else SOFT)
	pts.name = "SkillPoints"
	head.add_child(pts)
	head.add_child(label("줄을 내려갈수록 이 나무에 포인트를 %d씩 더 써야 해요. 마름모는 액티브 기술 (HUD 둥근 단추)." % rules.job_row_gate, 22, SOFT))
	# v0.28.9 2차 전직 (Lv.30): 직업마다 하나, 포인트를 더 받고 5 · 6줄이 열린다.
	var adv: Dictionary = def.get("advance", {})
	if not adv.is_empty():
		var ac: Color = Color(str(adv.get("color", "#C8302A")))
		if Net.is_advanced():
			head.add_child(label("2차 전직 · %s" % str(adv.get("name", "")), 30, ac))
		else:
			var card_adv: VBoxContainer = card()
			card_adv.get_parent().name = "AdvanceCard"
			var arow: HBoxContainer = HBoxContainer.new()
			card_adv.add_child(arow)
			var an: Label = label("2차 전직 — %s" % str(adv.get("name", "")), 30, ac, false)
			an.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			arow.add_child(an)
			var ready: bool = lv >= rules.job_advance_level
			var go: Button = button("전직", 28, INK, ready)
			go.name = "Advance"
			go.custom_minimum_size = Vector2(130, 64)
			go.disabled = not ready
			go.pressed.connect(func() -> void:
				Audio.play_ui(Audio.SFX_CLICK)
				Net.class_advance())
			arow.add_child(go)
			card_adv.add_child(label("%s%s" % [str(adv.get("desc", "")), "" if ready else " (Lv.%d 부터)" % rules.job_advance_level], 22, SOFT))
	var tree: SkillTreeView = SkillTreeView.new()
	tree.name = "SkillTree"
	tree.setup(job, learned, jp, _node, view_width() - 40.0, Net.is_advanced())
	tree.picked.connect(func(id: String) -> void:
		_node = id
		_build())
	add_child(tree)
	if not _node.is_empty() and not rules.job_node(job, _node).is_empty():
		var n: Dictionary = rules.job_node(job, _node)
		var rank: int = int(learned.get(_node, 0))
		var dc: VBoxContainer = card()
		dc.get_parent().name = "NodeCard"
		var row: HBoxContainer = HBoxContainer.new()
		dc.add_child(row)
		var nl: Label = label("%s  %d/%d" % [str(n.get("name", _node)), rank, int(n.get("max", 1))], 32, INK, false)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var block: String = rules.job_node_block(job, learned, jp, _node, Net.is_advanced())
		var learn: Button = button("배우기", 28, INK, block.is_empty())
		learn.name = "SkillUp"
		learn.custom_minimum_size = Vector2(150, 72)
		learn.disabled = not block.is_empty()
		var nid: String = _node
		learn.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.skill_up(nid))
		row.add_child(learn)
		dc.add_child(label(str(n.get("desc", "")), 24, INK))
		var act: String = str(n.get("active", ""))
		if not act.is_empty():
			var ad: Dictionary = rules.job_actives.get(act, {})
			dc.add_child(label("다시 쓰기까지 %d초" % roundi(float(ad.get("cooldown_ms", 0)) / 1000.0), 22, SOFT))
		if not block.is_empty():
			dc.add_child(label(block, 22, WARN if rank == 0 else SOFT))
	else:
		add_child(label("기술을 누르면 설명이 나와요.", 22, SOFT))
	var spent: int = 0
	for id: Variant in learned:
		spent += int(learned[id])
	if spent > 0:
		var reset: Button = button("기술 초기화 (%s — 포인트를 돌려받아요, 직업은 그대로)" % Money.sol(rules.job_reset_sol), 24, INK)
		reset.name = "SkillReset"
		reset.disabled = Net.sol < rules.job_reset_sol
		reset.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			_node = ""
			Net.skill_reset())
		add_child(reset)


func _build_job_pick(rules: HunterRules, lv: int) -> void:
	var ready: bool = lv >= rules.job_level
	add_child(label("전직 %s" % ("— 직업 하나를 고르세요 (바꿀 수 없어요)" if ready else "은 Lv.%d 부터 (지금 Lv.%d)" % [rules.job_level, lv]), 30, WARN if ready else INK))
	add_child(label("전직하면 Lv.%d 부터 레벨마다 기술 포인트 %d을 받아 기술 나무를 키워요 (지난 레벨 몫까지)." % [rules.job_level, rules.job_per_level], 22, SOFT))
	for e: Dictionary in rules.jobs:
		var jid: String = str(e.get("id", ""))
		var jc: Color = Color(str(e.get("color", "#E0603A")))
		var c: VBoxContainer = card()
		c.get_parent().name = "Job_%s" % jid
		var row: HBoxContainer = HBoxContainer.new()
		c.add_child(row)
		var nl: Label = label(str(e.get("name", jid)), 36, jc, false)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		var look: Button = button("나무 보기" if _peek_job != jid else "접기", 24, INK, _peek_job == jid)
		look.custom_minimum_size = Vector2(140, 64)
		look.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			_peek_job = "" if _peek_job == jid else jid
			_build())
		row.add_child(look)
		var pick: Button = button("전직", 28, INK, ready)
		pick.name = "JobPick_%s" % jid
		pick.custom_minimum_size = Vector2(130, 64)
		pick.disabled = not ready
		pick.pressed.connect(func() -> void:
			Audio.play_ui(Audio.SFX_CLICK)
			Net.class_pick(jid))
		row.add_child(pick)
		c.add_child(label(str(e.get("desc", "")), 22, SOFT))
		if _peek_job == jid:
			for n: Variant in e.get("tree", []):
				var node: Dictionary = n
				c.add_child(label("%s %s (최대 %d) — %s" % ["◆" if not str(node.get("active", "")).is_empty() else "●", str(node.get("name", "")), int(node.get("max", 1)), str(node.get("desc", ""))], 22, INK))


## 스탯 값이 주는 효과 글자.
func _stat_effect(key: String, v: int) -> String:
	match key:
		"str":
			return "피해 +%d%%" % roundi(v * stat_value("str", "damage") * 100.0)
		"vit":
			return "최대 체력 +%d" % floori(v * stat_value("vit", "hp_per"))
		"agi":
			return "이동 +%d%% · 공격 간격 -%d%%" % [roundi(v * stat_value("agi", "speed") * 100.0), roundi(v * stat_value("agi", "cooldown") * 100.0)]
		"luk":
			return "마석 확률 +%d%%" % roundi(v * stat_value("luk", "mana") * 100.0)
	return ""
