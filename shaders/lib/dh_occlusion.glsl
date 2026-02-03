// Utility

// Returns 1.0 when sun is unobstructable (e.g. noon) and 0.0 when near horizon (e.g. sunrise and sunset).
float getSunAngleDisocclusionFactor() {
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

	const float volumetricOcclusionBehindFade = 128.0;
	const float depthFarThreshold = 0.99;

	float nearPlane = dhNearPlane;
	float farPlane = dhFarPlane;

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
	float farRayLength = farPlane * sqrt(3.0);

	bool clippedByNearPlane = false;
	float nearPlaneHitDistance = 0.0;
	float rayLength = farRayLength;

	if ((viewPos.z + lightDir.z * farRayLength) > - nearPlane && abs(lightDir.z) > 1e-5) {
		clippedByNearPlane = true;
		nearPlaneHitDistance = (-nearPlane - viewPos.z) / lightDir.z;
		nearPlaneHitDistance = max(nearPlaneHitDistance, 0.0);
		rayLength = min(nearPlaneHitDistance + volumetricOcclusionBehindFade, farRayLength);
	}

	float behindFadeStart = 1.0;
	float behindFadeRange = 0.0;

	if (clippedByNearPlane && rayLength > 0.0) {
		float fadeDistance = min(volumetricOcclusionBehindFade, rayLength);
		behindFadeRange = fadeDistance / rayLength;
		behindFadeStart = clamp(1.0 - behindFadeRange, 0.0, 1.0);
	}

	vec2 screenEdges = 2.0 / vec2(viewWidth, viewHeight);
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

		if (samplePos.x <= screenEdges.x || samplePos.x >= 1.0 - screenEdges.x || samplePos.y <= screenEdges.y || samplePos.y >= 1.0 - screenEdges.y) {
			break;
		}

		// Use vanilla depth within range, then swap to DH depth farther away.

		#ifdef UseQuarterResDepth
			float sampleDepthLinear = sqrt(texelFetch(colortex4, ivec2(samplePos.xy / texelSize / 4.0), 0).a / 65000.0);
			float sampleDepthRaw = -((2.0 * nearPlane / sampleDepthLinear) - farPlane - nearPlane) / (farPlane - nearPlane);
		#else
			float sampleDepthRaw = texelFetch(depthtex1, ivec2(samplePos.xy / texelSize), 0).r;
		#endif

		float linearDepth = clamp(swapperLinZ(sampleDepthRaw, nearPlane, farPlane), 0.0, 1.0);

		bool useLODDepth = false;
		float dhSampleDepth = 1.0;

		if (linearDepth >= depthFarThreshold) {
			ivec2 dhDepthCoord = ivec2(samplePos.xy / texelSize);
			dhSampleDepth = texelFetch(LOD_DEPTHTEX1, dhDepthCoord, 0).x;
			linearDepth = clamp(swapperLinZ(dhSampleDepth, nearPlane, farPlane), 0.0, 1.0);
			useLODDepth = true;
		}

		float fadeDistance = rayLength > 1e-4 ? clamp(sampleDistance / rayLength, 0.0, 1.0) : 1.0;
		float behindFade = 1.0;

		if (clippedByNearPlane && behindFadeRange > 0.0) {
			behindFade = clamp(1.0 - smoothstep(behindFadeStart, 1.0, fadeDistance), 0.0, 1.0);
		}
		
		vec3 sceneViewPos = useLODDepth
			? toScreenSpace_DH(samplePos.xy, 1.0, dhSampleDepth)
			: toScreenSpace_DH(samplePos.xy, sampleDepthRaw, dhSampleDepth);
		float depthBias = 0.01 + sampleDistance * 1e-4;
		float occlusion = (sceneViewPos.z > (sampleViewPos.z + depthBias)) ? 1.0 : 0.0;

		float rayStrength = pow(mix(1.0, 0.0, float(i) / float(samples)), 2.0);
		float sampleVisibility = (linearDepth >= depthFarThreshold) ? 1.0 : mix(1.0, lightRange, occlusion);

		raySampleSum += sampleVisibility * behindFade * rayStrength;
		samplesProcessed ++;
	}

	if (samplesProcessed == 0) {
		return 1.0;
	}

	return clamp((raySampleSum / float(samplesProcessed)) + sunDistanceFactor + sunAngleFactor, 0.0, 1.0);
}
