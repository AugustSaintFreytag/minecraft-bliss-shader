#define NETHER_RELATED_SETTINGS
#define END_RELATED_SETTINGS
#define ATMOSPHERE_COEFF_RELATED_SETTINGS
#define SUN_AND_MOON_RELATED_SETTINGS
#define SKY_RELATED_SETTINGS
#define SHADOWMAP_CONSTANT_RELATED_SETTINGS
#define AMBIENT_LIGHT_RELATED_SETTINGS
#define SEASONS_RELATED_SETTINGS
#define VOLUMETRIC_CLOUD_RELATED_SETTINGS
#define VOLUMETRIC_FOG_RELATED_SETTINGS
#define SCENE_CONTROLLER_RELATED_SETTINGS
#define ANTIALIASING_RELATED_SETTINGS

#include "/lib/settings.glsl"

flat varying vec3 averageSkyCol_Clouds;
flat varying vec3 averageSkyCol;

flat varying vec3 sunColor;
flat varying vec3 sunColor2;
flat varying vec3 moonColor;
flat varying vec3 lightSourceColor;
flat varying vec3 zenithColor;
flat varying vec3 WsunVec;

flat varying float exposure;
flat varying float avgBrightness;
flat varying float rodExposure;
flat varying float avgL2;
flat varying float centerDepth;

uniform int hideGUI;

uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec2 texelSize;
uniform float sunElevation;
uniform float eyeAltitude;
uniform float rainStrength;
uniform float nightVision;
uniform float near;
uniform float far;
uniform float frameTime;
uniform int frameCounter;
uniform float frameTimeCounter;

vec3 sunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

#include "/lib/util.glsl"
#include "/lib/res_params.glsl"
#include "/lib/macro_lod_mod.glsl"
#include "/lib/shadow_params.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/robobo_sky.glsl"

float luma(vec3 color) {
	return dot(color,vec3(0.21, 0.72, 0.07));
}

vec3 rodSample(vec2 Xi)
{
	float r = sqrt(1.0f - Xi.x*Xi.y);
    float phi = 2 * PI * Xi.y;

    return normalize(vec3(cos(phi) * r, sin(phi) * r, Xi.x)).xzy;
}

