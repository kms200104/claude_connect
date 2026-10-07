shader_type spatial;
// toon_world 과 같고, 카메라와 캐릭터 사이를 가리면 캐릭터 둘레를 점점이 비운다 (건물·나무 전용, toon_common 의 SEE_THROUGH).
render_mode diffuse_toon, specular_disabled;

#define SEE_THROUGH
#include "res://assets/shaders/include/toon_common.gdshaderinc"
