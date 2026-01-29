#define ANTIALIASING_RELATED_SETTINGS
#define EMISSION_RELATED_SETTINGS
#define SHADOWMAP_CONSTANT_RELATED_SETTINGS

#include "/lib/settings.glsl"
#include "/lib/util.glsl"
#include "/lib/DH_utils.glsl"

varying vec4 pos;
varying vec4 gcolor;
varying vec3 vNormal;

uniform vec2 texelSize;
uniform vec3 cameraPosition;
uniform sampler2D depthtex1;
uniform sampler2DShadow shadow;
uniform vec3 sunVec;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform mat4 gbufferModelViewInverse;
uniform int frameCounter;

flat varying vec3 averageSkyCol_Clouds;
flat varying vec3 lightSourceColor;

#define diagonal3(m) vec3((m)[0].x, (m)[1].y, m[2].z)

const float shadowDistortK = 1.8;
const float shadowDistortD0 = 0.04 + (1.0 - clamp(shadowDistance - 64.0, 0.0, 1.0)) * 0.1;
const float shadowDistortD1 = 0.61;
const float shadowDistortA = exp(shadowDistortD0);
const float shadowDistortB = (exp(shadowDistortD1) - shadowDistortA) * 150.0 / 128.0;

float calcDistort(vec2 worldpos){
	return 1.0 / (log(length(worldpos) * shadowDistortB + shadowDistortA) * shadowDistortK);
}

vec3 toShadowSpaceProjected(vec3 p3){
    p3 = mat3(gbufferModelViewInverse) * p3 + gbufferModelViewInverse[3].xyz;
    p3 = mat3(shadowModelView) * p3 + shadowModelView[3].xyz;
    p3 = diagonal3(shadowProjection) * p3 + shadowProjection[3].xyz;
	
    return p3;
}

float sampleShadow(vec3 viewPos) {
	vec3 shadowPos = toShadowSpaceProjected(viewPos);

	#ifdef DISTORT_SHADOWMAP
		float distortFactor = calcDistort(shadowPos.xy);
		shadowPos.xy *= distortFactor;
	#endif

	if (abs(shadowPos.x) < 1.0 - 0.5 / shadowMapResolution && abs(shadowPos.y) < 1.0 - 0.5 / shadowMapResolution){
		shadowPos = shadowPos * vec3(0.5, 0.5, 0.5 / 6.0) + 0.5;
		return shadow2D(shadow, shadowPos + vec3(0.0, 0.0, -0.0035)).x;
	}

	return 1.0;
}

// Utility

vec3 toLinear(vec3 sRGB){
	return sRGB * sRGB;
}

float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	return fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
}

// Main

/* RENDERTARGETS:2 */
void main() {
	if (gl_FragCoord.x * texelSize.x < 1.0 && gl_FragCoord.y * texelSize.y < 1.0 )	{
		vec3 viewPos = pos.xyz;
		vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
		float viewDist = length(playerPos);
		float falloff = exp(-10.0 * (1.0-clamp(1.0 - playerPos.y/5000.0,0.0,1.0)));

		#ifdef DH_OVERDRAW_PREVENTION
			float overdrawDistance = 16.0;
			float lodFadeLength = min(16.0, far);
			float lodStart = far - lodFadeLength;
			float drawStart = max(lodStart - overdrawDistance, 0.0);
			
			if(viewDist < drawStart || texture2D(depthtex1, gl_FragCoord.xy*texelSize).x < 1.0){ 
				discard; 
				return;
			}

			if (viewDist < drawStart + lodFadeLength) {
				float dither = interleaved_gradientNoise();
				float fade = clamp((viewDist - drawStart) / max(lodFadeLength, 0.0001), 0.0, 1.0);

				if (dither > fade) {
					discard;
					return;
				}
			}
		#endif

		vec3 albedo = toLinear(gcolor.rgb);
        
		// if(length(playerPos) < clamp(far -16  *4, 16, maxOverdrawDistance) || texture(depthtex1, gl_FragCoord.xy * texelSize).x < 1.0) { 
		// 	discard; 
		// 	return;
		// }
    #endif

		#ifdef DH_NOISE_TEXTURE
			albedo = applyNoise(vec4(albedo, 1.0), playerPos + cameraPosition, length(playerPos)).rgb;
		#endif

		vec3 ambientLightColor = averageSkyCol_Clouds / 900.0;
		float lightness = luma(ambientLightColor);
		vec3 skylightInfluence = mix(vec3(lightness), ambientLightColor, 0.2);

		#ifdef OVERWORLD_SHADER
			vec3 directLightColor = lightSourceColor / 2400.0;
			float NdotL = clamp(dot(normalize(vNormal), normalize(sunVec)), 0.0, 1.0);
			NdotL = clamp((-15.0 + NdotL * 255.0) / 240.0, 0.0, 1.0);
			float shadowFactor = sampleShadow(viewPos);
			vec3 directLight = directLightColor * NdotL * shadowFactor;
		#else
			vec3 directLight = vec3(0.0);
		#endif

		gl_FragData[0] = vec4(albedo * (skylightInfluence + directLight) * Emissive_Brightness * 0.1, gcolor.a);
	}
}
