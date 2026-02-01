#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

varying vec2 texcoord;

uniform sampler2D colortex4;

flat varying vec4 exposure;
flat varying vec2 rodExposureDepth;

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {

	gl_Position = ftransform();
	texcoord = gl_MultiTexCoord0.xy;

	exposure = vec4(vec3(texelFetch(colortex4,IMAGE_BRIGHTNESS_COORDS,0).r),texelFetch(colortex4,IMAGE_BRIGHTNESS_COORDS,0).r);
	rodExposureDepth = texelFetch(colortex4,AUTO_EXPOSURE_COORDS,0).rg;
	rodExposureDepth.y = sqrt(rodExposureDepth.y/65000.0);
}