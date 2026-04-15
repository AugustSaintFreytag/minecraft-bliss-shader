#define ANTIALIASING_RELATED_SETTINGS
#define NETHER_RELATED_SETTINGS
#define END_RELATED_SETTINGS
#define SKY_RELATED_SETTINGS
#define ATMOSPHERE_COEFF_RELATED_SETTINGS
#define DISTANCE_BASED_FOG_RELATED_SETTINGS
#define SHADOWMAP_CONSTANT_RELATED_SETTINGS
#define AMBIENT_LIGHT_RELATED_SETTINGS
#define SEASONS_RELATED_SETTINGS
#define VOLUMETRIC_CLOUD_RELATED_SETTINGS
#define VOLUMETRIC_FOG_RELATED_SETTINGS
#define WATER_RELATED_SETTINGS

#define EXCLUDE_WRITE_TO_LUT

#include "/lib/settings.glsl"

flat varying vec4 lightCol;
flat varying vec3 averageSkyCol;
flat varying vec3 averageSkyCol_Clouds;

uniform sampler2D noisetex;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex10;
uniform sampler2D colortex12;
uniform sampler2D colortex14;
uniform sampler2D colortex15;

flat varying vec3 WsunVec;

uniform vec3 sunVec;
uniform float sunElevation;

uniform float far;
uniform float near;
uniform float dhFarPlane;
uniform float dhNearPlane;

uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;

#if defined VIVECRAFT
	uniform bool vivecraftIsVR;
	uniform vec3 vivecraftRelativeMainHandPos;
	uniform vec3 vivecraftRelativeOffHandPos;
	uniform mat4 vivecraftRelativeMainHandRot;
	uniform mat4 vivecraftRelativeOffHandRot;
#endif

uniform int frameCounter;
uniform float frameTimeCounter;

uniform vec2 texelSize;

uniform float viewHeight;
uniform float viewWidth;

uniform int isEyeInWater;
uniform float rainStrength;
uniform ivec2 eyeBrightnessSmooth;
uniform float eyeAltitude;
uniform float caveDetection;
uniform float skyLightLevelSmooth;
uniform float waterEnteredAltitude;

#include "/lib/macro_lod_mod.glsl"
#include "/lib/util.glsl"

vec4 blueNoise(vec2 coord){
  return texelFetch(colortex6, ivec2(coord)%512 , 0) ;
}

vec2 R2_samples(int n){
	vec2 alpha = vec2(0.75487765, 0.56984026);
	return fract(alpha * n);
}

uniform int hideGUI;

// Defines

#define DHVLFOG
#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)
#define  projMAD(m, v) (diagonal3(m) * (v) + (m)[3].xyz)

#include "/lib/color_transforms.glsl"
#include "/lib/color_dither.glsl"
#include "/lib/projections.glsl"
#include "/lib/res_params.glsl"
#include "/lib/sky_gradient.glsl"
#include "/lib/Shadow_Params.glsl"
#include "/lib/waterBump.glsl"
#include "/lib/TAA_jitter.glsl"
#include "/lib/dh_projections.glsl"
#include "/lib/dh_occlusion.glsl"

float DH_ld(float dist) {
    return (2.0 * dhNearPlane) / (dhFarPlane + dhNearPlane - dist * (dhFarPlane - dhNearPlane));
}
float DH_inv_ld (float lindepth){
	return -((2.0*dhNearPlane/lindepth)-dhFarPlane-dhNearPlane)/(dhFarPlane-dhNearPlane);
}

float linearizeDepthFast(const in float depth, const in float near, const in float far) {
    return (near * far) / (depth * (near - far) + far);
}

#define IS_LPV_ENABLED

