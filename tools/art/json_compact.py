"""JSON 을 사람이 읽기 좋게 쓴다: 들여쓰기 2칸, 단 숫자 · 짧은 글만 든 배열은 한 줄로 (좌표 목록이 한 줄에 한 값씩 길게 늘어지지 않게)."""
import json
import re

_INNER = re.compile(r"\[\s*((?:-?[0-9.eE+-]+|\"[^\"\n]{0,24}\"|true|false|null)(?:\s*,\s*(?:-?[0-9.eE+-]+|\"[^\"\n]{0,24}\"|true|false|null))*)\s*\]")


def dumps(doc) -> str:
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    text = _INNER.sub(lambda m: "[" + re.sub(r"\s*,\s*", ", ", m.group(1)) + "]", text)
    return text + "\n"
