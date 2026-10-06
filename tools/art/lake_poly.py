"""호수 윤곽(다각형) 공용 계산: 안팎 판정과 부호 있는 거리 (안쪽 음수, 미터). numpy 만 쓴다.
서버(server/src/gamedata.js)·클라이언트(core/types/spot_info.gd)의 식과 같아야 한다."""
import numpy as np


def signed_distance(outline: np.ndarray, px: np.ndarray, pz: np.ndarray) -> np.ndarray:
    """outline: (N,2) [x,z] 닫힌 다각형(마지막→처음 변 포함). 안쪽이면 음수."""
    n = len(outline)
    best = np.full(px.shape, 1e9)
    inside = np.zeros(px.shape, dtype=bool)
    for i in range(n):
        ax, az = outline[i]
        bx, bz = outline[(i + 1) % n]
        dx, dz = bx - ax, bz - az
        t = np.clip(((px - ax) * dx + (pz - az) * dz) / max(dx * dx + dz * dz, 1e-9), 0.0, 1.0)
        best = np.minimum(best, np.hypot(px - (ax + t * dx), pz - (az + t * dz)))
        crosses = ((az > pz) != (bz > pz)) & (px < (bx - ax) * (pz - az) / (bz - az + 1e-12) + ax)
        inside ^= crosses
    return np.where(inside, -best, best)
