class_name Money
extends RefCounted
## 솔(화폐) 표시. 1솔 ≈ 1원 (v0.8 부터 현실 단위). 큰 돈은 만·억 단위로 줄여 읽기 쉽게.


## 세 자리마다 쉼표: 1234567 → "1,234,567"
static func digits(n: int) -> String:
	var negative: bool = n < 0
	var s: String = str(absi(n))
	var out: String = ""
	for i: int in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if negative else "") + out


## "12,345솔"
static func sol(n: int) -> String:
	return "%s솔" % digits(n)


## 큰 돈을 만·억으로: 350000000 → "3억 5,000만솔", 125000 → "12만 5,000솔", 9800 → "9,800솔".
static func short(n: int) -> String:
	var negative: bool = n < 0
	var v: int = absi(n)
	var eok: int = v / 100000000
	var man: int = (v % 100000000) / 10000
	var rest: int = v % 10000
	var parts: PackedStringArray = []
	if eok > 0:
		parts.append("%s억" % digits(eok))
	if man > 0:
		parts.append("%s만" % digits(man))
	if rest > 0 and eok == 0:
		parts.append(digits(rest))
	if parts.is_empty():
		parts.append("0")
	return ("-" if negative else "") + " ".join(parts) + "솔"


## 부호 붙인 변화량: "+1,200솔" / "-3억솔"
static func delta(n: int) -> String:
	return ("+" if n > 0 else "") + (short(n) if absi(n) >= 100000 else sol(n))


## 퍼센트: 0.0412 → "4.12%"
static func percent(rate: float, places: int = 2) -> String:
	return ("%." + str(places) + "f%%") % (rate * 100.0)
