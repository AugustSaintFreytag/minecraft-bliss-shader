#define ANTIALIASING_RELATED_SETTINGS
#define EMISSION_RELATED_SETTINGS

#include "/lib/settings.glsl"
#include "/lib/DH_utils.glsl"

varying vec4 pos;
varying vec4 gcolor;

uniform vec2 texelSize;
uniform vec3 cameraPosition;
uniform sampler2D depthtex1;

uniform mat4 gbufferModelViewInverse;
uniform int frameCounter;

flat varying vec3 averageSkyCol_Clouds;

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

		#ifdef DH_NOISE_TEXTURE
			albedo = applyNoise(vec4(albedo, 1.0), playerPos + cameraPosition, length(playerPos)).rgb;
		#endif

		vec3 ambientLightColor = averageSkyCol_Clouds / 900.0;
		float lightness = luma(ambientLightColor);
		vec3 skylightInfluence = mix(vec3(lightness), ambientLightColor, 0.2);

		gl_FragData[0] = vec4(albedo * skylightInfluence * Emissive_Brightness * 0.1, gcolor.a);
	}
}