#if defined LPV_VL_FOG_ILLUMINATION && defined IS_LPV_ENABLED
	#ifdef IS_LPV_ENABLED
		#extension GL_ARB_shader_image_load_store: enable
		#extension GL_ARB_shading_language_packing: enable
	#endif

	#ifdef IS_LPV_ENABLED
		uniform usampler1D texBlockData;
		uniform sampler3D texLpv1;
		uniform sampler3D texLpv2;
	#endif

	#ifdef IS_LPV_ENABLED
		#include "/lib/hsv.glsl"
		#include "/lib/lpv_common.glsl"
		#include "/lib/lpv_render.glsl"
	#endif
	vec4 raymarchLPV(
		in vec3 viewPos,
		in float dither
	){
		#if !defined LPV_VL_FOG_ILLUMINATION
			return vec3(0.0);
		#endif

		int SAMPLECOUNT = 8;
		vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
		vec3 LPVrayStartPos = playerPos - gbufferModelViewInverse[3].xyz;
		
		// Ensure the max marching distance is the voxel distance, or the render distance if the voxels go farther than it.
		float LPVRayLength = length(LPVrayStartPos);
		#if LPV_SIZE == 8
			LPVrayStartPos *= min(LPVRayLength, min(256.0,far))/LPVRayLength;
		#elif LPV_SIZE == 7
			LPVrayStartPos *= min(LPVRayLength, min(128.0,far))/LPVRayLength;
		#elif LPV_SIZE == 6
			LPVrayStartPos *= min(LPVRayLength, min(64.0,far))/LPVRayLength;
		#endif
		LPVRayLength = length(LPVrayStartPos);

		vec3 LPVrayProgress = vec3(0.0);
		vec4 color = vec4(0.0,0.0,0.0,1.0);
		float expFactor = 11.0;

		for (int i = 0; i < SAMPLECOUNT; i++) {
			float d = (pow(expFactor, float(i+dither)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
			float dd = pow(expFactor, float(i+dither)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

			LPVrayProgress = gbufferModelViewInverse[3].xyz + d*LPVrayStartPos;

			vec3 lpvPos = GetLpvPosition(LPVrayProgress);

        	float fadeLength = 10.0; // in blocks
        	vec3 cubicRadius = clamp(	min(((LpvSize3-1.0) - lpvPos)/fadeLength,      lpvPos/fadeLength) ,0.0,1.0);
        	float LpvFadeF = cubicRadius.x*cubicRadius.y*cubicRadius.z;

			if(LpvFadeF < 0.01) break;

			vec3 sampleColor = SampleLpvLinear(lpvPos).rgb;
			#ifdef VANILLA_LIGHTMAP_MASK
				vec3 lighting = sampleColor * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 25. * exp(-10 * (1.0-luma(sampleColor)));
			#else
				vec3 lighting = sampleColor * LPV_VL_FOG_ILLUMINATION_BRIGHTNESS * 25. * exp(-5 * (1.0-luma(sampleColor)));
			#endif

			float density = 0.0001;
			float volumeCoeff = exp(-dd*density*LPVRayLength);

			color.rgb += (lighting - lighting * volumeCoeff) * color.a;
			color.a *= volumeCoeff;
		}
		return color.rgba;
	}

#endif

uniform float nightVision;

#define LIGHTNINGFLASH_VL
#include "/lib/lightning_stuff.glsl"

#ifdef OVERWORLD_SHADER
	const bool shadowHardwareFiltering = true;
	uniform sampler2DShadow shadow;

	#ifdef TRANSLUCENT_COLORED_SHADOWS
		uniform sampler2D shadowcolor0;
		uniform sampler2DShadow shadowtex0;
		uniform sampler2DShadow shadowtex1;
	#endif
	
	flat varying vec3 refractedSunVec;

	
	#include "/lib/scene_controller.glsl"


	#define TIMEOFDAYFOG

	#include "/lib/volumetricClouds.glsl"
	#include "/lib/climate_settings.glsl"
	#include "/lib/overworld_fog.glsl"
#endif

#ifdef NETHER_SHADER
	#include "/lib/nether_fog.glsl"
#endif
#ifdef END_SHADER
	#include "/lib/end_fog.glsl"
#endif

#define fsign(a)  (clamp((a)*1e35,0.,1.)*2.-1.)


/*
from https://blog.demofox.org/2022/01/01/interleaved-gradient-noise-a-different-kind-of-low-discrepancy-sequence/
Copyright 2019 Alan Wolfe

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
float interleaved_gradientNoise_temporal(){
	vec2 coord = gl_FragCoord.xy + 5.588238 * float(frameCounter%64);
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y)) ;
	return noise;
}

float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

float blueNoise(){
  return fract(texelFetch(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 * frameCounter );
}

float R2_dither(){
	vec2 coord = gl_FragCoord.xy + (frameCounter%40000) * 2.0;
	vec2 alpha = vec2(0.75487765, 0.56984026);
	
	return fract(alpha.x * coord.x + alpha.y * coord.y);
}

vec4 waterVolumetrics(vec3 rayStart, vec3 rayEnd, float rayLength, vec2 dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float sunShadow, float VdotL, vec3 LPV){
	int spCount = 8;

	vec3 start = toShadowSpaceProjected(rayStart);
	vec3 end = toShadowSpaceProjected(rayEnd);
	vec3 dV = (end-start);

	// Limit ray length at 32 blocks for performance and reducing integration error.
	float maxZ = min(rayLength,32.0)/(1e-8+rayLength);
	
	dV *= maxZ;
	rayLength *= maxZ;

	vec3 dVWorld = mat3(gbufferModelViewInverse) * (rayEnd - rayStart) * maxZ;

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);
	
	#ifdef OVERWORLD_SHADER
		float lowlightlevel  = clamp(eyeBrightnessSmooth.y / 240.0, 0.1, 1.0);
		float phase = fogPhase(VdotL) * 5.0;
	#else
		float lowlightlevel  = 1.0;
		float phase = 0.0;
	#endif

	float downwardAbsorbtionBias = -normalize(dVWorld).y;
	downwardAbsorbtionBias = clamp(downwardAbsorbtionBias + 0.333, 0.0, 1.0);
	downwardAbsorbtionBias = pow(1.0 - pow(1.0 - downwardAbsorbtionBias, 2.0), 2.0);
	downwardAbsorbtionBias *= 15.0;

	float expFactor = 11.0;
	for (int i=0; i < spCount; i++) {
		float d = (pow(expFactor, float(i + dither.x) / float(spCount)) / expFactor - 1.0 / expFactor) / (1 - 1.0 / expFactor);		// exponential step position (0-1)
		float dd = pow(expFactor, float(i + dither.y) / float(spCount)) * log(expFactor) / float(spCount)/(expFactor - 1.0);		// step length (derivative)
		
		vec3 progressW = gbufferModelViewInverse[3].xyz + cameraPosition + d * dVWorld;
		
		float distanceFromWaterSurface = max(-(progressW.y - waterEnteredAltitude), 0.0);

		vec3 shadowColor = vec3(1.0);

		#ifdef OVERWORLD_SHADER
			vec3 spPos = start.xyz + dV * d;

			// Project into biased shadow map space.
			#ifdef DISTORT_SHADOWMAP
				float distortFactor = calcDistort(spPos.xy);
			#else
				float distortFactor = 1.0;
			#endif

			vec3 pos = vec3(spPos.xy * distortFactor, spPos.z);
			if (abs(pos.x) < 1.0 - 0.5 / 2048.0 && abs(pos.y) < 1.0 - 0.5 / 2048.0) {
				pos = pos*vec3(0.5,0.5,0.5/6.0)+0.5;

				#ifdef TRANSLUCENT_COLORED_SHADOWS
					sh = vec3(shadow2D(shadowtex0, pos).x);

					if(shadow2D(shadowtex1, pos).x > pos.z && shadowColor.x < 1.0){
						vec4 translucentShadow = texture(shadowcolor0, pos.xy);

						if (translucentShadow.a < 0.9) {
							shadowColor = normalize(translucentShadow.rgb + 0.0001);
						}
					}
				#else
					shadowColor = vec3(shadow2D(shadow, pos).x);
				#endif
			}

			shadowColor *= GetCloudShadow(progressW, WsunVec * lightCol.a);

		#endif

		float bubble = exp2(-10.0 * clamp(1.0 - length(d * dVWorld) / 16.0, 0.0, 1.0));
		float caustics = max(max(waterCaustics(progressW, WsunVec, -(progressW.y - waterEnteredAltitude)), phase * 0.5) * mix(0.5, 1.5, bubble), phase);

		vec3 sunAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface / abs(WsunVec.y)));
		vec3 waterAbsorbance = exp(-waterCoefs * (distanceFromWaterSurface + downwardAbsorbtionBias));

		vec3 directLight = lightSource * phase * caustics * sunAbsorbance;
		vec3 indirectLight = ambient * waterAbsorbance;
		// vec3 indirectLight = ambient * (0.25 + (1.0 - sunShadow) * 4.0) * waterAbsorbance;


		vec3 light = (indirectLight + directLight + LPV) * scatterCoef;
		
		vec3 volumeCoeff = exp(-waterCoefs * length(dd * dVWorld));
		vL += (light - light * volumeCoeff) / waterCoefs * absorbance;

		absorbance *= volumeCoeff;

	}

	return vec4(vL, dot(absorbance,vec3(0.335)));
}

vec4 waterVolumetricsTranslucent(vec3 rayStart, vec3 rayEnd, float estEndDepth, float estSunDepth, float rayLength, float dither, vec3 waterCoefs, vec3 scatterCoef, vec3 ambient, vec3 lightSource, float sunShadow, float VdotL){
	int spCount = rayMarchSampleCount;

	vec3 start = toShadowSpaceProjected(rayStart);
	vec3 end = toShadowSpaceProjected(rayEnd);
	vec3 dV = (end-start);

	// Limit ray length at 32 blocks for performance and reducing integration error.
	float maxZ = min(rayLength,12.0)/(1e-8+rayLength);
	dV *= maxZ;
	rayLength *= maxZ;
	estEndDepth *= maxZ;
	estSunDepth *= maxZ;
	
	vec3 wpos = mat3(gbufferModelViewInverse) * rayStart  + gbufferModelViewInverse[3].xyz;
	vec3 dVWorld = (wpos - gbufferModelViewInverse[3].xyz);
	
    #ifdef OVERWORLD_SHADER
		float phase = fogPhase(VdotL) * 5.0;
	#else
		float phase = 1.0;
	#endif

	vec3 absorbance = vec3(1.0);
	vec3 vL = vec3(0.0);
	
	float expFactor = 11.0;
	vec3 sh = vec3(1.0);

	// Do this outside raymarch loop, masking the water surface is good enough.
	#if defined OVERWORLD_SHADER
		float cloudShadow = GetCloudShadow(wpos + cameraPosition, WsunVec);
	#else
		float cloudShadow = 1.0;
	#endif
	
	float downwardAbsorbtionBias = -normalize(dVWorld).y;
	downwardAbsorbtionBias = clamp(downwardAbsorbtionBias - 0.333, 0.0, 1.0);
	downwardAbsorbtionBias = pow(1.0 - pow(1.0-downwardAbsorbtionBias, 2.0), 2.0);
	downwardAbsorbtionBias *= 15.0;

	for (int i=0; i < spCount; i++) {
		float d = (pow(expFactor, float(i + dither) / float(spCount)) / expFactor - 1.0 / expFactor) / (1 - 1.0 / expFactor);
		float dd = pow(expFactor, float(i + dither) / float(spCount)) * log(expFactor) / float(spCount) / (expFactor - 1.0);
		vec3 progressW = gbufferModelViewInverse[3].xyz + cameraPosition + d * dVWorld;

		#ifdef OVERWORLD_SHADER
			vec3 spPos = start.xyz + dV * d;

			// Project into biased shadow map space.
			#ifdef DISTORT_SHADOWMAP
				float distortFactor = calcDistort(spPos.xy);
			#else
				float distortFactor = 1.0;
			#endif

			vec3 pos = vec3(spPos.xy * distortFactor, spPos.z);
			if (abs(pos.x) < 1.0 - 0.5 / 2048.0 && abs(pos.y) < 1.0 - 0.5 / 2048.0){
				pos = pos*vec3(0.5, 0.5, 0.5 / 6.0) + 0.5;
				// sh = shadow2D( shadow, pos).x;

				#ifdef TRANSLUCENT_COLORED_SHADOWS
					sh = vec3(shadow2D(shadowtex0, pos).x);

					if(shadow2D(shadowtex1, pos).x > pos.z && sh.x < 1.0){
						vec4 translucentShadow = texture(shadowcolor0, pos.xy);
						if(translucentShadow.a < 0.9) sh = normalize(translucentShadow.rgb + 0.0001);
					}
				#else
					sh = vec3(shadow2D(shadow, pos).x);
				#endif
			}
		#endif

		vec3 sunAbsorbance = exp(-waterCoefs * estSunDepth * d);
		vec3 ambientAbsorbance = exp(-waterCoefs * (estEndDepth * d + downwardAbsorbtionBias));

		vec3 directLight = lightSource * sh * cloudShadow * phase * sunAbsorbance;
		// vec3 indirectLight = ambient * (0.25 + (1.0 - sunShadow) * 4) * ambientAbsorbance;
		vec3 indirectLight = ambient * ambientAbsorbance;

		vec3 light = (directLight + indirectLight) * scatterCoef;
		
		vec3 volumeCoeff = exp(-waterCoefs * dd * rayLength);
		vL += (light - light * volumeCoeff) / waterCoefs * absorbance;
		absorbance *= volumeCoeff;
	}
	
    return vec4(vL, dot(absorbance,vec3(0.333333)));
}

float fogPhase2(float lightPoint){
	float linear = 1.0 - clamp(lightPoint*0.5+0.5,0.0,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	return exponential;
}

// encoding by jodie
float encodeVec2(vec2 a){
    const vec2 constant1 = vec2(1.0, 256.0) / 65535.0;
    vec2 temp = floor(a * 255.0);
	return temp.x * constant1.x + temp.y * constant1.y;
}

vec2 decodeVec2(float a){
    const vec2 constant1 = 65535.0 / vec2( 256.0, 65536.0);
    const float constant2 = 256.0 / 255.0;
    return fract(a * constant1) * constant2;
}

float convertHandDepth(float depth) {
    float ndcDepth = depth * 2.0 - 1.0;
    ndcDepth /= MC_HAND_DEPTH;

    return ndcDepth * 0.5 + 0.5;
}

#if defined DISTANT_HORIZONS
	
#else
	float sampleVolumetricOcclusion(in vec3 viewPos, in vec3 lightDir, float noise, float vanillaDepth){
		return 1.0;
	}
#endif

ivec2 normalizeTexturePos(vec2 pos) {
	vec2 uv = (pos / vec2(viewWidth, viewHeight));
	ivec2 size = textureSize(colortex4, 0);
	
	ivec2 ipos = ivec2(uv * vec2(size));
	ipos = clamp(ipos, ivec2(0), size - ivec2(1));

	return ipos;
}

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	/* RENDERTARGETS:0,13 */

	gl_FragData[1] = vec4(0.0, 0.0, 0.0, 1.0);	
	
	float noise_2 = blueNoise();
	float noise_1 = interleaved_gradientNoise_temporal();
	vec2 bnoise = blueNoise(gl_FragCoord.xy).rg;

	int seed = frameCounter % 40000;
	vec2 r2_sequence = R2_samples(seed).xy * 5.0;
	vec2 BN = fract(r2_sequence + bnoise);

	vec2 rawTexelCoord = floor(gl_FragCoord.xy - 0.5) / VL_RENDERING_RESOLUTION_SCALE * texelSize;
	ivec2 nTexelCoord = normalizeTexturePos(rawTexelCoord);
	
	ivec2 rawTexelPos = ivec2(rawTexelCoord / texelSize);
	ivec2 nTexelPos = normalizeTexturePos(rawTexelPos);

	#ifdef OVERWORLD_SHADER
		vec2 lightmap = decodeVec2(texelFetch(colortex14, rawTexelPos, 0).x);
	#else
		vec2 lightmap = decodeVec2(texelFetch(colortex14, rawTexelPos, 0).a);
		lightmap.y = 1.0;
	#endif

	float alpha = texelFetch(colortex7, rawTexelPos, 0).a;
	float blendedAlpha = texelFetch(colortex2, rawTexelPos, 0).a;

	bool isInWater = alpha > 0.99;

	float z0 = texelFetch(depthtex0, rawTexelPos, 0).x;
	float z1 = texelFetch(depthtex1, rawTexelPos, 0).x;

	#ifdef USING_LOD_MOD
		float DH_z0 = texelFetch(LOD_DEPTHTEX0, rawTexelPos, 0).x;
		float DH_z1 = texelFetch(LOD_DEPTHTEX1, rawTexelPos, 0).x;
	#else
		float DH_z0 = 0.0;
		float DH_z1 = 0.0;
	#endif

	bool isSky = min(z0, DH_z0) >= 1.0;
	
	vec3 viewPos0 = toScreenSpace_DH(rawTexelCoord, z0, DH_z0);
	vec3 viewPos1 = toScreenSpace_DH(rawTexelCoord, z1, DH_z1);
	vec3 cameraWorldPos = gbufferModelViewInverse[3].xyz + cameraPosition;
	bool clampAirFogToWaterSurface = isEyeInWater != 1 && isInWater;
	vec3 airFogViewPos = clampAirFogToWaterSurface ? viewPos1 : viewPos0;
	vec3 waterFogViewPos = viewPos0;
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos0 + gbufferModelViewInverse[3].xyz;
	vec3 playerPos_normalized = normalize(playerPos);

	if (isEyeInWater == 1) {
		vec3 waterFogEndWorldPos = cameraWorldPos + mat3(gbufferModelViewInverse) * waterFogViewPos;
		float startDistanceFromSurface = cameraWorldPos.y - waterEnteredAltitude;
		float endDistanceFromSurface = waterFogEndWorldPos.y - waterEnteredAltitude;

		if (startDistanceFromSurface < 0.0 && endDistanceFromSurface > 0.0) {
			float surfaceIntersection = clamp((-startDistanceFromSurface) / max(endDistanceFromSurface - startDistanceFromSurface, 1e-4), 0.0, 1.0);
			waterFogViewPos *= surfaceIntersection;
		}
	}

	float Vdiff = distance(viewPos1, viewPos0);
	float estimatedDepth = Vdiff * abs(playerPos_normalized.y);
	float estimatedSunDepth = Vdiff / abs(WsunVec.y); // Assuming water plane

	float dirtAmount = Dirt_Amount;
	vec3 waterEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	vec3 dirtEpsilon = vec3(Dirt_Absorb_R, Dirt_Absorb_G, Dirt_Absorb_B);
	vec3 totEpsilon = vec3(Water_Absorb_R, Water_Absorb_G, Water_Absorb_B);
	vec3 scatterCoef = dirtAmount * vec3(Dirt_Scatter_R, Dirt_Scatter_G, Dirt_Scatter_B) / PI;

	vec3 baseDirectLightColor = vec3(DIRECTLIGHT_FOG_R, DIRECTLIGHT_FOG_G, DIRECTLIGHT_FOG_B);
	vec3 baseIndirectLightColor = vec3(INDIRECTLIGHT_FOG_R, INDIRECTLIGHT_FOG_G, INDIRECTLIGHT_FOG_B);

	vec3 directLightColor = baseDirectLightColor * lightCol.rgb / 2400.0;

	vec3 indirectLightColor = baseIndirectLightColor * averageSkyCol / 1200.0;
	vec3 indirectLightColor_dynamic = averageSkyCol_Clouds / 1200.0;
	
    vec3 indirectLight = indirectLightColor_dynamic * skyLightLevelSmooth * ambient_brightness; 
    float minimumLightAmount = 0.02 * nightVision + 0.005 * mix(MINIMUM_INDOOR_LIGHT, MINIMUM_OUTDOOR_LIGHT, skyLightLevelSmooth);
    indirectLight += vec3(1.0) * minimumLightAmount;
	
	vec3 indirectLight_fog = indirectLightColor * skyLightLevelSmooth * ambient_brightness; 
    indirectLight_fog += vec3(1.0) * minimumLightAmount;

	#if defined LPV_VL_FOG_ILLUMINATION
		vec4 LPV_ILLUMINATION = raymarchLPV(viewPos0, R2_dither());
	#else
		vec4 LPV_ILLUMINATION = vec4(0.0, 0.0, 0.0, 1.0);
	#endif

	#if defined OVERWORLD_SHADER && defined DH_VOLUMETRIC_OCCLUSION
		vec3 lightDir = normalize(sunVec * lightCol.a);
		bool sunShadowSourceIsLOD = clampAirFogToWaterSurface ? z1 >= 1.0 : z0 >= 1.0;

		float sunShadow = getSunShadow(airFogViewPos, lightDir, BN.x, false, sunShadowSourceIsLOD);
		// DepthSample depthSample = getDepthSample(viewToClipSpace(viewPos0).xy);
		// float depth = depthSample.value;

		// gl_FragData[0].rgb = vec3(blendedAlpha, 0, 0);
		// return;

		// gl_FragData[0].rgb = vec3(1.0, 0.1, 0.9);
		// gl_FragData[0].rgb = vec3(1.0 - sunShadow);
		// return;

		// Sun Angle Factor Debugging Display
		// if (gl_FragCoord.x < 100 && gl_FragCoord.y < 100) {
		// 	float sunAngleFactor = getSunAngleDisocclusionFactor();
		// 	vec3 sunAngleColor = vec3(sunAngleFactor * 0.05, 0.0, sunAngleFactor);

		// 	if (sunAngleFactor > 0.99) {
		// 		sunAngleColor.g = 1.0;
		// 	}
			
		// 	gl_FragData[0].rgb = sunAngleColor;
		// 	return;
		// }
	#else
		float sunShadow = 0.0;
	#endif

	float daylightFactor = clamp(sunElevation * 2.0, 0.0, 1.0);
	float cloudPlaneDistance = 0.0;

	#if defined OVERWORLD_SHADER
		vec4 volumetricClouds = GetVolumetricClouds(viewPos0, BN, WsunVec, directLightColor, indirectLightColor, cloudPlaneDistance);
	  	
  		#if defined OVERWORLD_SHADER && defined CAVE_FOG && defined CAVE_FOG_DARKEN_SKY
  		  if (isEyeInWater == 0 && eyeAltitude < 1500) {
  		    float skyhole = pow(clamp(1.0 - pow(max(playerPos_normalized.y - 0.6, 0.0) * 5.0, 2.0), 0.0, 1.0), 2) * caveDetection;

			volumetricClouds.rgb *= 1.0 - skyhole;
			volumetricClouds.a = mix(volumetricClouds.a, 1.0, skyhole);
  		  }
  		#endif

		if (isEyeInWater == 1) {
			sunShadow = 0.0;
		}

		vec4 volumetricFog = GetVolumetricFog(airFogViewPos, vec2(noise_1), WsunVec, sunShadow, directLightColor, indirectLight_fog, indirectLight, cloudPlaneDistance);

		if (isSky) {
			volumetricFog.rgb *= 1 + (daylightFactor * 4.0);
		}

		#if defined LPV_VL_FOG_ILLUMINATION
			volumetricFog.a *= LPV_ILLUMINATION.a;
			volumetricFog.rgb = volumetricFog.rgb * LPV_ILLUMINATION.a + LPV_ILLUMINATION.rgb;
		#endif

		volumetricFog = vec4(volumetricClouds.rgb * volumetricFog.a + volumetricFog.rgb, volumetricFog.a * volumetricClouds.a);
	#endif

	#if defined NETHER_SHADER || defined END_SHADER
		vec4 volumetricFog = GetVolumetricFog(viewPos0, noise_1, noise_1);
		
		#if defined LPV_VL_FOG_ILLUMINATION
			volumetricFog.a *= LPV_ILLUMINATION.a;
			volumetricFog.rgb = volumetricFog.rgb * LPV_ILLUMINATION.a + LPV_ILLUMINATION.rgb;
		#endif
	#endif

	if (isEyeInWater == 1){
		vec4 underWaterFog =  waterVolumetrics(vec3(0.0), waterFogViewPos, length(waterFogViewPos), vec2(noise_1), totEpsilon, scatterCoef, indirectLightColor_dynamic, directLightColor, sunShadow, dot(normalize(waterFogViewPos), normalize(sunVec* lightCol.a)), LPV_ILLUMINATION.rgb);
		volumetricFog = vec4(underWaterFog.rgb, 1.0);
	}
	
	vec4 clampedVolumetricFog = clamp(volumetricFog, 0.0, 68000.0);

	// Fog Color
	gl_FragData[0] = clampedVolumetricFog;

	// Bloomy Fog Mask
	gl_FragData[1].a = volumetricFog.a;
	
	if(blendedAlpha > 0.0 || isInWater){
		// Translucents
		vec4 translucentVolumetricClouds = volumetricClouds;
		vec4 translucentVolumetricFog = vec4(0.0, 0.0, 0.0, 1.0);

		#if defined OVERWORLD_SHADER
			translucentVolumetricClouds = GetVolumetricClouds(viewPos1, vec2(noise_1), WsunVec, directLightColor, indirectLightColor, cloudPlaneDistance);
			translucentVolumetricFog = GetVolumetricFog(viewPos1, vec2(noise_1), WsunVec, sunShadow, directLightColor, indirectLight_fog, indirectLight, cloudPlaneDistance);
			translucentVolumetricFog = vec4(translucentVolumetricClouds.rgb * translucentVolumetricFog.a + translucentVolumetricFog.rgb, translucentVolumetricFog.a * translucentVolumetricClouds.a);
		#endif
		
		#if defined NETHER_SHADER || defined END_SHADER
			translucentVolumetricFog = GetVolumetricFog(viewPos1, noise_1, noise_1);
		#endif
		
		gl_FragData[1] = clamp(translucentVolumetricFog, 0.0, 68000.0);

		if(isInWater && isEyeInWater != 1) {
			vec4 waterVolumetricFog = waterVolumetricsTranslucent(viewPos0, viewPos1, estimatedDepth, estimatedSunDepth, Vdiff, noise_1, totEpsilon, scatterCoef, indirectLight, directLightColor, sunShadow, dot(normalize(viewPos0), normalize(sunVec * lightCol.a)));
			vec4 waterVolumetricFogDistant = translucentVolumetricFog * vec4(vec3(0.5), 1.0);

			float distanceFactor = smoothstep(0.0, far * 0.5, far - length(viewPos1));
			waterVolumetricFog = mix(waterVolumetricFogDistant, waterVolumetricFog, clamp(distanceFactor, 0.0, 1.0));

			gl_FragData[1] = clamp(waterVolumetricFog, 0.0, 65000.0);
		}
	}
}
