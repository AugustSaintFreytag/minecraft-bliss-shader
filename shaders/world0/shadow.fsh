#version 120
#define DIRECT_LIGHT_RELATED_SETTINGS
#define SHADOWMAP_CONSTANT_RELATED_SETTINGS
#include "/lib/settings.glsl"

varying vec4 color;

varying vec2 texcoord;
uniform sampler2D tex;
uniform sampler2D noisetex;
uniform float far;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

float blueNoise(){
  return fract(texelFetch2D(noisetex, ivec2(gl_FragCoord.xy)%512, 0).a + 1.0/1.6180339887 );
}

varying vec3 playerPosVarying;

float interleaved_gradientNoise(){
	vec2 coord = gl_FragCoord.xy;
	float noise = fract(52.9829189*fract(0.06711056*coord.x + 0.00583715*coord.y));
	return noise;
}

void main() {
	
	float fadeDist = min(far, shadowDistance);
	float dist = length(playerPosVarying.xyz);
	if (dist > fadeDist * 0.9) {
		float dither = interleaved_gradientNoise();
		if (dither < (dist - fadeDist * 0.9) / (fadeDist * 0.1)) discard;
	}

	vec4 shadowColor = vec4(texture2D(tex,texcoord.xy).rgb * color.rgb,  texture2DLod(tex, texcoord.xy, 0).a);

	gl_FragData[0] = shadowColor;

  	#if defined Stochastic_Transparent_Shadows
		if(gl_FragData[0].a < blueNoise()) { discard; return;}
  	#endif
}
