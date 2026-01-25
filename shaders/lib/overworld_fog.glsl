uniform ivec2 eyeBrightness;

#include "/lib/fog_utils.glsl"

#define FOG_USE_SHAPING 1
#define FOG_USE_TURBULENCE 1

const float FOG_TURBULENCE_MIX = 0.85;
const float FOG_SHAPING_INTENSITY = 0.95;

// Utilities

float phaseRayleigh(float cosTheta) {
	const float oneOverPi 	= 1.0 / acos(-1.0);
	const vec2 mul_add = vec2(0.1, 0.28) * oneOverPi;
	return cosTheta * mul_add.x + mul_add.y; // optimized version from [Elek09], divided by 4 pi for energy conservation
}

float fogPhase(float lightPoint){
	float linear = clamp(-lightPoint*0.5+0.5,0.0,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}

float phaseCloudFog(float x, float g){
    float gg = g * g;
    return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

float densityAtPosFog(in vec3 pos){
	pos /= 24.0;
	pos.xz *= 0.5;
	
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	
	f = (f*f) * (3.-2.*f);
	
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0, 193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture2D(noisetex, coord).yx;

	return mix(xy.r, xy.g, f.y);
}

float turbulentFogNoise(in vec3 pos){
	vec3 p = pos * 0.5;
	float noise = 0.0;
	float amplitude = 0.6;
	float frequency = 1.0;
	vec3 warp = frameTimeCounter * 10 * Cloud_Speed * vec3(-0.02, 0.004, -0.006);

	for(int i = 0; i < 3; i++){
		float n = densityAtPosFog(p * frequency + warp);

		n = 1.0 - abs(n * 2.0 - 1.0);
		n = n * n;
		noise += n * amplitude;
		warp += vec3(n) * 0.35;
		frequency *= 2.2;
		amplitude *= 0.5;
	}

	return noise;
}

float shapeFogNoise(float noise, float coverage, float intensity){
	float noiseFloor = mix(0, 0.2, coverage - 0.5);
	float noiseCeiling = mix(0.3, 0.9, coverage);
	float shapedNoise = smoothstep(noiseFloor, noiseCeiling, noise);

	return mix(noise, shapedNoise, intensity);
}

float applyFogShaping(float noise, float coverage, float intensity){
#if FOG_USE_SHAPING
	return clamp(shapeFogNoise(noise, coverage, intensity), 0.0, 1.0);
#else
	return clamp(noise, 0.0, 1.0);
#endif
}

float applyFogTurbulence(float baseNoise, vec3 pos){
#if FOG_USE_TURBULENCE
	float turbulentNoise = turbulentFogNoise(pos);
	return mix(baseNoise, turbulentNoise, FOG_TURBULENCE_MIX);
#else
	return baseNoise;
#endif
}

uniform bool isInSpecialEnvironment;
uniform vec3 exitedBiomePos;

float getLocalEffectDensity(
	in vec3 playerPos
){	
	float uniformFog = scaleFogSetting(parameters.localFog.x, FOG_UNIFORM_SCALE * 0.1);
	float clumpyFog = scaleFogSetting(parameters.localFog.y, FOG_CLUMPY_SCALE * 0.1);
	float clumpyCoverage = clamp(parameters.localFog.z, 0.0, 1.0);

	float fogResult = uniformFog;
	
	if(clumpyFog > 0.0){
		vec3 pos = playerPos;
		vec3 samplePos = playerPos * vec3(1.0, 1.0 / 48.0, 1.0) * 24.0 * 7.0;

		samplePos += vec3(1.0, -0.01, 1.0) * frameTimeCounter * 500.0 * Cloud_Speed;

		float baseNoise = densityAtPosFog(samplePos);
		float localClumpyNoise = applyFogTurbulence(baseNoise, samplePos);
		float localClumpyFog = min(max(1.0 - applyFogShaping(localClumpyNoise, clumpyCoverage, FOG_SHAPING_INTENSITY) - 0.2, 0.0) / 0.8, 1.0);

		fogResult += localClumpyFog * clumpyFog;
	}
	
	return fogResult;
}

float getFogDensities(
	in vec3 playerPos,
	float localEffectRadius
){	
	float uniformFog = scaleFogSetting(parameters.fog.x, FOG_UNIFORM_SCALE);
	float clumpyFog = scaleFogSetting(parameters.fog.y, FOG_CLUMPY_SCALE);
	float clumpyCoverage = parameters.fog.z;

	float fogResult = pow(uniformFog, 3);

	if(clumpyFog > 0.0){
		vec3 movement = vec3(1.0, -0.01, 1.0) * frameTimeCounter * Cloud_Speed;
		vec3 pos = playerPos;
		vec3 samplePos = playerPos * vec3(1.0, 1.0 / 24.0, 1.0) + movement;
		vec3 samplePos2 = playerPos * vec3(1.0, 1.0 / 48.0, 1.0) + movement;

		float shapeBaseNoise = densityAtPosFog(samplePos * 24.0);
		float shapeNoise = applyFogTurbulence(shapeBaseNoise, samplePos * 18.0);
		float shape = 1.0 - applyFogShaping(shapeNoise, clumpyCoverage, FOG_SHAPING_INTENSITY);
		float shape2BaseNoise = densityAtPosFog(samplePos2 * 200.0 - vec3(min(max(shape - 0.6 ,0.0) * 2.0 ,1.0) * 200.0));
		float shape2Noise = applyFogTurbulence(shape2BaseNoise, samplePos2 * 150.0);
		float shape2 = 1.0 - applyFogShaping(shape2Noise, clumpyCoverage, FOG_SHAPING_INTENSITY);
		float finalShape = max(min(max(shape - 0.6, 0.0) * 2.0, 1.0) - shape2 * 0.4, 0.0) * exp(-0.05 * max(pos.y - 60, 0.0));

		fogResult += finalShape * pow(clumpyFog, 3);
	}
	
	return fogResult;
}

// Shadows

vec3 sampleShadowmapVL(vec3 start, vec3 shadowMapRayStartPos, vec3 shadowMapRayProgress, float increment) {
	vec3 shadowColor = vec3(1.0);

	shadowMapRayProgress = start.xyz + increment*shadowMapRayStartPos;

	#ifdef DISTORT_SHADOWMAP
		float distortFactor = calcDistort(shadowMapRayProgress.xy);
	#else
		float distortFactor = 1.0;
	#endif

	vec3 shadowPos = vec3(shadowMapRayProgress.xy*distortFactor, shadowMapRayProgress.z);

	if (abs(shadowPos.x) < 1.0-0.5/2048. && abs(shadowPos.y) < 1.0-0.5/2048){

		shadowPos = shadowPos * vec3(0.5, 0.5, 0.5/6.0) + 0.5;

		#ifdef TRANSLUCENT_COLORED_SHADOWS
			shadowColor = vec3(shadow2D(shadowtex0, shadowPos).x);

			if(shadow2D(shadowtex1, shadowPos).x > shadowPos.z && shadowColor.x < 1.0){
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
	float increment, 
	vec3 start, 
	vec3 shadowMapRayStartPos, 
	vec3 shadowMapRayProgress,
	float flatPhase,
	inout float sunPhase
){
	vec3 shadows = vec3(1.0);
	shadows *= sampleShadowmapVL(start, shadowMapRayStartPos, shadowMapRayProgress, increment);
	
	float cloudShadow = GetCloudShadow(rayProgress, sunVector);
	shadows *= cloudShadow;

	return shadows;
}

// Entry

vec4 GetVolumetricFog(
	in vec3 viewPos,
	in vec2 dither,
	in vec3 sunVector,
	
	in vec3 LightColor,
	in vec3 AmbientColor,
	in vec3 AveragedAmbientColor,
	
	in float cloudPlaneDistance
){
	#ifndef TOGGLE_VL_FOG
		return vec4(0.0, 0.0, 0.0, 1.0);
	#endif
	
	int SAMPLECOUNT = VL_SAMPLES;

	// Project pixel position into projected shadowmap space.
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
	vec3 rayStartPos = playerPos - gbufferModelViewInverse[3].xyz;

	vec3 localRayStartPos = rayStartPos;
	float localRayLength = length(localRayStartPos);
	localRayStartPos *= min(localRayLength, 64.0)/localRayLength;
	localRayLength = length(localRayStartPos);
	vec3 localRayProgress = vec3(0.0);

	// Shadow Map
	vec3 shadowViewPos = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
	shadowViewPos = diagonal3(shadowProjection) * shadowViewPos + shadowProjection[3].xyz;

	vec3 start = toShadowSpaceProjected(vec3(0.0));
	vec3 shadowMapRayStartPos = shadowViewPos - start;

	float rayLength = length(rayStartPos);

	#ifdef USING_LOD_MOD
		float maxLength = min(rayLength, max(far, LOD_RENDERDISTANCE))/rayLength;
	#else
		float maxLength = min(rayLength, far)/rayLength;
	#endif

	shadowMapRayStartPos *= maxLength;
	rayStartPos *= maxLength;

	rayLength = length(rayStartPos);

	vec3 rayProgress = vec3(0.0);
	vec3 shadowMapRayProgress = vec3(0.0);
	float expFactor = 11.0;

	float SdotV = dot(sunVector, normalize(playerPos));
	float rayleighPhase = phaseRayleigh(SdotV);
	float sunPhase = fogPhase(SdotV) * 5.0;
	float flatPhase = clamp(SdotV * 0.5 + 0.5, 0.0, 1.0);

	float absorbance = 1.0;
	float localAbsorbance = 1.0;
	float LPVAbsorb = 1.0;
	vec3 airAbsorbance = vec3(1.0);
	
	float indoors = clamp(eyeBrightnessSmooth.y / 240.0, 0, 1);

	vec3 masterLightColor = LightColor * 3.5;
	vec3 ambientLightColor = AmbientColor * 1.5;
	
	float saturationIntensity = 0.5 + SdotV * 0.25;
	masterLightColor = saturateColor(masterLightColor, clamp(saturationIntensity, 0.2, 1.0));
	ambientLightColor = saturateColor(ambientLightColor, clamp(saturationIntensity, 0.2, 1.0));

	vec3 localFogColor = parameters.localFogColor.rgb;
	vec3 localFogColor_lightCol = localFogColor * dot(masterLightColor, vec3(0.33333));
	vec3 localFogColor_ambientCol = localFogColor * dot(ambientLightColor, vec3(0.33333));

	float skyPhase = 0.5 + pow(1.0 - pow(1.0 - clamp(normalize(playerPos).y * 0.5 + 0.5, 0.0, 1.0), 2.0), 5.0) * 2.0;

	vec3 rayleighCoeffs = vec3(sky_coefficientRayleighR*1e-6, sky_coefficientRayleighG*1e-5, sky_coefficientRayleighB*1e-5);
	vec3 mieCoeffs = vec3(sky_coefficientMieR*1e-6, sky_coefficientMieG*1e-6, sky_coefficientMieB*1e-6);

	// this is to reduce sampling problems with shadows when thick local fog is used.
	float localFogExists = (parameters.localFog.x > 0.0 || parameters.localFog.y > 0.0) ? 1.0 : 0.0;

	vec3 color = vec3(0.0);
	
	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither.x)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither.y)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);
	
		#if (defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2)
			float kill = length(d*rayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#else
			float kill = 1.0;
		#endif

		rayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + d*rayStartPos;
		localRayProgress = gbufferModelViewInverse[3].xyz + cameraPosition + d*localRayStartPos;
		
		#ifdef FAKE_PLANET
			LightColor = getPlanetAbsorb(rayProgress, WsunVec, colortex4);
		#endif

		vec3 shadows = getShadows(mix(rayProgress, localRayProgress, localFogExists), sunVector, d, start, shadowMapRayStartPos, shadowMapRayProgress, flatPhase, sunPhase);
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			vec3 lightningFlash = createLightningPointLight(rayProgress - cameraPosition, lightningBoltPosition.xyz, 1.0, 1.0) * indoors;
		#endif
		
		/// ATMOSOPHERE
		float planetVolume = clamp(1.0 - length((rayProgress-cameraPosition) - vec3(0.0, 250.0, 0.0)) / 2500.0, 0.0,1.0);
		#ifdef USING_LOD_MOD
			vec2 airCoef = exp2(-max(rayProgress.y-62.0,0.0)/vec2(8.0e3, 1.2e3)*vec2(6.,7.0)) * planetVolume * 12.5 * Haze_amount;
		#else
			vec2 airCoef = exp2(-max(rayProgress.y-62.0,0.0)/vec2(8.0e3, 1.2e3)*vec2(6.,7.0)) * planetVolume * 25.0 * Haze_amount;
		#endif

		vec3 rayleigh = rayleighCoeffs * airCoef.x;
		vec3 mie = mieCoeffs * (airCoef.y + min(Haze_amount, 1.0));
		vec3 airDensity = kill * (rayleigh + mie);
		vec3 airDensityPhased = rayleighPhase * rayleigh + sunPhase*mie;
		vec3 airVolumeCoeff = exp(-airDensity * dd * rayLength);
		vec3 airLighting = masterLightColor * shadows*sunPhase * airDensityPhased + AveragedAmbientColor * airDensity * 0.666;
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			airLighting += lightningFlash * airDensity;
		#endif
		
		color += (airLighting - airLighting * airVolumeCoeff) / (airDensity+1e-6)*airAbsorbance;

		/// GLOBAL FOG
		float fogDensity = kill * getFogDensities(rayProgress, 0.0);
		float fogVolumeCoeff = exp(-fogDensity * dd * rayLength);
		vec3 fogLighting = masterLightColor * sunPhase*shadows + ambientLightColor * skyPhase;
		
		#if defined LIGHTNING_FLASH && defined LIGHTNINGFLASH_VL
			fogLighting += lightningFlash;
		#endif
		
		color += (fogLighting - fogLighting * fogVolumeCoeff) * absorbance;

		/// LOCAL FOG
		#if (defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2)
			kill = length(d * localRayStartPos) > cloudPlaneDistance ? 0.0 : 1.0;
		#endif

		float localEffectDensity = kill * getLocalEffectDensity(localRayProgress);

		#ifdef EXCLUDE_WRITE_TO_LUT
			localEffectDensity *= indoors;
		#endif

		float localFogVolumeCoeff = exp(-localEffectDensity * dd * localRayLength);
		vec3 localFogLighting = localFogColor_lightCol * shadows * sunPhase + localFogColor_ambientCol * skyPhase;
		
		color += (localFogLighting - localFogLighting * localFogVolumeCoeff) * localAbsorbance;
		
		localAbsorbance *= localFogVolumeCoeff;
		airAbsorbance *= airVolumeCoeff * fogVolumeCoeff * localFogVolumeCoeff;
		absorbance *= fogVolumeCoeff * localFogVolumeCoeff * dot(airVolumeCoeff, vec3(0.33333));
	}

	// float minFogLuma = 0.5; 
	// float fogLuma = dot(color, vec3(0.2126, 0.7152, 0.0722)); 
	// float grayFactor = smoothstep(minFogLuma, minFogLuma + 0.1, fogLuma); 
	// color = mix(vec3(minFogLuma), color, grayFactor);

	return vec4(color, absorbance);
}
