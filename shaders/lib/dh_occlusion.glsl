// Utility

// Returns 1.0 when sun is unobstructable (e.g. noon) and 0.0 when near horizon (e.g. sunrise and sunset).
float getSunAngleDisocclusionFactor() {
	const float HOURS_PER_HALF_DAY = 12.0;
	const float HORIZON_ANGLE = PI * 0.5;

	const float sunAngleEventOffsetHours = 0.25;
	const float sunAngleTransitionHours = 0.5;

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
	const float occlusionDistanceLimit = DH_VOLUMETRIC_OCCLUSION_DISTANCE;
	const float volumetricOcclusionBehindFade = 128.0;

	float nearPlane = dhNearPlane;
	float farPlane = dhFarPlane;

	// Vanilla planes
	// float nearPlane = near; 
	// float farPlane = far * 4.0;
	
	float lightRange = pow(clamp(-dot(normalize(viewPos), lightDir) + 0.65, 0.0, 1.0), 2.0) / 2;
	float farRayLength = farPlane * sqrt(3.0);
	vec3 position = toClipSpace3_DH(viewPos, true);
	
	float rayLength = farRayLength;
	bool clippedByNearPlane = false;
	float nearPlaneHitDistance = 0.0;

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

	vec3 direction = toClipSpace3_DH(viewPos + lightDir * rayLength, true) - position;

	direction.xyz = direction.xyz / max(max(abs(direction.x) / 0.0005, abs(direction.y) / 0.0005), 500.0);
	direction *= stepSize;
	
	position.xy *= RENDER_SCALE;
	direction.xy *= RENDER_SCALE;
	
	vec3 newPos = position + direction * noise;
	vec2 screenEdges = 2.0 / vec2(viewWidth, viewHeight);

	float depthFarThreshold = 0.99;
	float occlusionDistanceCutoff = occlusionDistanceLimit;
	float occlusionDistanceCutoffSq = occlusionDistanceCutoff * occlusionDistanceCutoff;
	float distanceToViewer = length(viewPos);

	float sunAngleFactor = getSunAngleDisocclusionFactor();

	if (sunAngleFactor == 1.0) {
		return 1.0;
	}

	float sunDistanceFactor = clamp(smoothstep(occlusionDistanceCutoff * 0.2, occlusionDistanceCutoff, distanceToViewer), 0.0, 1.0);

	if (sunDistanceFactor == 1.0) {
		return 1.0;
	}
	
	float raySampleSum = 0.0;
	int samplesProcessed = 0;

	for (int i = 0; i < samples; i++) {
		newPos.xy = clamp(newPos.xy, screenEdges, 1.0 - screenEdges);

		// Prefer vanilla depth samples before falling back to DH LOD depth.
		#ifdef UseQuarterResDepth
			float sampleDepth = sqrt(texelFetch(colortex4, ivec2(newPos.xy / texelSize / 4.0), 0).a / 65000.0);
		#else
			float sampleDepth = linZ(texelFetch(depthtex1, ivec2(newPos.xy / texelSize), 0).r);
		#endif

		float linearDepth = clamp(swapperLinZ(sampleDepth, nearPlane, farPlane), 0.0, 1.0);

		// Once vanilla depth is exhausted, continue in LOD depth buffer.
		if (linearDepth >= depthFarThreshold) {
			ivec2 dhDepthCoord = ivec2(newPos.xy / texelSize);
			float dhSampleDepth = texelFetch(LOD_DEPTHTEX1, dhDepthCoord, 0).x;
			linearDepth = clamp(swapperLinZ(dhSampleDepth, nearPlane, farPlane), 0.0, 1.0);
		}

		float d = samples > 1 ? float(i) / float(samples - 1) : 1.0;
		float behindFade = 1.0;

		if (clippedByNearPlane && behindFadeRange > 0.0) {
			behindFade = clamp(1.0 - smoothstep(behindFadeStart, 1.0, d), 0.0, 1.0);
		}
		
		float rayStrength = pow(mix(1.0, 0.0, float(i) / float(samples)), 2.0);
		raySampleSum += (linearDepth >= depthFarThreshold ? 1.0 : lightRange) * behindFade * rayStrength;

		newPos = clamp(newPos + direction, vec3(screenEdges.x, screenEdges.y, 0.0), 1.0 - vec3(screenEdges.x, screenEdges.y, 0.0));
		samplesProcessed ++;
	}

	if (samplesProcessed == 0) {
		return 1.0;
	}

	float suppressionFactor = 4.0;
	return clamp(((raySampleSum / float(samplesProcessed)) * suppressionFactor) + sunDistanceFactor + sunAngleFactor, 0.0, 1.0);
}
