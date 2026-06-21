#define FOG_USE_SHAPING 1
#define FOG_SHAPING_INTENSITY 0.9

#include "/lib/fog_utils.glsl"

uniform bool isInSpecialEnvironment;
uniform vec3 exitedBiomePos;

#define WEATHER_FOG_EXTINCTION_MULT 1.2
#define LOCAL_FOG_EXTINCTION_MULT 1.3
#define WEATHER_FOG_SINGLE_SCATTER_ALBEDO 0.98
#define LOCAL_FOG_SINGLE_SCATTER_ALBEDO 0.98

#define CLUMPY_FOG_MAX_DISTANCE 1024.0

#define PLAYER_FOG_FADE_DISTANCE 8.0
#define PLAYER_FOG_MIN_INTENSITY 0.5

// Utilities

float phaseRayleigh(float cosTheta) {
	const float oneOverPi 	= 1.0 / acos(-1.0);
	const vec2 mul_add = vec2(0.1, 0.28) * oneOverPi;
	return cosTheta * mul_add.x + mul_add.y; // optimized version from [Elek09], divided by 4 pi for energy conservation
}

float fogPhase(float lightPoint) {
	float linear = clamp(-lightPoint * 0.5 + 0.5, 0.0, 1.0);
	float linear2 = 1.0 - clamp(lightPoint, 0.0, 1.0);

	float exponential = exp2(pow(linear, 0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}

float phaseCloudFog(float x, float g) {
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

float densityAtPosFog(in vec3 pos) {
	pos /= 32.0;
	pos.xz *= 0.5;
	
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	
	f = (f*f) * (3.0 - 2.0 * f);
	
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0, 193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r, xy.g, f.y);
}

float shapeFogNoise(float noise, float coverage, float intensity) {
	float noiseFloor = mix(0, 0.20, pow((coverage - 0.5) / 0.5, 2.0));
	float noiseCeiling = mix(0.10, 0.85, pow(coverage, 2.0));
	float shapedNoise = smoothstep(noiseFloor, noiseCeiling, noise);

	return mix(noise, shapedNoise, intensity);
}

float applyFogShaping(float noise, float coverage, float intensity) {
#if FOG_USE_SHAPING
	return clamp(shapeFogNoise(noise, coverage, intensity), 0.0, 1.0);
#else
	return clamp(noise, 0.0, 1.0);
#endif
}

float getFogStartHeightFade(float height) {
	return clamp(height - float(FOG_START_HEIGHT), 0.0, 1.0);
}

float getDistanceFogFade(float sampleDistance, float fadeDistance, float minIntensity) {
	return mix(minIntensity, 1.0, smoothstep(0.0, fadeDistance, sampleDistance));
}

float getPlayerDistanceFogFade(float sampleDistance) {
	return getDistanceFogFade(sampleDistance, PLAYER_FOG_FADE_DISTANCE, PLAYER_FOG_MIN_INTENSITY);
}


float getLocalEffectDensity(
	in vec3 playerPos
) {	
	float uniformFog = scaleFogSetting(parameters.localFog.x, FOG_UNIFORM_SCALE * 0.1);
	float clumpyFog = scaleFogSetting(parameters.localFog.y, FOG_CLUMPY_SCALE * 0.1);
	float clumpyCoverage = clamp(parameters.localFog.z, 0.0, 1.0);

	float fogResult = uniformFog;
	
	if(clumpyFog > 0.0) {
		vec3 pos = playerPos;
		vec3 samplePos = playerPos * vec3(1.0, 1.0 / 48.0, 1.0) * 24.0 * 7.0;

		samplePos += vec3(1.0, -0.01, 1.0) * frameTimeCounter * 500.0 * Cloud_Speed;

		float localClumpyNoise = densityAtPosFog(samplePos);
		float localClumpyFog = min(max(1.0 - applyFogShaping(localClumpyNoise, clumpyCoverage, FOG_SHAPING_INTENSITY), 0.0), 1.0);

		fogResult += localClumpyFog * clumpyFog;
	}
	
	return pow(fogResult, 2) * getFogStartHeightFade(playerPos.y);
}

float getUniformFogDensity(
	in vec3 playerPos
) {
	float uniformFog = scaleFogSetting(parameters.fog.x, FOG_UNIFORM_SCALE);

	return pow(uniformFog, 3) * getFogStartHeightFade(playerPos.y);
}

float getClumpyFogDensity(
	in vec3 playerPos
) {
	float clumpyFog = scaleFogSetting(parameters.fog.y, FOG_CLUMPY_SCALE);
	float clumpyCoverage = parameters.fog.z;

	float fogResult = 0.0;

	if(clumpyFog > 0.0) {
		vec3 movement = vec3(1.0, -0.01, 1.0) * frameTimeCounter * Cloud_Speed;
		vec3 pos = playerPos;
		vec3 samplePos = playerPos * vec3(1.0, 1.0 / 24.0, 1.0) + movement;
		vec3 samplePos2 = playerPos * vec3(1.0, 1.0 / 48.0, 1.0) + movement;

		float shapeNoise = densityAtPosFog(samplePos * 24.0);;
		float shape = 1.0 - applyFogShaping(shapeNoise, clumpyCoverage, FOG_SHAPING_INTENSITY);
		float shape2Noise = densityAtPosFog(samplePos2 * 200.0 - vec3(min(max(shape - 0.6, 0.0) * 2.0, 1.0) * 200.0));
		float shape2 = 1.0 - applyFogShaping(shape2Noise, clumpyCoverage, FOG_SHAPING_INTENSITY);
		float finalShape = max(min(max(shape - 0.6, 0.0) * 2.0, 1.0) - shape2 * 0.4, 0.0) * exp(-0.05 * max(pos.y - float(FOG_START_HEIGHT), 0.0));

		fogResult += finalShape * pow(clumpyFog, 3);
	}
	
	return fogResult * getFogStartHeightFade(playerPos.y);
}

// Shadows

vec3 sampleShadowmapVL(vec3 shadowMapZeroPos, vec3 shadowMapRayStartPos, vec3 shadowMapRayProgress) {
	vec3 shadowColor = vec3(1.0);

	shadowMapRayProgress = shadowMapZeroPos.xyz + shadowMapRayStartPos;

	#ifdef DISTORT_SHADOWMAP
		float distortFactor = calcDistort(shadowMapRayProgress.xy);
	#else
		float distortFactor = 1.0;
	#endif

	vec3 shadowPos = vec3(shadowMapRayProgress.xy*distortFactor, shadowMapRayProgress.z);

	if (abs(shadowPos.x) < 1.0-0.5/2048. && abs(shadowPos.y) < 1.0-0.5/2048) {

		shadowPos = shadowPos * vec3(0.5, 0.5, 0.5/6.0) + 0.5;

		#ifdef TRANSLUCENT_COLORED_SHADOWS
			shadowColor = vec3(shadow2D(shadowtex0, shadowPos).x);

			if(shadow2D(shadowtex1, shadowPos).x > shadowPos.z && shadowColor.x < 1.0) {
				vec4 translucentShadow = texture(shadowcolor0, shadowPos.xy);
				if(translucentShadow.a < 0.9) shadowColor = normalize(translucentShadow.rgb+0.0001);
			}
		#else
			float shadowMap = shadow2D(shadow, shadowPos).x;
			shadowColor = vec3(shadowMap);
		#endif
	}
	return shadowColor;
}

vec3 getShadows(
	vec3 rayProgress, 
	in vec3 sunVector,
	vec3 shadowMapZeroPos, 
	vec3 shadowMapRayStartPos, 
	vec3 shadowMapRayProgress,
	float flatPhase,
	inout float sunPhase
) {
	vec3 shadows = vec3(1.0);
	shadows *= sampleShadowmapVL(shadowMapZeroPos, shadowMapRayStartPos, shadowMapRayProgress);
	
	float cloudShadow = GetCloudShadow(rayProgress, sunVector);
	shadows *= cloudShadow;

	return shadows;
}

// Volumetric Fog

vec4 GetVolumetricFog(
	in vec3 viewPos,
	in vec2 dither,
	in vec3 sunVector,
	in float sunShadow,
	in vec3 lightColor,
	in vec3 ambientColor,
	in vec3 averagedAmbientColor,
	
	in float cloudPlaneDistance,
	in bool isSkyRay
) {
	#ifndef TOGGLE_VL_FOG
		return vec4(0.0, 0.0, 0.0, 1.0);
	#endif
	
	const int sampleCount = VL_SAMPLES;
	const float expFactor = 11.0;

	// Project pixel position into shadow map space.
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
	vec3 rayStartPos = playerPos - gbufferModelViewInverse[3].xyz;

	vec3 localRayStartPos = rayStartPos;
	float localRayLength = length(localRayStartPos);

	localRayStartPos *= min(localRayLength, 64.0) / max(localRayLength, 1e-6);
	localRayLength = length(localRayStartPos); 

	// Shadow Map

	vec3 shadowViewPos = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
	shadowViewPos = diagonal3(shadowProjection) * shadowViewPos + shadowProjection[3].xyz;

	vec3 shadowMapZeroPos = toShadowSpaceProjected(vec3(0.0));
	vec3 shadowMapRayStartPos = shadowViewPos - shadowMapZeroPos;

	float fullRayLength = length(rayStartPos);
	float rayLength = fullRayLength;

	#ifdef USING_LOD_MOD
		float maxLength = min(rayLength, max(far, LOD_RENDERDISTANCE)) / max(rayLength, 1e-6);
	#else
		float maxLength = min(rayLength, far) / max(rayLength, 1e-6);
	#endif

	shadowMapRayStartPos *= maxLength;
	rayStartPos *= maxLength;

	rayLength = length(rayStartPos);

	vec3 weatherRayStartPos = rayStartPos;
	float weatherRayLength = rayLength;

	if(isSkyRay) {
		#ifdef USING_LOD_MOD
			float skyWeatherDistance = max(far, LOD_RENDERDISTANCE);
		#else
			float skyWeatherDistance = far;
		#endif

		float weatherMaxLength = min(fullRayLength, skyWeatherDistance) / max(fullRayLength, 1e-6);
		weatherRayStartPos = (playerPos - gbufferModelViewInverse[3].xyz) * weatherMaxLength;
		weatherRayLength = length(weatherRayStartPos);
	}

	vec3 clumpyRayStartPos = weatherRayStartPos;
	float clumpyRayLength = weatherRayLength;
	float clumpyMaxLength = min(clumpyRayLength, CLUMPY_FOG_MAX_DISTANCE) / max(clumpyRayLength, 1e-6);

	clumpyRayStartPos *= clumpyMaxLength;
	clumpyRayLength = length(clumpyRayStartPos);

	vec3 rayProgress = vec3(0.0);
	vec3 weatherRayProgress = vec3(0.0);
	vec3 clumpyRayProgress = vec3(0.0);
	vec3 localRayProgress = vec3(0.0);
	vec3 shadowMapRayProgress = vec3(0.0);

	float SdotV = dot(sunVector, normalize(playerPos));
	float rayleighPhase = phaseRayleigh(SdotV);

	float flatPhase = clamp(SdotV * 0.5 + 0.5, 0.0, 1.0);
	float fullSunPhase = fogPhase(SdotV) * 5.0;
	float sunPhase = mix(fullSunPhase, flatPhase, sunShadow);

	float absorbance = 1.0;
	float localAbsorbance = 1.0;

	vec3 airAbsorbance = vec3(1.0);
	
	float eyeSkyVisibility = clamp(eyeBrightnessSmooth.y / 240.0, 0.0, 1.0);
	float daylightFactor = clamp(sunElevation * 2.0, 0.0, 1.0);
	float daylightAmp = (1.0 + (1.0 - daylightFactor) * 1.0);
	
	vec3 masterLightColor = lightColor * 1.5 * daylightAmp;
	vec3 ambientLightColor = ambientColor * 1.2 + 0.25 * lightColor;

	vec3 localFogColor = parameters.localFogColor.rgb;
	vec3 localFogColor_lightCol = localFogColor * dot(masterLightColor, vec3(0.33333));
	vec3 localFogColor_ambientCol = localFogColor * dot(ambientLightColor, vec3(0.33333));

	float skyPhase = 0.5 + pow(1.0 - pow(1.0 - clamp(normalize(playerPos).y * 0.5 + 0.5, 0.0, 1.0), 2.0), 2.0) * 2.0;

	vec3 rayleighCoeffs = vec3(sky_coefficientRayleighR * 1e-6, sky_coefficientRayleighG * 1e-5, sky_coefficientRayleighB * 1e-5);
	vec3 mieCoeffs = vec3(sky_coefficientMieR * 1e-6, sky_coefficientMieG * 1e-6, sky_coefficientMieB * 1e-6);

	// If current fog parameters include any local fog.
	float localFogDensityFactor = (parameters.localFog.x > 0.0 || parameters.localFog.y > 0.0) ? 1.0 : 0.0;

	vec3 color = vec3(0.0);
	
	for (int i = 0; i < sampleCount; i++) {
		float sampleOffset = (pow(expFactor, float(i + dither.x) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor);
		float volumeSampleOffset = pow(expFactor, float(i + dither.y) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0);
	
		#if defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2
			float airKill = length(sampleOffset * rayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
			float weatherKill = length(sampleOffset * weatherRayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
			float clumpyKill = length(sampleOffset * clumpyRayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#else
			float airKill = 1.0;
			float weatherKill = 1.0;
			float clumpyKill = 1.0;
		#endif

		rayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * rayStartPos;
		weatherRayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * weatherRayStartPos;
		clumpyRayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * clumpyRayStartPos;
		localRayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * localRayStartPos;
		
		#ifdef FAKE_PLANET
			lightColor = getPlanetAbsorb(rayProgress, WsunVec, colortex4);
		#endif

		// Receives: Sampled position, sun vector, sampling distance, shadow map zero position, shadow map max ray length position, shadow map progress, ambient light phase, sun light phase
		vec3 shadows = getShadows(mix(weatherRayProgress, localRayProgress, localFogDensityFactor), sunVector, shadowMapZeroPos, shadowMapRayStartPos * sampleOffset, shadowMapRayProgress, flatPhase, sunPhase);
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			vec3 lightningFlash = createLightningPointLight(rayProgress - cameraPosition, lightningBoltPosition.xyz, 1.0, 1.0) * eyeSkyVisibility;
		#endif
		
		// (I) Atmosphere

		float planetVolume = clamp(1.0 - length((rayProgress - cameraPosition) - vec3(0.0, 250.0, 0.0)) / 2500.0, 0.0, 1.0);
		float fogStartHeightFade = getFogStartHeightFade(rayProgress.y);

		#ifdef USING_LOD_MOD
			vec2 airCoef = exp2(-max(rayProgress.y - float(FOG_START_HEIGHT), 0.0) / vec2(8.0e3, 1.2e3) * vec2(6.0, 7.0)) * planetVolume * 12.5 * ATMOSPHERIC_HAZE_AMOUNT;
		#else
			vec2 airCoef = exp2(-max(rayProgress.y - float(FOG_START_HEIGHT), 0.0) / vec2(8.0e3, 1.2e3) * vec2(6.0, 7.0)) * planetVolume * 25.0 * ATMOSPHERIC_HAZE_AMOUNT;
		#endif

		vec3 rayleigh = rayleighCoeffs * airCoef.x;
		vec3 mie = mieCoeffs * (airCoef.y + min(ATMOSPHERIC_HAZE_AMOUNT, 1.0) * fogStartHeightFade);
		vec3 airDensity = airKill * (rayleigh + mie);
		vec3 airDensityPhased = rayleighPhase * rayleigh + sunPhase * mie;
		vec3 airVolumeCoeff = exp(-airDensity * volumeSampleOffset * rayLength);
		vec3 airLighting = masterLightColor * shadows * sunPhase * airDensityPhased + averagedAmbientColor * airDensity * 0.666;
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			airLighting += lightningFlash * airDensity;
		#endif

		airLighting = (airLighting - airLighting * airVolumeCoeff) / (airDensity + 1e-6) * airAbsorbance;
		
		color += airLighting;

		// (II) Global Fog

		vec3 fogLighting = masterLightColor * sunPhase * shadows + ambientLightColor * skyPhase;

		// Lightning
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			fogLighting += lightningFlash;
		#endif

		float uniformStepLength = volumeSampleOffset * weatherRayLength;
		float uniformFogFade = getPlayerDistanceFogFade(length(sampleOffset * weatherRayStartPos));
		float uniformDensity = weatherKill * getUniformFogDensity(weatherRayProgress) * uniformFogFade;
		float uniformSigmaT = uniformDensity * WEATHER_FOG_EXTINCTION_MULT;
		float uniformFogVolumeCoeff = clamp(exp(-uniformSigmaT * uniformStepLength), 0.0, 1.0);
		
		color += fogLighting * (1.0 - uniformFogVolumeCoeff) * WEATHER_FOG_SINGLE_SCATTER_ALBEDO * absorbance;

		float clumpyStepLength = volumeSampleOffset * clumpyRayLength;
		float clumpyFogFade = getPlayerDistanceFogFade(length(sampleOffset * clumpyRayStartPos));
		float clumpyDensity = clumpyKill * getClumpyFogDensity(clumpyRayProgress) * clumpyFogFade;
		float clumpySigmaT = clumpyDensity * WEATHER_FOG_EXTINCTION_MULT;
		float clumpyFogVolumeCoeff = clamp(exp(-clumpySigmaT * clumpyStepLength), 0.0, 1.0);

		color += fogLighting * (1.0 - clumpyFogVolumeCoeff) * WEATHER_FOG_SINGLE_SCATTER_ALBEDO * absorbance * uniformFogVolumeCoeff;

		float fogVolumeCoeff = uniformFogVolumeCoeff * clumpyFogVolumeCoeff;

		// (III) Local Fog

		#if (defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2)
			float localKill = length(sampleOffset * localRayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#else
			float localKill = 1.0;
		#endif

		float localStepLength = volumeSampleOffset * localRayLength;
		float localEffectDensity = localKill * getLocalEffectDensity(localRayProgress);
		float localFogFade = getPlayerDistanceFogFade(length(sampleOffset * localRayStartPos));
		localEffectDensity *= localFogFade;

		float localFogSigmaT = localEffectDensity * LOCAL_FOG_EXTINCTION_MULT;
		float localFogVolumeCoeff = exp(-localFogSigmaT * localStepLength);
		vec3 localFogLighting = localFogColor_lightCol * shadows * sunPhase + localFogColor_ambientCol * skyPhase;
		
		color += localFogLighting * (1.0 - localFogVolumeCoeff) * LOCAL_FOG_SINGLE_SCATTER_ALBEDO * localAbsorbance;
		
		localAbsorbance *= localFogVolumeCoeff;
		airAbsorbance *= airVolumeCoeff * fogVolumeCoeff * localFogVolumeCoeff;
		absorbance *= fogVolumeCoeff * localFogVolumeCoeff * dot(airVolumeCoeff, vec3(0.33333));
	}

	return vec4(color, absorbance);
}
