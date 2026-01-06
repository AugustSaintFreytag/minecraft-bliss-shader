#define ANTIALIASING_RELATED_SETTINGS
#define DEPTH_OF_FIELD_RELATED_SETTINGS
#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

varying vec4 pos;
varying vec4 gcolor;

uniform vec2 texelSize;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 dhProjection;
uniform vec3 cameraPosition;
uniform sampler2D colortex4;

flat varying vec3 averageSkyCol_Clouds;


#if DOF_QUALITY == 5
	uniform int hideGUI;
	uniform int frameCounter;
	uniform float aspectRatio;
	uniform float screenBrightness;
	uniform float far;
	#include "/lib/bokeh.glsl"
#endif

#include "/lib/TAA_jitter.glsl"


void main() {
	vec4 vPos = gl_Vertex;
	vec3 cameraOffset = fract(cameraPosition);
	vec4 viewPos = gl_ModelViewMatrix * vPos;

	#ifdef PLANET_CURVATURE
		vec4 worldPos = gbufferModelViewInverse * viewPos;

		float curvature = length(worldPos) / (16*8);
		worldPos.y -= curvature*curvature * CURVATURE_AMOUNT;

		worldPos = gbufferModelView * worldPos;

		gl_Position = dhProjection * worldPos;
	#else
		gl_Position = dhProjection * viewPos;
	#endif

	#if TAA_MODE == 3
		gl_Position.xy = gl_Position.xy * RENDER_SCALE + RENDER_SCALE * gl_Position.w - gl_Position.w;
	#endif
	
	#if TAA_MODE > 0 && defined DH_TAA_JITTER
		gl_Position.xy += taaJitter * gl_Position.w*texelSize;
	#endif
	
	pos = viewPos;
	gcolor = gl_Color;
	
	averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;
	
	#if DOF_QUALITY == 5
		vec2 jitter = clamp(jitter_offsets[frameCounter % 64], -1.0, 1.0);
		jitter = rotate(radians(float(frameCounter))) * jitter;
		jitter.y *= aspectRatio;
		jitter.x *= DOF_ANAMORPHIC_RATIO;

		#if MANUAL_FOCUS == -2
		float focusMul = 0;
		#elif MANUAL_FOCUS == -1
		float focusMul = gl_Position.z + (far / 3.0) - mix(pow(512.0, screenBrightness), 512.0 * screenBrightness, 0.25);
		#else
		float focusMul = gl_Position.z + (far / 3.0) - MANUAL_FOCUS;
		#endif

		vec2 totalOffset = (jitter * JITTER_STRENGTH) * focusMul * 1e-2;
		gl_Position.xy += hideGUI >= 1 ? totalOffset : vec2(0);
	#endif
}
