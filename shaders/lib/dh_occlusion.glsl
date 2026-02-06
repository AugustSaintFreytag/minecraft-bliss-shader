#define VOLUMETRIC_OCCLUSION_BEHIND_FADE 128.0
#define DEPTH_FAR_THRESHOLD 0.99

// Library

struct DepthSample {
	float value;
	float rawDepth;
	float rawDepthLOD;
	bool isLOD;
};

// Utility

DepthSample getDepthSample(in vec2 pos) {
	// Takes a position in clip space and returns a depth sample from that point.

	float dhNear = dhNearPlane;
	float dhFar = dhFarPlane;
	float vanillaNear = near;
	float vanillaFar = far;

	#ifdef UseQuarterResDepth
		float sampleDepthLinear = sqrt(texelFetch(colortex4, ivec2(pos.xy / texelSize / 4.0), 0).a / 65000.0);
		float sampleDepthRaw = -((2.0 * vanillaNear / sampleDepthLinear) - vanillaFar - vanillaNear) / (vanillaFar - vanillaNear);
	#else
		float sampleDepthRaw = texelFetch(depthtex1, ivec2(pos.xy / texelSize), 0).r;
	#endif

	float linearDepth = clamp(swapperLinZ(sampleDepthRaw, vanillaNear, vanillaFar), 0.0, 1.0);

	bool isLODDepth = false;
	float sampleDepthLODRaw = 1.0;

	if (linearDepth >= DEPTH_FAR_THRESHOLD) {
		ivec2 dhDepthCoord = ivec2(pos.xy / texelSize);
		sampleDepthLODRaw = texelFetch(LOD_DEPTHTEX1, dhDepthCoord, 0).x;
		linearDepth = clamp(swapperLinZ(sampleDepthLODRaw, dhNear, dhFar), 0.0, 1.0);
		isLODDepth = true;
	}

	return DepthSample(linearDepth, sampleDepthRaw, sampleDepthLODRaw, isLODDepth);
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

// Sun

float getDHSunVisibility(in vec3 viewPos, in vec3 lightDir, float noise, float vanillaDepth){
	const int samples = DH_VOLUMETRIC_OCCLUSION_SAMPLES;
	const float stepSize = DH_VOLUMETRIC_OCCLUSION_STEP;
	const float occlusionDistanceCutoff = DH_VOLUMETRIC_OCCLUSION_DISTANCE;

	float dhNear = dhNearPlane;
	float dhFar = dhFarPlane;
	float vanillaNear = near;
	float vanillaFar = far;

	// Pre-check if current sun angle makes occlusion impossible.

	float sunAngleFactor = getSunAngleDisocclusionFactor();

	if (sunAngleFactor == 1.0) {
		return 1.0;
	}

	// Pre-check if distance to sampled position is outside of bounds.

	float occlusionDistanceCutoffSq = occlusionDistanceCutoff * occlusionDistanceCutoff;
	float distanceToViewer = length(viewPos);
	float sunDistanceFactor = clamp(smoothstep(occlusionDistanceCutoff * 0.2, occlusionDistanceCutoff, distanceToViewer), 0.0, 1.0);

	if (sunDistanceFactor == 1.0) {
		return 1.0;
	}

	// Ray Construction
	
	float lightRange = pow(clamp(-dot(normalize(viewPos), lightDir) + 0.65, 0.0, 1.0), 2.0) / 2;
	float farRayLength = dhFar * sqrt(3.0);

	bool clippedByNearPlane = false;
	float nearPlaneHitDistance = 0.0;
	float rayLength = farRayLength;

	if ((viewPos.z + lightDir.z * farRayLength) > - dhNear && abs(lightDir.z) > 1e-5) {
		clippedByNearPlane = true;
		nearPlaneHitDistance = (-dhNear - viewPos.z) / lightDir.z;
		nearPlaneHitDistance = max(nearPlaneHitDistance, 0.0);
		rayLength = min(nearPlaneHitDistance + VOLUMETRIC_OCCLUSION_BEHIND_FADE, farRayLength);
	}

	float behindFadeStart = 1.0;
	float behindFadeRange = 0.0;

	if (clippedByNearPlane && rayLength > 0.0) {
		float fadeDistance = min(VOLUMETRIC_OCCLUSION_BEHIND_FADE, rayLength);
		behindFadeRange = fadeDistance / rayLength;
		behindFadeStart = clamp(1.0 - behindFadeRange, 0.0, 1.0);
	}

	
	float rayStepSize = max(stepSize, 1e-4);

	// Sampling
	
	float raySampleSum = 0.0;
	int samplesProcessed = 0;

	for (int i = 0; i < samples; i++) {
		float sampleDistance = (float(i) + noise) * rayStepSize;

		if (sampleDistance > rayLength) {
			break;
		}

		vec3 sampleViewPos = viewPos + lightDir * sampleDistance;
		vec3 samplePos = toClipSpace3_DH(sampleViewPos, true);
		
		samplePos.xy *= RENDER_SCALE;

		if (!isWithinViewBounds(samplePos.xy)) {
			break;
		}

		DepthSample depthSample = getDepthSample(samplePos.xy);

		float linearDepth = depthSample.value;

		float fadeDistance = rayLength > 1e-4 ? clamp(sampleDistance / rayLength, 0.0, 1.0) : 1.0;
		float behindFade = 1.0;

		if (clippedByNearPlane && behindFadeRange > 0.0) {
			behindFade = clamp(1.0 - smoothstep(behindFadeStart, 1.0, fadeDistance), 0.0, 1.0);
		}
		
		vec3 sceneViewPos = depthSample.isLOD
			? toScreenSpace_DH(samplePos.xy, 1.0, depthSample.rawDepthLOD)
			: toScreenSpace_DH(samplePos.xy, depthSample.rawDepth, depthSample.rawDepthLOD);
		float depthBias = 0.01 + sampleDistance * 1e-4;
		float occlusion = (sceneViewPos.z > (sampleViewPos.z + depthBias)) ? 1.0 : 0.0;

		float rayStrength = pow(mix(1.0, 0.0, float(i) / float(samples)), 2.0);
		float sampleVisibility = (linearDepth >= DEPTH_FAR_THRESHOLD) ? 1.0 : mix(1.0, lightRange, occlusion);

		raySampleSum += sampleVisibility * behindFade * rayStrength;
		samplesProcessed ++;
	}

	if (samplesProcessed == 0) {
		return 1.0;
	}

	return clamp((raySampleSum / float(samplesProcessed)) + sunDistanceFactor + sunAngleFactor, 0.0, 1.0);
}
