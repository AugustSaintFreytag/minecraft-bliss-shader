#define ANTIALIASING_RELATED_SETTINGS
#define EMISSION_RELATED_SETTINGS
#include "/lib/settings.glsl"

varying vec4 pos;
varying vec4 gcolor;

uniform vec2 texelSize;
uniform vec3 cameraPosition;
uniform sampler2D depthtex1;

uniform mat4 gbufferModelViewInverse;
uniform float far;
uniform int frameCounter;

flat varying vec3 averageSkyCol_Clouds;

// Utility

vec3 toLinear(vec3 sRGB){
	return sRGB * (sRGB * (sRGB * 0.305306011 + 0.682171111) + 0.012522878);
}

float luma(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 quantize(const in vec3 val, const in int stepSize) {
	return floor(val * stepSize) / stepSize;
}

// Utility (Noise)

float interleaved_gradientNoise_temporal(){
	#if TAA_MODE > 0
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887 * frameCounter);
	#else
		return fract(52.9829189*fract(0.06711056*gl_FragCoord.x + 0.00583715*gl_FragCoord.y ) + 1.0/1.6180339887);
	#endif
}

float rand(float co) { return fract(sin(co*(91.3458)) * 47453.5453); }
float rand(vec2 co) { return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453); }
float rand(vec3 co) { return rand(co.xy + rand(co.z)); }

// Noise

const float noiseIntensity = NOISE_INTENSITY;
const int noiseDropoff = NOISE_DROPOFF;

vec4 applyNoise(in vec4 fragColor, const in vec3 viewPos, const in float viewDist) {
	float noiseAmplification = noiseIntensity * 0.01;
	float lum = (fragColor.r + fragColor.g + fragColor.b) / 3.0;
	noiseAmplification = (1.0 - pow(lum * 2.0 - 1.0, 2.0)) * noiseAmplification; 
	noiseAmplification *= fragColor.a; 
	
	float highestSteps = NOISE_RESOLUTION;
	float lowestSteps = 2.0;
	float transitionLength = 16.0 * 16.0; 
	
	float transitionGradient = clamp((viewDist - (far+32.0)) / transitionLength,0.0,1.0);
	transitionGradient = sqrt(transitionGradient);

	int dynamicNoiseSteps = int(mix(highestSteps, lowestSteps, transitionGradient));

	float randomValue = rand(quantize(viewPos, dynamicNoiseSteps))
	* 2.0 * noiseAmplification - noiseAmplification;

	vec3 newCol = fragColor.rgb + (1.0 - fragColor.rgb) * randomValue;
	newCol = clamp(newCol, 0.0, 1.0);

	if (noiseDropoff != 0) {
		float distF = min(viewDist / noiseDropoff, 1.0);
		newCol = mix(newCol, fragColor.rgb, distF); 
	}

	return vec4(newCol, fragColor.a);
}

// Main

/* RENDERTARGETS:2 */
void main() {
	if (gl_FragCoord.x * texelSize.x < 1.0 && gl_FragCoord.y * texelSize.y < 1.0 )	{
		vec3 viewPos = pos.xyz;
		vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
		float falloff = exp(-10.0 * (1.0-clamp(1.0 - playerPos.y/5000.0,0.0,1.0)));

		#ifdef DH_OVERDRAW_PREVENTION
			#if OVERDRAW_MAX_DISTANCE == 0
				float maxOverdrawDistance = far;
			#else
				float maxOverdrawDistance = OVERDRAW_MAX_DISTANCE;
			#endif

			if(length(playerPos) < clamp(far * 0.9, 16.0, maxOverdrawDistance) || texture2D(depthtex1, gl_FragCoord.xy*texelSize).x < 1.0){ 
				discard; 
				return;
			}
		#endif

		vec3 albedo = toLinear(gcolor.rgb);

		#ifdef DH_NOISE_TEXTURE
			albedo = applyNoise(vec4(albedo, 1.0), playerPos + cameraPosition, length(playerPos)).rgb;
		#endif

		vec3 ambientLightColor = averageSkyCol_Clouds / 900.0;
		float lightness = luma(ambientLightColor);
		vec3 skylightInfluence = mix(vec3(lightness), ambientLightColor, 0.2);

		gl_FragData[0] = vec4(albedo * skylightInfluence * emissive_Brightness * 0.1, gcolor.a);
	}
}
