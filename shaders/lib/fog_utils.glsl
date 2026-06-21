#ifndef FOG_UTILS_GLSL
#define FOG_UTILS_GLSL

const float FOG_UNIFORM_SCALE = 0.2;
const float FOG_CLUMPY_SCALE = 1.0;

float scaleFogSetting(float value, float factor){
	return value * factor;
}

#endif
