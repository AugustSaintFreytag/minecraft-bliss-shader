uniform vec2 texelSize;

#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"

void main() {
	gl_Position = ftransform();
	gl_Position.xy *= vec2(SKY_CLOUD_ATLAS_OFFSET_X + SKY_CLOUD_ATLAS_SIZE + 1.0, SKY_CLOUD_ATLAS_SIZE + 1.0) / 2048.0;
	gl_Position.xy = gl_Position.xy * 2.0 - 1.0;
}