//Low discrepancy 2D sequence, integration error is as low as sobol but easier to compute : http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
vec2 R2_samples(int n) {
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

float tanh(float x) {
	return (exp(x) - exp(-x))/(exp(x) + exp(-x));
}

float hash11(float p) {
    p = fract(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

#define USE_SCENE_CONTROLLER_SETTINGS
#include "/lib/scene_controller.glsl"

void main() {
	gl_Position = ftransform();
	gl_Position.xy *= vec2(SKY_CLOUD_ATLAS_OFFSET_X + SKY_ATLAS_SIZE + 1.0, SKY_ATLAS_SIZE + 1.0) * texelSize;
	gl_Position.xy = gl_Position.xy * 2.0 - 1.0;

	WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

	#ifdef OVERWORLD_SHADER

		///////////////////////////////////
		/// --- AMBIENT LIGHT STUFF --- ///
		///////////////////////////////////

		averageSkyCol_Clouds = vec3(0.0);
		averageSkyCol = vec3(0.0);

		vec2 sample3x3[9] = vec2[](
			vec2(-1.0, -0.3),
			vec2( 0.0,  0.0),
			vec2( 1.0, -0.3),

			vec2(-1.0, -0.5),
			vec2( 0.0, -0.5),
			vec2( 1.0, -0.5),

			vec2(-1.0, -1.0),
			vec2( 0.0, -1.0),
			vec2( 1.0, -1.0)
		);

		float maxIT = 20.0;

		for (int i = 0; i < int(maxIT); i++) {
			vec2 ij = R2_samples(((i * 50 + 1) % 1000) * int(maxIT) + i) * vec2(1.0, 0.9000);
			vec3 pos = normalize(rodSample(ij)) * vec3(1.0, 0.5, 1.0) + vec3(0.0, 0.5, 0.0);

			averageSkyCol += 1.5 * skyFromTex(pos, colortex4).rgb / maxIT / 150.0;
			averageSkyCol_Clouds += skyCloudsFromTex(pos, colortex4).rgb / maxIT / 150.0;
		}

		averageSkyCol_Clouds = 1.5 * (averageSkyCol_Clouds / (1.0 + luma(averageSkyCol_Clouds) * 0.2));		
		averageSkyCol = max(averageSkyCol * PLANET_GROUND_BRIGHTNESS, 0.0);

		#ifdef USE_CUSTOM_SKY_GROUND_LIGHTING_COLORS
			averageSkyCol = luma(averageSkyCol) * vec3(SKY_GROUND_R,SKY_GROUND_G,SKY_GROUND_B);
		#endif

		////////////////////////////////////////
		/// --- SUNLIGHT/MOONLIGHT STUFF --- ///
		////////////////////////////////////////

		vec2 planetSphere = vec2(0.0);

		float sunVis = clamp(sunElevation, 0.0, 0.05) / 0.05 * clamp(sunElevation, 0.0, 0.05) / 0.05;
		float moonVis = clamp(-sunElevation, 0.0, 0.05) / 0.05 * clamp(-sunElevation, 0.0, 0.05) / 0.05;

		vec3 skyAbsorb = vec3(0.0);
		sunColor = calculateAtmosphere(vec3(0.0), sunVec, vec3(0.0, 1.0, 0.0), sunVec, -sunVec, planetSphere, skyAbsorb, 25, 0.0);
		sunColor = sunColorBase/4000.0 * skyAbsorb;
		sunColor2 = sunColorBase/4000.0;
		moonColor = moonColorBase/4000.0;

		lightSourceColor = sunColor * sunVis + moonColor * moonVis;
	#endif

	#if defined OVERWORLD_SHADER && defined TWILIGHT_FOREST_FLAG
		lightSourceColor = vec3(0.0);
		moonColor = vec3(0.0);
	#endif

	///////////////////////////////////////////
	/// --- SCENE CONTROLLER PARAMETERS --- ///
	///////////////////////////////////////////

	// components are split for readability/user friendliness within this function
	applySceneControllerParameters(
		parameters.smallCumulus.x, parameters.smallCumulus.y, 
		parameters.largeCumulus.x, parameters.largeCumulus.y,
		parameters.altostratus.x, parameters.altostratus.y,
		parameters.fog.x, parameters.fog.y, parameters.fog.z,
		parameters.localFog.x, parameters.localFog.y, parameters.localFog.z, parameters.localFogColor.rgb
	);

	//////////////////////////////
	/// --- EXPOSURE STUFF --- ///
	//////////////////////////////

	float avgLuma = 0.0;
	float m2 = 0.0;
	int n = 100;
	
	vec2 clampedRes = max(1.0 / texelSize, vec2(1920.0, 1080.0));
	vec2 resScale = vec2(1920.0, 1080.0) / clampedRes;

	float avgExp = 0.0;
	float avgB = 0.0;
	
	const int maxITexp = 50;
	float w = 0.0;
	
	for (int i = 0; i < maxITexp; i++){
		vec2 ij = R2_samples((frameCounter % 2000) * maxITexp + i);
		vec2 tc = 0.5 + (ij - 0.5) * 0.7;
		vec3 sp = texture(colortex6, tc / 16.0 * resScale + vec2(0.375 * resScale.x + 4.5 * texelSize.x, 0.0)).rgb;
		avgExp += log(sqrt(luma(sp)));
		avgB += log(min(dot(sp,vec3(0.07, 0.22, 0.71)), 8e-2));
	}

	avgExp = exp(avgExp/maxITexp);
	avgB = exp(avgB/maxITexp);
	
	avgBrightness = clamp(mix(avgExp,texelFetch(colortex4, IMAGE_BRIGHTNESS_COORDS, 0).g, AUTO_EXPOSURE_ADJUST_RATE), 0.00003051757, 65000.0);

	float L = max(avgBrightness, 1e-8);
	float keyVal = 1.03 - 2.0 / (log(L * 4000 / 150.0 * 8.0 / 3.0 + 1.0) / log(10.0) + 2.0);
	float expFunc = 0.5 + 0.5 * tanh(log(L));
	float targetExposure = (EXPOSURE_DARKENING * 0.35)/log(L + 1.0 + EXPOSURE_BRIGHTENING * 0.05);

	avgL2 = clamp(mix(avgB, texelFetch(colortex4, IMAGE_BRIGHTNESS_COORDS, 0).b, 0.985), 0.00003051757, 65000.0);
	float targetrodExposure = max(0.012 / log2(avgL2 + 1.002) - 0.1, 0.0) * 1.2;

	exposure = max(targetExposure * EXPOSURE_MULTIPLIER, 0.0);

	float currCenterDepth = linZ(texture(depthtex2, vec2(0.5) * RENDER_SCALE).r);
	centerDepth = mix(sqrt(texelFetch(colortex4, AUTO_EXPOSURE_COORDS,0).g / 65000.0), currCenterDepth, clamp(DoF_Adaptation_Speed * exp(-0.016 / frameTime + 1.0) / (6.0 + currCenterDepth * far), 0.0, 1.0));
	centerDepth = centerDepth * centerDepth * 65000.0;

	rodExposure = targetrodExposure;

	#ifndef AUTO_EXPOSURE
		exposure = Manual_exposure_value;
		rodExposure = clamp(log(Manual_exposure_value * 2.0 + 1.0) - 0.1, 0.0, 2.0);
	#endif

	#ifdef display_LUT
		if(hideGUI == 0){
			exposure = Manual_exposure_value;
			rodExposure = clamp(log(Manual_exposure_value * 2.0 + 1.0) - 0.1, 0.0, 2.0);
		}
	#endif
}
