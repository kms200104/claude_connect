// 닉네임 (v14). 거울 창이나 처음 화면 설정에서 정한다. 빈 이름이면 기본 이름("플레이어 N" 같은 것)을 쓴다.
// 글자 · 숫자 · 띄어쓰기 · _ - . 만, 앞뒤 공백을 지우고 띄어쓰기는 한 칸으로, 최대 NAME_MAX 글자.

export const NAME_MAX = 10;

/** 받은 이름을 정리한다. 쓸 수 없는 이름이면 null, 지우기(빈 이름)면 ''. */
export function cleanName(raw) {
  if (typeof raw !== 'string') return null;
  const text = raw.normalize('NFC').replace(/\s+/gu, ' ').trim();
  if (text === '') return '';
  if ([...text].length > NAME_MAX) return null;
  if (!/^[\p{L}\p{N}\p{M} _.\-]+$/u.test(text)) return null;
  return text;
}

/** 저장 파일에서 읽은 이름 (이상하면 빈 이름). */
export function sanitizeName(raw) {
  return cleanName(raw) ?? '';
}
