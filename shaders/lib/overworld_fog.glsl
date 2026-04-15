#define FOG_USE_SHAPING 1
#define FOG_USE_TURBULENCE 1

#define FOG_TURBULENCE_MIX 1.0
#define FOG_SHAPING_INTENSITY 1.0

#include "/lib/fog_utils.glsl"

uniform bool isInSpecialEnvironment;
uniform vec3 exitedBiomePos;

// Utilities

float phaseRayleigh(float cosTheta) {
	const float oneOverPi 	= 1.0 / acos(-1.0);
	const vec2 mul_add = vec2(0.1, 0.28) * oneOverPi;
	return cosTheta * mul_add.x + mul_add.y; // optimized version from [Elek09], divided by 4 pi for energy conservation
}

float fogPhase(float lightPoint) {
	float linear = clamp(-lightPoint*0.5+0.5,0.0,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}

float phaseCloudFog(float x, float g) {
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

float densityAtPosFog(in vec3 pos) {
	pos /= 16.0;
	pos.xz *= 0.5;
	
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	
	f = (f*f) * (3.-2.*f);
	
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0, 193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r, xy.g, f.y);
}

float turbulentFogNoise(in vec3 pos) {
	pos /= 8;
	float noise = 0.0;
	float amplitude = 0.65;
	float frequency = 1.2;
	vec3 warp = frameTimeCounter * 10 * Cloud_Speed * vec3(-0.02, 0.004, -0.006);

	for(int i = 0; i < 3; i++) {
		float n = densityAtPosFog(pos * frequency + warp);

		n = 1.0 - abs(n * 2.0 - 1.0);
		n = n * n;
		noise += n * amplitude;
		warp += vec3(n) * 0.35;
		frequency *= 2.2;
		amplitude *= 0.5;
	}

	return noise;
}

float shapeFogNoise(float noise, float coverage, float intensity) {
	float noiseFloor = mix(0, 0.25, coverage - 0.5);
	float noiseCeiling = mix(0.25, 0.7, coverage);
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

float applyFogTurbulence(float baseNoise, vec3 pos) {
#if FOG_USE_TURBULENCE
	float turbulentNoise = turbulentFogNoise(pos);
	return mix(baseNoise, baseNoise * 0.25 + turbulentNoise * 0.75, FOG_TURBULENCE_MIX);
#else
	return baseNoise;
#endif
}

float getFogStartHeightFade(float height) {
	return clamp(height - float(FOG_START_HEIGHT), 0.0, 1.0);
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

		float baseNoise = densityAtPosFog(samplePos);
		float localClumpyNoise = applyFogTurbulence(baseNoise, samplePos);
		float localClumpyFog = min(max(1.0 - applyFogShaping(localClumpyNoise, clumpyCoverage, FOG_SHAPING_INTENSITY), 0.0), 1.0);

		fogResult += localClumpyFog * clumpyFog;
	}
	
	return pow(fogResult, 2) * getFogStartHeightFade(playerPos.y);
}

float getFogDensities(
	in vec3 playerPos,
	float localEffectRadius
) {	
	float uniformFog = scaleFogSetting(parameters.fog.x, FOG_UNIFORM_SCALE);
	float clumpyFog = scaleFogSetting(parameters.fog.y, FOG_CLUMPY_SCALE);
	float clumpyCoverage = parameters.fog.z;

	float fogResult = pow(uniformFog, 3);

	if(clumpyFog > 0.0) {
		vec3 movement = vec3(1.0, -0.01, 1.0) * frameTimeCounter * Cloud_Speed;
		vec3 pos = playerPos;
		vec3 samplePos = playerPos * vec3(1.0, 1.0 / 24.0, 1.0) + movement;
		vec3 samplePos2 = playerPos * vec3(1.0, 1.0 / 48.0, 1.0) + movement;

		float shapeBaseNoise = densityAtPosFog(samplePos * 24.0);
		float shapeNoise = applyFogTurbulence(shapeBaseNoise, samplePos * 18.0);
		float shape = 1.0 - applyFogShaping(shapeNoise, clumpyCoverage, FOG_SHAPING_INTENSITY);
		float shape2BaseNoise = densityAtPosFog(samplePos2 * 200.0 - vec3(min(max(shape - 0.6, 0.0) * 2.0, 1.0) * 200.0));
		float shape2Noise = applyFogTurbulence(shape2BaseNoise, samplePos2 * 150.0);
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
	
	in float cloudPlaneDistance
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

	localRayStartPos *= min(localRayLength, 64.0) / localRayLength;
	localRayLength = length(localRayStartPos); 

	// Shadow Map

	vec3 shadowViewPos = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
	shadowViewPos = diagonal3(shadowProjection) * shadowViewPos + shadowProjection[3].xyz;

	vec3 shadowMapZeroPos = toShadowSpaceProjected(vec3(0.0));
	vec3 shadowMapRayStartPos = shadowViewPos - shadowMapZeroPos;

	float rayLength = length(rayStartPos);

	#ifdef USING_LOD_MOD
		float maxLength = min(rayLength, max(far, LOD_RENDERDISTANCE)) / rayLength;
	#else
		float maxLength = min(rayLength, far)/rayLength;
	#endif

	shadowMapRayStartPos *= maxLength;
	rayStartPos *= maxLength;

	rayLength = length(rayStartPos);

	vec3 rayProgress = vec3(0.0);
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
	
	float indoors = clamp(eyeBrightnessSmooth.y / 240.0, 0, 1);
	float daylightFactor = clamp(sunElevation * 2.0, 0.0, 1.0);
	
	vec3 masterLightColor = saturate(lightColor * 1.5, 0.85) * (1.0 + (1.0 - daylightFactor) * 1.0);
	vec3 ambientLightColor = saturate(ambientColor * 1.25, 0.25) + (0.25 * saturate(lightColor, 0.35));

	vec3 localFogColor = parameters.localFogColor.rgb;
	vec3 localFogColor_lightCol = localFogColor * dot(masterLightColor, vec3(0.33333));
	vec3 localFogColor_ambientCol = localFogColor * dot(ambientLightColor, vec3(0.33333));

	float skyPhase = 0.5 + pow(1.0 - pow(1.0 - clamp(normalize(playerPos).y * 0.5 + 0.5, 0.0, 1.0), 2.0), 2.0) * 2.0;

	vec3 rayleighCoeffs = vec3(sky_coefficientRayleighR*1e-6, sky_coefficientRayleighG*1e-5, sky_coefficientRayleighB*1e-5);
	vec3 mieCoeffs = vec3(sky_coefficientMieR*1e-6, sky_coefficientMieG*1e-6, sky_coefficientMieB*1e-6);

	// If current fog parameters include any local fog.
	float localFogDensityFactor = (parameters.localFog.x > 0.0 || parameters.localFog.y > 0.0) ? 1.0 : 0.0;

	vec3 color = vec3(0.0);
	
	for (int i = 0; i < sampleCount; i++) {
		float sampleOffset = (pow(expFactor, float(i + dither.x) / float(sampleCount)) / expFactor - 1.0 / expFactor) / (1.0 - 1.0 / expFactor);
		float volumeSampleOffset = pow(expFactor, float(i + dither.y) / float(sampleCount)) * log(expFactor) / float(sampleCount) / (expFactor - 1.0);
	
		#if defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2
			float kill = length(sampleOffset * rayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#else
			float kill = 1.0;
		#endif

		rayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * rayStartPos;
		localRayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + sampleOffset * localRayStartPos;
		
		#ifdef FAKE_PLANET
			lightColor = getPlanetAbsorb(rayProgress, WsunVec, colortex4);
		#endif

		// Receives: Sampled position, sun vector, sampling distance, shadow map zero position, shadow map max ray length position, shadow map progress, ambient light phase, sun light phase
		vec3 shadows = getShadows(mix(rayProgress, localRayProgress, localFogDensityFactor), sunVector, shadowMapZeroPos, shadowMapRayStartPos * sampleOffset, shadowMapRayProgress, flatPhase, sunPhase);
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			vec3 lightningFlash = createLightningPointLight(rayProgress - cameraPosition, lightningBoltPosition.xyz, 1.0, 1.0) * indoors;
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
		vec3 airDensity = kill * (rayleigh + mie);
		vec3 airDensityPhased = rayleighPhase * rayleigh + sunPhase * mie;
		vec3 airVolumeCoeff = exp(-airDensity * volumeSampleOffset * rayLength);
		vec3 airLighting = masterLightColor * shadows * sunPhase * airDensityPhased + averagedAmbientColor * airDensity * 0.666;
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			airLighting += lightningFlash * airDensity;
		#endif

		airLighting = (airLighting - airLighting * airVolumeCoeff) / (airDensity + 1e-6) * airAbsorbance;
		
		color += airLighting;

		// (II) Global Fog

		float fogDensity = kill * getFogDensities(rayProgress, 0.0) * pow(indoors, 3);
		float fogVolumeCoeff = clamp(exp(-fogDensity * volumeSampleOffset * rayLength), 0.0, 1.0);
		float fogSunPhase = mix(sunPhase, sunPhase, smoothstep(0.0, 1.0, fogVolumeCoeff * 1.5));

		vec3 fogLighting = masterLightColor * fogSunPhase * shadows * 0.85 + ambientLightColor * skyPhase;

		// Lightning
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			fogLighting += lightningFlash;
		#endif
		
		fogLighting = (fogLighting - fogLighting * fogVolumeCoeff) * absorbance;

		color += fogLighting;

		// (III) Local Fog

		#if (defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2)
			kill = length(sampleOffset * localRayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#endif

		float localEffectDensity = kill * getLocalEffectDensity(localRayProgress);

		#ifdef EXCLUDE_WRITE_TO_LUT
			localEffectDensity *= indoors;
		#endif

		float localFogVolumeCoeff = exp(-localEffectDensity * volumeSampleOffset * localRayLength);
		vec3 localFogLighting = localFogColor_lightCol * shadows * sunPhase + localFogColor_ambientCol * skyPhase;
		
		color += (localFogLighting - localFogLighting * localFogVolumeCoeff) * localAbsorbance;
		
		localAbsorbance *= localFogVolumeCoeff;
		airAbsorbance *= airVolumeCoeff * fogVolumeCoeff * localFogVolumeCoeff;
		absorbance *= fogVolumeCoeff * localFogVolumeCoeff * dot(airVolumeCoeff, vec3(0.33333));
	}

	return vec4(color, absorbance);
}
