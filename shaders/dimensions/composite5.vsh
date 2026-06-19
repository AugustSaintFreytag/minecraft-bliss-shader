uniform int frameCounter;
uniform float near;
uniform float far;

varying vec2 texcoord;
flat varying float tempOffsets;

#include "/lib/util.glsl"

void main() {

	gl_Position = ftransform();
	texcoord = gl_MultiTexCoord0.xy;
	tempOffsets = HaltonSeq2(frameCounter%10000);
}
