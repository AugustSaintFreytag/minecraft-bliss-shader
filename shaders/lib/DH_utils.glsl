// DH_utils.glsl

uniform float far;

float rand(float co) { return fract(sin(co*(91.3458)) * 47453.5453); }
float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }
float rand(vec3 co) { return rand(co.xy + rand(co.z)); }

vec3 quantize(const in vec3 val, const in int stepSize) {
	return floor(val * stepSize) / stepSize;
}

float luma(vec3 color) {
	return dot(color,vec3(0.299, 0.587, 0.114));
}

vec4 applyNoise(in vec4 fragColor, const in vec3 pos, const in float viewDist) {
	float noiseAmplification = NOISE_INTENSITY * 0.01;
	float lum = (fragColor.r + fragColor.g + fragColor.b) / 3.0;
	noiseAmplification = (1.0 - pow(lum * 2.0 - 1.0, 2.0)) * noiseAmplification; 
	noiseAmplification *= fragColor.a; 
	
	float highestSteps = NOISE_RESOLUTION;
	float lowestSteps = 2.0;
	float transitionLength = 16.0 * 16.0; 
	
	float transitionGradient = clamp((viewDist - (far+32.0)) / transitionLength, 0.0, 1.0);
	transitionGradient = sqrt(transitionGradient);

	int dynamicNoiseSteps = int(mix(highestSteps, lowestSteps, transitionGradient));

	float randomValue = rand(quantize(pos, dynamicNoiseSteps))
	* 2.0 * noiseAmplification - noiseAmplification;

	vec3 newCol = fragColor.rgb + (1.0 - fragColor.rgb) * randomValue;
	newCol = clamp(newCol, 0.0, 1.0);

	if (NOISE_DROPOFF != 0) {
		float distF = min(viewDist / NOISE_DROPOFF, 1.0);
		newCol = mix(newCol, fragColor.rgb, distF); 
	}

	return vec4(newCol, fragColor.a);
}
