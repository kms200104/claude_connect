#!/usr/bin/env python3
"""게임 글꼴(주아 + 고운돋움 기호)에 없는 글자를 채우는 예비 글꼴 셋을 만든다 → assets/fonts/.

  emoji_subset.ttf    Noto Color Emoji 의 SVG 그림(OT-SVG)만 남긴 부분집합 — Godot 가 컬러로 그린다.
                      (구글 폰트판은 COLRv1 + SVG 인데 Godot 는 COLRv1 을 못 그려서 COLR/CPAL 을 뺀다.)
  symbols_subset.ttf  Noto Sans Symbols 2 의 기호 (✓ ✕ ✎ …)
  cjk_marks.ttf       Noto Sans KR 에서 그 밖의 글자 (낫표 「」 · ± …)

담는 글자: 프로젝트 글(.gd .json .js .tscn)에서 기본 글꼴에 없는 글자를 모두 찾고, 마을톡에서 많이 쓰는 이모지(CHAT_EMOJI)를 더한다.
글을 새로 쓰다 이모지 · 기호를 더하면 이 도구를 다시 돌린다:  python3 tools/fonts/build_extra_fonts.py
원본은 구글 폰트 CDN 에서 받아 ~/.cache/solbaram_fonts 에 둔다. 모두 SIL OFL 1.1 (assets/fonts/LICENSE.txt).
필요: pip install fonttools lxml
"""
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/fonts'
CACHE = Path.home() / '.cache/solbaram_fonts'
BASE_FONTS = [OUT / 'jua_regular.ttf', OUT / 'gowun_dodum_symbols.ttf']
FAMILIES = {'emoji': 'Noto Color Emoji', 'symbols': 'Noto Sans Symbols 2', 'cjk': 'Noto Sans KR'}

# 마을톡에서 자주 쓰는 이모지 (휴대폰 글자판으로 칠 수 있으니 미리 담아 둔다).
CHAT_EMOJI = (
    '😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓'
    '🤗🤔🫣🤭🫢🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👻💀👽🤖💩😺😸😹😻😼😽🙀😿😾'
    '👍👎👏🙌👐🤲🤝🙏✌🤞🫶🤟🤘👌🤌👈👉👆👇☝✋🤚🖐🖖👋🤙💪✍'
    '❤🧡💛💚💙💜🤍🖤🤎💔❣💕💞💓💗💖💘💝💟💌💋'
    '✨⭐🌟💫🔥💯💢💥💦💨💤🎉🎊🎁🎂🎈🎀🎪🎵🎶🎤🎧🎮🎨📷📸📦🛵🚲🚗✈⛵🏠🏡🏪🏛⛪🌊🏝🏖'
    '🌸🌷🌹🌺🌻🌼💐🍀🌿🌱🌲🌳🌴🍂🍁🍄🌈☀🌤⛅🌥☁🌦🌧⛈🌩❄☃⛄🌙🌛🌝🌞⭐🌠'
    '🐟🐠🐡🦈🐙🦀🦐🐚🎣🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🐤🐥🦆🦉🦋🐝🐞🐌🐢'
    '🍎🍏🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🥕🌽🥔🍠🥐🍞🧀🥚🍳🥞🍔🍟🍕🌭🥪🌮🍝🍜🍲🍛🍣🍱🍙🍚🍘🍢🍡🍧🍨🍦🥧🧁🍰🍮🍭🍬🍫🍿🍩🍪☕🍵🧃🥤🍶🍺'
    '💰💸💵💴🪙💳🏆🥇🥈🥉🏅🎖📅📆📍🗺🧭⏰⌛💡📱📞✉📮📝✏🔑🎒👒🎩👑👗👕👖🧣🧤🧦👟'
    '✅❌⭕❗❓❕❔⚠🚫💬💭🗨🔔🎵'
)
# 기본 글꼴에 없어도 그대로 두는 글자 (서식 · 보이지 않는 글자).
IGNORE = {'‍', '️', '︎', '​', '﻿'}


def code_points(font_path):
    return set(TTFont(font_path).getBestCmap())


def project_text():
    files = subprocess.check_output(['git', 'ls-files', '*.gd', '*.json', '*.js', '*.tscn'], cwd=ROOT, text=True).split()
    text = []
    for f in files:
        if 'node_modules' in f or f.startswith('tools/fonts/'):
            continue
        try:
            text.append((ROOT / f).read_text(encoding='utf-8'))
        except (UnicodeDecodeError, FileNotFoundError):
            pass
    return '\n'.join(text)


def fetch(family):
    """구글 폰트 CSS API 에서 그 글꼴의 ttf 주소를 찾아 받아 둔다."""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / (family.replace(' ', '') + '.ttf')
    if path.exists() and path.stat().st_size > 10000:
        return path
    css_url = 'https://fonts.googleapis.com/css2?family=' + family.replace(' ', '+')
    css = urllib.request.urlopen(urllib.request.Request(css_url, headers={'User-Agent': 'Mozilla/5.0'})).read().decode()
    url = re.search(r'url\((https://[^)]+\.ttf)\)', css).group(1)
    print(f'[fonts] 받기 {family}: {url}')
    path.write_bytes(urllib.request.urlopen(url).read())
    return path


def build(src, out, chars, drop=()):
    opts = subset.Options()
    opts.drop_tables += list(drop)
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.notdef_outline = False
    font = TTFont(src)
    cmap = font.getBestCmap()
    have = ''.join(c for c in chars if ord(c) in cmap)
    # 이모지 다음에 오는 변형 선택자(FE0F)도 함께 (❤️ 처럼 붙여 쓴 글자).
    sub = subset.Subsetter(opts)
    sub.populate(text=have + '️')
    sub.subset(font)
    font.save(out)
    print(f'[fonts] {out.relative_to(ROOT)}: {len(have)}자 · {out.stat().st_size // 1024}KB')
    return set(have)


def main():
    base = set()
    for f in BASE_FONTS:
        base |= code_points(f)
    used = {c for c in project_text() if ord(c) > 127 and ord(c) not in base and c not in IGNORE and not ('가' <= c <= '힣')}
    wanted = used | set(CHAT_EMOJI) - IGNORE
    emoji_src = fetch(FAMILIES['emoji'])
    got = build(emoji_src, OUT / 'emoji_subset.ttf', sorted(wanted), drop=('COLR', 'CPAL'))
    rest = wanted - got
    got |= build(fetch(FAMILIES['symbols']), OUT / 'symbols_subset.ttf', sorted(rest))
    rest = wanted - got
    got |= build(fetch(FAMILIES['cjk']), OUT / 'cjk_marks.ttf', sorted(rest))
    missing = sorted(c for c in used if c not in got)
    if missing:
        print('[fonts] 아직 어느 글꼴에도 없는 글자:', ' '.join(f'{c}(U+{ord(c):04X})' for c in missing))
    return 0


if __name__ == '__main__':
    sys.exit(main())
