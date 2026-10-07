class_name AchievementInfo
extends RefCounted
## data/achievements/achievements.json 의 업적 하나 (v16). 이뤘는지는 서버가 정한다 (profile.ach).

var id: String = ""
## 같은 갈래 (단계가 오르는 한 줄).
var group: String = ""
var tier: int = 1
## 판정에 쓰는 값 이름 (profile.stats 의 키).
var stat: String = ""
var goal: int = 1
var display_name: String = ""
var description: String = ""
## 이루면 닉네임 옆에 달 수 있는 칭호.
var title: String = ""


static func from_dict(d: Dictionary) -> AchievementInfo:
	var a: AchievementInfo = AchievementInfo.new()
	a.id = str(d.get("id", ""))
	a.group = str(d.get("group", a.id))
	a.tier = int(d.get("tier", 1))
	a.stat = str(d.get("stat", ""))
	a.goal = maxi(1, int(d.get("goal", 1)))
	a.display_name = str(d.get("name", a.id))
	a.description = str(d.get("desc", ""))
	a.title = str(d.get("title", ""))
	return a
