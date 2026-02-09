#define VOLUMETRIC_OCCLUSION_BEHIND_FADE 128.0
#define DEPTH_FAR_THRESHOLD 0.99

// Library

struct DepthSample {
	float value;
	vec3 pos;
	bool isLOD;
};

// Utility

vec3 clipToViewSpace(in vec2 pos, float depth, float depthLOD) {
	return toScreenSpace_DH(pos.xy, depth, depthLOD);
}

ivec2 clipToTexCoords(in vec2 pos) {
	return ivec2(pos / texelSize);
}

vec3 viewToClipSpace(in vec3 pos) {
	vec3 clipPos = toClipSpace3_DH(pos, true);
	clipPos.xy *= RENDER_SCALE;

	return clipPos;
}

DepthSample getDepthSample(in vec2 pos) {
	float depth = 0.0;
	vec3 depthViewPos = vec3(0.0);
	bool depthIsLOD = false;

	ivec2 texcoord = clipToTexCoords(pos);
	float depthBase = texelFetch(depthtex1, texcoord, 0).r;

	if (depthBase < 1.0) {
		depth = swapperLinZ(depthBase, near, far * 4.0);
		depthViewPos = clipToViewSpace(pos, depthBase, 0.0);
	} else {
		float depthLOD = texelFetch(LOD_DEPTHTEX1, texcoord, 0).r;
		depth = swapperLinZ(depthLOD, LOD_NEARPLANE + far, LOD_FARPLANE);
		depthViewPos = clipToViewSpace(pos, depthBase, depthLOD);
		depthIsLOD = true;
	}

	return DepthSample(depth, depthViewPos, depthIsLOD);
}

bool isWithinViewBounds(in vec2 pos) {
	vec2 viewBounds = 2.0 / vec2(viewWidth, viewHeight);
	return !(pos.x <= viewBounds.x || pos.x >= 1.0 - viewBounds.x || pos.y <= viewBounds.y || pos.y >= 1.0 - viewBounds.y);
}

// Daylight Disocclusion

float getSunAngleDisocclusionFactor() {
	// Returns 1.0 when sun is unobstructable (e.g. noon) and 0.0 when near horizon (e.g. sunrise and sunset).

	const float HOURS_PER_HALF_DAY = 12.0;
	const float HORIZON_ANGLE = PI * 0.5;

	const float sunAngleEventOffsetHours = 2.0;
	const float sunAngleTransitionHours = 1.5;

	float sunAngle = acos(clamp(sunElevation, -1.0, 1.0));
	float distanceFromHorizon = abs(sunAngle - HORIZON_ANGLE);

	float offsetHours = clamp(max(sunAngleEventOffsetHours, 0.0), 0.0, HOURS_PER_HALF_DAY);
	float transitionHours = clamp(max(sunAngleTransitionHours, 0.0), 0.0, HOURS_PER_HALF_DAY);

	float hourToAngle = PI / HOURS_PER_HALF_DAY;
	float offsetAngle = offsetHours * hourToAngle;
	float transitionAngle = max(transitionHours * hourToAngle, 1e-4);

	float normalizedDistance = max(distanceFromHorizon - offsetAngle, 0.0);
	float transitionProgress = smoothstep(0.0, transitionAngle, normalizedDistance);

	return clamp(transitionProgress, 0.0, 1.0);
}

// Sun (New)

float getSunShadow(in vec3 viewPos, in vec3 lightDir, float noise) {
	const int samples = DH_VOLUMETRIC_OCCLUSION_SAMPLES;
	const float stepSize = DH_VOLUMETRIC_OCCLUSION_STEP;
	const int stepPacing = 2;
	const float minStepSize = 1.0;
	const float depthBias = 0.001;
	const float maxDistance = DH_VOLUMETRIC_OCCLUSION_DISTANCE;

	// Light direction is the direction of the sun from the currently sampled position.
	// View position and light direction are in view space.

	float lightFacingFactor = 1.0 - smoothstep(0.0, 1.0, lightDir.z * 2);

	// If light direction in view space points away from camera, assume light is behind camera.
	// View space z coordinate is < 0 in front, > 0 behind camera.

	float lightNoise = noise;
	vec3 lightRayViewPos = viewPos + lightDir * 100.0;
	vec3 lightRayClipPos = viewToClipSpace(lightRayViewPos);
	vec3 lightSampleStartPos = viewPos;

	// float maxStepSize = mix(minStepSize, stepSize, lightFacingFactor);
	float maxStepSize = stepSize;
	float maxRayLength = samples * maxStepSize;

	float occlusionAmount = 0.0;
	int stepsSinceLastHit = 0;

	for (int i=0; i < samples; i++) {
		float sampleStepSize = mix(minStepSize, maxStepSize, clamp(stepsSinceLastHit / stepPacing, 0.0, 1.0));
		vec3 lightDirStep = lightDir * maxStepSize;
		vec3 sampleViewPos = lightSampleStartPos + lightDirStep * (float(i) + lightNoise);
		vec3 sampleClipPos = viewToClipSpace(sampleViewPos);

		DepthSample depthSample = getDepthSample(sampleClipPos.xy);

		if (depthSample.pos.z > 10.0) {
			break;
		}
		
		// float sampleDepthBias = mix(depthBias, depthBias * 0.1, lightFacingFactor);
		float sampleDepthBias = depthBias;

		if (depthSample.pos.z < sampleViewPos.z + sampleDepthBias) {
			// No Hit
			stepsSinceLastHit ++;
			continue;
		}

		// Hit

		float rayLength = i * stepSize;
		float rayLengthFactor = clamp(1.0 - rayLength / maxRayLength * 0.25, 0.0, 1.0);

		occlusionAmount += rayLengthFactor;
		stepsSinceLastHit = 0;
	}

	// Clip space is screen space.
	return smoothstep(0.0, 1.0, occlusionAmount) * lightFacingFactor;
}