#define VOLUMETRIC_OCCLUSION_BEHIND_FADE 128.0
#define DEPTH_FAR_THRESHOLD 0.99

// Library

struct DepthSample {
	float value;
	float raw;
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
	float depthRaw = 0.0;

	vec3 depthViewPos = vec3(0.0);
	bool depthIsLOD = false;

	ivec2 texcoord = clipToTexCoords(pos);
	float z0 = texelFetch(depthtex0, texcoord, 0).r;
	float z1 = texelFetch(depthtex1, texcoord, 0).r;
	float depthBase = min(z0, z1);

	if (depthBase < 1.0) {
		depth = swapperLinZ(depthBase, near, far * 4.0);
		depthViewPos = clipToViewSpace(pos, depthBase, 0.0);
		depthRaw = depthBase;
	} else {
		float depthLOD = texelFetch(LOD_DEPTHTEX1, texcoord, 0).r;
		depth = swapperLinZ(depthLOD, LOD_NEARPLANE + far, LOD_FARPLANE);
		depthViewPos = clipToViewSpace(pos, depthBase, depthLOD);
		depthRaw = depthLOD;
		depthIsLOD = true;
	}

	return DepthSample(depth, depthRaw, depthViewPos, depthIsLOD);
}

float hashNoise(float noise) {
    return fract(sin(noise) * 43758.5453);
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

vec3 bounceSampleClipPosIfBeyondBounds(vec3 clipPos) {
	vec2 clipPosNorm = clipPos.xy;
	vec2 bouncesNum = floor(abs(clipPosNorm));
	vec2 bouncesRemainder = fract(abs(clipPosNorm));
	vec2 mirroredClipPos = mix(bouncesRemainder, 1.0 - bouncesRemainder, mod(bouncesNum, 2.0));

	return vec3(mirroredClipPos.x + bouncesNum.x * 0.01, mirroredClipPos.y + bouncesNum.y * 0.01, clipPos.z);
}

bool sampleClipPosIsOutOfBounds(vec3 clipPos) {
	// Reject out of bounds with margin to allow for edge fill.
	return clipPos.x < -0.05 || clipPos.x > 1.05 || clipPos.y < -0.05 || clipPos.y > 1.05;
}

bool checkDepthPlaneHit(DepthSample depthSample, vec3 viewPos, float stepSize, float depthBias) {
	float sceneZ = depthSample.pos.z;
	float posZ = viewPos.z;
	float deltaZ = sceneZ - posZ; // > 0.0 means hit is closer than origin
	float distance = max(-posZ, 0.0);
	float thickness = 0.02 + distance * 0.001 + stepSize * 0.5;

	return deltaZ > depthBias && deltaZ < thickness;
}

float getSunShadow(in vec3 viewPos, in vec3 lightDir, float noise, bool fast) {
	const int maxSamples = DH_VOLUMETRIC_OCCLUSION_SAMPLES;
	const float depthBias = DH_VOLUMETRIC_OCCLUSION_BIAS;
	const float maxSampleDistance = DH_VOLUMETRIC_OCCLUSION_LENGTH;
	const float maxDistance = DH_VOLUMETRIC_OCCLUSION_DISTANCE;

	// Light direction is the direction of the sun from the currently sampled position.
	// View position and light direction are in view space.

	float lightFacingFactor = 1.0 - smoothstep(0.0, 1.0, lightDir.z * 2);
	float lightDistance = length(viewPos);
	float lightDistanceFactor = clamp(lightDistance / maxDistance, 0.0, 1.0);
	float lightDistanceFadeFactor = 1.0 - smoothstep(maxDistance * 0.25, maxDistance, lightDistance);

	if (lightDistanceFadeFactor == 0.0) {
		return 0.0;
	}

	// Pre-check if current sun angle makes occlusion impossible.

	float sunAngleFactor = getSunAngleDisocclusionFactor();

	if (sunAngleFactor == 1.0) {
		return 0.0;
	}

	// If light direction in view space points away from camera, assume light is behind camera.
	// View space z coordinate is < 0 in front, > 0 behind camera.

	vec3 lightRayViewPos = viewPos + lightDir * 1000.0;
	vec3 lightRayClipPos = viewToClipSpace(lightRayViewPos);
	vec3 lightSampleStartPos = viewPos;

	int samples = maxSamples;
	float sampleDepthBias = depthBias;
	float maxRayLength = maxSampleDistance;

	if (fast) {
		samples = 2;
		maxRayLength = maxSampleDistance * 2.0;
	}

	float stepSize = maxRayLength / samples;

	float occlusionAmount = 0.0;
	int stepsSinceLastHit = 0;

	for (int i=0; i < samples; i++) {
		float samplePower = 1.0;
		float sampleNoise = hashNoise(noise + i);
		float sampleStepSize = stepSize;

		vec3 lightDirStep = lightDir * sampleStepSize;
		vec3 sampleViewPos = lightSampleStartPos + sampleNoise + lightDirStep * (float(i) + 0.1);
		vec3 sampleClipPos = viewToClipSpace(sampleViewPos);

		if (sampleClipPosIsOutOfBounds(sampleClipPos)) {
			break;
		}

		sampleClipPos = bounceSampleClipPosIfBeyondBounds(sampleClipPos);
		DepthSample depthSample = getDepthSample(sampleClipPos.xy);
		
		// Reject sky at maximum of linearized depth.
		if (depthSample.raw > 0.9999) {
			continue;
		}

		if (!checkDepthPlaneHit(depthSample, sampleViewPos, sampleStepSize, depthBias)) {
			// No Hit
			stepsSinceLastHit ++;
			continue;
		}

		// Hit

		float rayLength = i * sampleStepSize;
		float rayLengthFactor = 1.0 - rayLength / maxRayLength;

		occlusionAmount += samplePower;
		stepsSinceLastHit = 0;
	}

	// Clip space is screen space.
	float outputOcclusion = (smoothstep(0.0, 1.0, occlusionAmount) * lightDistanceFadeFactor) * (1.0 - sunAngleFactor);
	return outputOcclusion;
}