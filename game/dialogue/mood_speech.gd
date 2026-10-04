class_name MoodSpeech
extends RefCounted
## 기분에 따라 말투를 살짝 바꾼다. 대사 자체는 성격별 묶음(dialogue.json)에서 고르고, 여기서는 말끝·추임새·말버릇만 만진다.
##   happy   말끝이 늘어지고(~) 말버릇과 ♪ 가 붙는다      excited 느낌표가 늘고 "우와," 같은 추임새
##   sad     말끝이 흐려지고(…) "하아…" 한숨              grumpy  물결·음표가 빠지고 "흥," 으로 시작
##   sleepy  "(하암)" 하품과 "…zz"                        calm    가끔 말버릇만
## 같은 대사는 같은 모양으로 바뀐다 (대사 해시로 정한다) — 테스트·연출이 매번 흔들리지 않게.

const LABELS: Dictionary[String, String] = {
	"happy": "기분 좋음", "calm": "평온", "sad": "시무룩", "grumpy": "뾰로통", "sleepy": "졸림", "excited": "신남",
}
## 기분을 나타내는 감정표현 (대화창 이름 옆 작은 아이콘).
const ICONS: Dictionary[String, String] = {
	"happy": "happy", "calm": "", "sad": "sad", "grumpy": "angry", "sleepy": "sleepy", "excited": "surprise",
}


static func apply(line: String, mood: String, info: NpcInfo) -> String:
	if line.is_empty():
		return line
	var roll: float = float(absi(line.hash()) % 1000) / 1000.0
	var catchphrase: String = info.catchphrase if info != null else ""
	var out: String = line.strip_edges()
	match mood:
		"happy":
			out = _replace_end(out, ".", "~")
			if not catchphrase.is_empty() and roll < 0.6:
				out = "%s %s♪" % [out, catchphrase]
			elif roll < 0.85:
				out += " ♪"
		"excited":
			out = out.replace(".", "!").replace("~", "!")
			if not out.ends_with("!") and not out.ends_with("?"):
				out += "!"
			if roll < 0.4:
				out = "우와, " + out
			elif not catchphrase.is_empty() and roll < 0.7:
				out = "%s! %s" % [catchphrase, out]
		"sad":
			out = out.replace("!", "…").replace("~", "…").replace("♪", "")
			out = _replace_end(out, ".", "…")
			if not out.ends_with("…") and not out.ends_with("?"):
				out += "…"
			if roll < 0.4:
				out = "하아… " + out
		"grumpy":
			out = out.replace("~", ".").replace("♪", "").replace("!", ".")
			if roll < 0.45:
				out = ("흠. " if info != null and info.personality == "gruff" else "흥, ") + out
		"sleepy":
			out = out.replace("!", "…")
			if roll < 0.45:
				out = "(하암) " + out
			elif roll < 0.75:
				out = _replace_end(out, ".", "…") + " zz"
		_:
			if not catchphrase.is_empty() and roll < 0.25:
				out = "%s %s" % [out, catchphrase]
	return out


static func label(mood: String) -> String:
	return LABELS.get(mood, "")


static func _replace_end(text: String, from: String, to: String) -> String:
	return text.left(text.length() - from.length()) + to if text.ends_with(from) else text
