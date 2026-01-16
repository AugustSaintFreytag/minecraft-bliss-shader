#ifndef FOG_UTILS_GLSL
#define FOG_UTILS_GLSL

const float FOG_UNIFORM_SCALE = 0.2;
const float FOG_CLUMPY_SCALE = 1.0;
const float FOG_CLUMPY_EDGE_SHARPNESS = 0.5;

float scaleFogSetting(float value, float factor){
	return value * factor;
}

float sharpenFogNoise(float noise){
	noise = clamp(noise, 0.0, 1.0);
	float sharper = smoothstep(0.45, 0.55, noise);
	return mix(noise, sharper, FOG_CLUMPY_EDGE_SHARPNESS);
}

#endif
