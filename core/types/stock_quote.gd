class_name StockQuote
extends RefCounted
## 증권 종목 하나의 지금 상태 (서버 market.wire / market_tick).

var id: String = ""
var display_name: String = ""
var sector: String = ""
var about: String = ""
var price: int = 0
## 오늘 기준가 (어제 마지막 가격). 등락률의 기준.
var ref: int = 0
## 최근 분 단위 가격 (오래된 것부터).
var hist: PackedInt64Array = []


func change_rate() -> float:
	return float(price - ref) / float(ref) if ref > 0 else 0.0
