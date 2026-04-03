// Library

struct DepthSample {
	float value;
	float raw;
	vec3 pos;
	bool isLOD;
};

// Utility

float hashNoise(float noise) {
    return fract(sin(noise) * 43758.5453);
}

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

	// All clip XY we use are in the same scaled space as other screenspace effects.
	// Convert back to unscaled UVs for depth fetches + view reconstruction.
	// Depth buffers are TAA-jittered, apply compensation.
	vec2 uv = pos / RENDER_SCALE - taaJitter * texelSize * 0.5;
	ivec2 texcoord = clipToTexCoords(uv);

	// Use small 2x2 sample pattern to catch thin geometry.
	// Remedy sampling gaps where a single texel fetch hits sky.
	ivec2 res = textureSize(depthtex0, 0);
	ivec2 p00 = clamp(texcoord, ivec2(0), res - 1);
	ivec2 p10 = clamp(texcoord + ivec2(1, 0), ivec2(0), res - 1);
	ivec2 p01 = clamp(texcoord + ivec2(0, 1), ivec2(0), res - 1);
	ivec2 p11 = clamp(texcoord + ivec2(1, 1), ivec2(0), res - 1);

	// If we take min depth from a neighbor texel but reconstruct view position
	// using the center UV, we get a mismatch that presents as light bleed.
	// Track the UV of the winning texel and reconstruct from that.
	vec2 uv00 = (vec2(p00) + 0.5) * texelSize;
	vec2 uv10 = (vec2(p10) + 0.5) * texelSize;
	vec2 uv01 = (vec2(p01) + 0.5) * texelSize;
	vec2 uv11 = (vec2(p11) + 0.5) * texelSize;

	float z0_00 = texelFetch(depthtex0, p00, 0).r;
	float z0_10 = texelFetch(depthtex0, p10, 0).r;
	float z0_01 = texelFetch(depthtex0, p01, 0).r;
	float z0_11 = texelFetch(depthtex0, p11, 0).r;

	float z1_00 = texelFetch(depthtex1, p00, 0).r;
	float z1_10 = texelFetch(depthtex1, p10, 0).r;
	float z1_01 = texelFetch(depthtex1, p01, 0).r;
	float z1_11 = texelFetch(depthtex1, p11, 0).r;

	float depthBase = z0_00;
	vec2 uvMin = uv00;
	if (z0_10 < depthBase) { depthBase = z0_10; uvMin = uv10; }
	if (z0_01 < depthBase) { depthBase = z0_01; uvMin = uv01; }
	if (z0_11 < depthBase) { depthBase = z0_11; uvMin = uv11; }

	if (z1_00 < depthBase) { depthBase = z1_00; uvMin = uv00; }
	if (z1_10 < depthBase) { depthBase = z1_10; uvMin = uv10; }
	if (z1_01 < depthBase) { depthBase = z1_01; uvMin = uv01; }
	if (z1_11 < depthBase) { depthBase = z1_11; uvMin = uv11; }

	if (depthBase < 1.0) {
		depth = swapperLinZ(depthBase, near, far * 4.0);
		depthViewPos = clipToViewSpace(uvMin, depthBase, 0.0);
		depthRaw = depthBase;
	} else {
		float zLod00 = texelFetch(LOD_DEPTHTEX1, p00, 0).r;
		float zLod10 = texelFetch(LOD_DEPTHTEX1, p10, 0).r;
		float zLod01 = texelFetch(LOD_DEPTHTEX1, p01, 0).r;
		float zLod11 = texelFetch(LOD_DEPTHTEX1, p11, 0).r;

		float depthLOD = zLod00;
		vec2 uvLodMin = uv00;
		if (zLod10 < depthLOD) { depthLOD = zLod10; uvLodMin = uv10; }
		if (zLod01 < depthLOD) { depthLOD = zLod01; uvLodMin = uv01; }
		if (zLod11 < depthLOD) { depthLOD = zLod11; uvLodMin = uv11; }

		depth = swapperLinZ(depthLOD, LOD_NEARPLANE + far, LOD_FARPLANE);
		depthViewPos = clipToViewSpace(uvLodMin, 1.0, depthLOD);
		depthRaw = depthLOD;
		depthIsLOD = true;
	}

	return DepthSample(depth, depthRaw, depthViewPos, depthIsLOD);
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

// Sun Shadow (Edition I)

vec3 bounceSampleClipPosIfBeyondBounds(vec3 clipPos) {
	vec2 clipPosNorm = clipPos.xy;
	vec2 bouncesNum = floor(abs(clipPosNorm));
	vec2 bouncesRemainder = fract(abs(clipPosNorm));
	vec2 mirroredClipPos = mix(bouncesRemainder, 1.0 - bouncesRemainder, mod(bouncesNum, 2.0));

	return vec3(mirroredClipPos.x + bouncesNum.x * 0.01, mirroredClipPos.y + bouncesNum.y * 0.01, clipPos.z);
}

bool sampleClipPosIsOutOfBounds(vec3 clipPos) {
	// Reject out of bounds with margin to allow for edge fill.
	vec2 maxBounds = RENDER_SCALE;
	return clipPos.x < -0.05 || clipPos.x > maxBounds.x + 0.05 || clipPos.y < -0.05 || clipPos.y > maxBounds.y + 0.05;
}

bool checkDepthPlaneHit(DepthSample depthSample, vec3 viewPos, float stepSize, float depthBias) {
	float sceneZ = depthSample.pos.z;
	float posZ = viewPos.z;
	float deltaZ = sceneZ - posZ; // > 0.0 means hit is closer than origin
	float distance = max(-posZ, 0.0);
	float thickness = 0.02 + distance * 0.001 + stepSize * 0.5;

	return deltaZ > depthBias && deltaZ < thickness;
}

float getSunShadow_1Level(in vec3 viewPos, in vec3 lightDir, float noise, bool fast) {
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

// Sun Shadow (Edition II)

bool depthRawIsSky(float rawDepth) {
	return rawDepth >= 0.9999;
}

bool evalDepthDeltaZ(in vec3 rayViewPos, in vec2 clipPosXY, out float dz, out DepthSample depthSample) {
	depthSample = getDepthSample(clipPosXY);
	if (depthRawIsSky(depthSample.raw)) {
		dz = 0.0;
		return false;
	}

	// View space z is negative in front of camera.
	dz = depthSample.pos.z - rayViewPos.z;
	return true;
}

bool refineCrossingHit(
	in vec3 originViewPos,
	in vec3 lightDir,
	in vec2 depthJitter,
	in float tNearIn,
	in float tFarIn,
	in float stepForThickness,
	in float depthBiasBase,
	out float tHitOut
) {
	float tNear = tNearIn;
	float tFar = tFarIn;

	DepthSample dsMid;
	for (int j = 0; j < 5; j++) {
		float tMid = 0.5 * (tNear + tFar);
		vec3 midViewPos = originViewPos + lightDir * tMid;
		vec3 midClipPos = viewToClipSpace(midViewPos);
		midClipPos.xy += depthJitter;
		if (sampleClipPosIsOutOfBounds(midClipPos)) {
			tFar = tMid;
			continue;
		}
		float dzMid;
		bool valid = evalDepthDeltaZ(midViewPos, midClipPos.xy, dzMid, dsMid);
		if (!valid) {
			// No surface at this UV (sky): treat as still in front.
			tNear = tMid;
			continue;
		}
		if (dzMid > 0.0) {
			tFar = tMid;
		} else {
			tNear = tMid;
		}
	}

	vec3 hitViewPos = originViewPos + lightDir * tFar;
	vec3 hitClipPos = viewToClipSpace(hitViewPos);
	hitClipPos.xy += depthJitter;
	DepthSample dsHit;
	float dzHit;
	bool validHit = evalDepthDeltaZ(hitViewPos, hitClipPos.xy, dzHit, dsHit);
	if (!validHit) {
		return false;
	}

	float dist = max(-hitViewPos.z, 0.0);
	float grazing = 1.0 / max(abs(lightDir.z), 0.15);

	float depthBias = depthBiasBase + dist * 0.0005 * grazing + stepForThickness * 0.01;
	float thickness = 0.03 + dist * 0.0015 * grazing + max(0.25, stepForThickness * 2.0) * grazing;

	if (dzHit > depthBias && dzHit < thickness) {
		tHitOut = tFar;
		return true;
	}

	return false;
}

float getSunShadow_2Level(in vec3 viewPos, in vec3 lightDir, float noise, bool fast) {
	int maxSamples = DH_VOLUMETRIC_OCCLUSION_SAMPLES;
	float depthBiasBase = DH_VOLUMETRIC_OCCLUSION_BIAS;
	float maxSampleDistance = DH_VOLUMETRIC_OCCLUSION_LENGTH;
	float maxDistance = DH_VOLUMETRIC_OCCLUSION_DISTANCE;

	float lightDistance = length(viewPos);
	float lightDistanceFadeFactor = 1.0 - smoothstep(maxDistance * 0.25, maxDistance, lightDistance);

	if (maxSamples == 0 || lightDistanceFadeFactor == 0.0) {
		return 0.0;
	}

	float sunAngleFactor = getSunAngleDisocclusionFactor();

	if (sunAngleFactor == 1.0) {
		return 0.0;
	}

	int fineSamples = maxSamples;
	float maxRayLength = maxSampleDistance;

	if (fast) {
		fineSamples = 2;
		maxRayLength = maxSampleDistance * 2.0;
	}

	// Coarse Pass

	// Fewer and longer steps to detect depth crossing as pre-check.
	// Bound so increasing sample counts don't over-restrict.
	int coarseSteps = clamp(fineSamples / 2, 4, 16);
	float coarseStep = maxRayLength / float(coarseSteps);
	float fineStep = maxRayLength / float(max(fineSamples, 1));

	// Apply stable per-ray depth UV jitter to break banding.
	// Use a 2D jitter in the ray's screen-space basis (dir + perp) 
	// so we don't lock to depth texel columns (vertical line artifacts). 
	// Seed with `taaJitter` so TAA can integrate it over time.
	vec2 originClipXY = viewToClipSpace(viewPos).xy;
	vec2 endClipXY = viewToClipSpace(viewPos + lightDir * maxRayLength).xy;
	vec2 rayDirClip = endClipXY - originClipXY;
	vec2 rayDirN = rayDirClip / max(length(rayDirClip), 1e-6);
	vec2 rayPerp = vec2(-rayDirClip.y, rayDirClip.x);
	
	float rayPerpLen = max(length(rayPerp), 1e-6);
	rayPerp /= rayPerpLen;

	vec2 pixelScaled = texelSize * RENDER_SCALE;
	
	float pixel = max(pixelScaled.x, pixelScaled.y);
	float frameSeed = dot(taaJitter, vec2(113.1, 17.7));
	float jitterA = hashNoise(noise + 91.7 + frameSeed);
	float jitterB = hashNoise(noise + 93.1 + frameSeed);
	
	vec2 depthJitter = (rayDirN * (jitterA - 0.5) + rayPerp * (jitterB - 0.5)) * pixel * 0.85;

	bool occluded = false;
	bool hasBest = false;

	float bestDzAdj = -1e20;
	float bestNearMiss = 0.0;

	float tPrev = 0.0;
	float dzPrev = 0.0;
	bool hasPrev = false;
	vec2 clipPrev = vec2(0.0);

	for (int i = 0; i < maxSamples; i++) {
		if (i >= coarseSteps) {
			break;
		}

		float sampleNoise = hashNoise(noise + float(i));
		
		// Keep jitter conservative so higher sample counts don't overreach thin edges.
		float jitter = (sampleNoise - 0.5) * coarseStep * 0.25;
		float t = (float(i) + 1.0) * coarseStep + jitter;
		
		t = clamp(t, 0.0, maxRayLength);

		vec3 rayViewPos = viewPos + lightDir * t;
		vec3 rayClipPos = viewToClipSpace(rayViewPos);
		
		rayClipPos.xy += depthJitter;

		if (sampleClipPosIsOutOfBounds(rayClipPos)) {
			break;
		}

		// Skip sky samples (no surface at this UV). Keep marching.
		DepthSample dsCoarse;
		float dz;
		bool valid = evalDepthDeltaZ(rayViewPos, rayClipPos.xy, dz, dsCoarse);

		if (!valid) {
			continue;
		}

		// SSR-style thickness test: if we land within a depth thickness band, accept occlusion
		// even if we don't catch a clean sign crossing at low sample counts.
		float dist = max(-rayViewPos.z, 0.0);
		float grazing = 1.0 / max(abs(lightDir.z), 0.15);
		float depthBias = depthBiasBase + dist * 0.0005 * grazing + coarseStep * 0.01;
		float thickness = 0.03 + dist * 0.0015 * grazing + max(0.25, coarseStep * 2.0) * grazing;
		float nearMiss = thickness * 0.45;
		float dzAdj = dz - depthBias;

		if (!hasBest || dzAdj > bestDzAdj) {
			hasBest = true;
			bestDzAdj = dzAdj;
			bestNearMiss = nearMiss;
		}

		if (dzAdj > 0.0 && dz < thickness) {
			occluded = true;
			break;
		}

		if (!hasPrev) {
			hasPrev = true;
			// If our very first valid sample is already behind the depth surface,
			// bracket from the start (t=0) so we don't miss big nearby occluders.
			if (dz > 0.0) {
				float tHit;
				if (refineCrossingHit(viewPos, lightDir, depthJitter, 0.0, t, fineStep, depthBiasBase, tHit)) {
					occluded = true;
					break;
				}
			}

			tPrev = t;
			dzPrev = dz;
			clipPrev = rayClipPos.xy;
			continue;
		}

		// Adaptive subdivision: if we advanced multiple pixels since the last valid sample,
		// insert 1-2 mid probes to avoid skipping thin silhouettes (foliage/ridges) at low sample counts.
		float deltaPix = length((rayClipPos.xy - clipPrev) / max(pixelScaled, vec2(1e-6)));
		int extraProbes = (deltaPix > 3.5) ? 2 : ((deltaPix > 1.75) ? 1 : 0);
		for (int e = 1; e <= 2; e++) {
			if (e > extraProbes) {
				break;
			}
			float tE = mix(tPrev, t, float(e) / float(extraProbes + 1));
			vec3 eViewPos = viewPos + lightDir * tE;
			vec3 eClipPos = viewToClipSpace(eViewPos);
			eClipPos.xy += depthJitter;
			if (sampleClipPosIsOutOfBounds(eClipPos)) {
				continue;
			}
			DepthSample dsE;
			float dzE;
			bool validE = evalDepthDeltaZ(eViewPos, eClipPos.xy, dzE, dsE);
			if (!validE) {
				continue;
			}

			float distE = max(-eViewPos.z, 0.0);
			float grazingE = 1.0 / max(abs(lightDir.z), 0.15);
			float depthBiasE = depthBiasBase + distE * 0.0005 * grazingE + coarseStep * 0.01;
			float thicknessE = 0.03 + distE * 0.0015 * grazingE + max(0.25, coarseStep * 2.0) * grazingE;
			float nearMissE = thicknessE * 0.45;
			float dzAdjE = dzE - depthBiasE;
			if (!hasBest || dzAdjE > bestDzAdj) {
				hasBest = true;
				bestDzAdj = dzAdjE;
				bestNearMiss = nearMissE;
			}
			if (dzAdjE > 0.0 && dzE < thicknessE) {
				occluded = true;
				break;
			}
			if (dzPrev <= 0.0 && dzE > 0.0) {
				float tHit;
				if (refineCrossingHit(viewPos, lightDir, depthJitter, tPrev, tE, fineStep, depthBiasBase, tHit)) {
					occluded = true;
					break;
				}
			}

			tPrev = tE;
			dzPrev = dzE;
			clipPrev = eClipPos.xy;
		}
		if (occluded) {
			break;
		}

		// Crossing test: ray went from in front of depth surface to behind it.
		if (dzPrev <= 0.0 && dz > 0.0) {
			float tHit;
			if (refineCrossingHit(viewPos, lightDir, depthJitter, tPrev, t, fineStep, depthBiasBase, tHit)) {
				occluded = true;
				break;
			}
		}

		tPrev = t;
		dzPrev = dz;
		clipPrev = rayClipPos.xy;
	}

	// Optional Fine Pass

	// If no occlusion was found in coarse pass, do a higher-res march.
	// Scale with `DH_VOLUMETRIC_OCCLUSION_SAMPLES`. 
	// This makes higher sample counts strictly better for thin/far silhouettes.
	if (!occluded && fineSamples > coarseSteps) {
		float tPrevFine = 0.0;
		float dzPrevFine = 0.0;
		bool hasPrevFine = false;
		vec2 clipPrevFine = vec2(0.0);

		for (int i = 0; i < maxSamples; i++) {
			if (i >= fineSamples) {
				break;
			}

			float sampleNoise = hashNoise(noise + 17.0 + float(i));
			float jitter = (sampleNoise - 0.5) * fineStep * 0.25;
			float t = (float(i) + 1.0) * fineStep + jitter;
			t = clamp(t, 0.0, maxRayLength);

			vec3 rayViewPos = viewPos + lightDir * t;
			vec3 rayClipPos = viewToClipSpace(rayViewPos);
			rayClipPos.xy += depthJitter;

			if (sampleClipPosIsOutOfBounds(rayClipPos)) {
				break;
			}

			DepthSample ds;
			float dz;
			bool valid = evalDepthDeltaZ(rayViewPos, rayClipPos.xy, dz, ds);

			if (!valid) {
				continue;
			}

			float dist = max(-rayViewPos.z, 0.0);
			float grazing = 1.0 / max(abs(lightDir.z), 0.15);
			float depthBias = depthBiasBase + dist * 0.0005 * grazing + fineStep * 0.01;
			float thickness = 0.03 + dist * 0.0015 * grazing + max(0.25, fineStep * 2.0) * grazing;
			float nearMiss = thickness * 0.45;
			float dzAdj = dz - depthBias;

			if (!hasBest || dzAdj > bestDzAdj) {
				hasBest = true;
				bestDzAdj = dzAdj;
				bestNearMiss = nearMiss;
			}
			
			if (dzAdj > 0.0 && dz < thickness) {
				occluded = true;
				break;
			}

			if (!hasPrevFine) {
				hasPrevFine = true;
				tPrevFine = t;
				dzPrevFine = dz;
				clipPrevFine = rayClipPos.xy;
				continue;
			}

			float deltaPixFine = length((rayClipPos.xy - clipPrevFine) / max(pixelScaled, vec2(1e-6)));
			int extraProbesFine = (deltaPixFine > 3.5) ? 2 : ((deltaPixFine > 1.75) ? 1 : 0);

			for (int e = 1; e <= 2; e++) {
				if (e > extraProbesFine) {
					break;
				}

				float tE = mix(tPrevFine, t, float(e) / float(extraProbesFine + 1));
				vec3 eViewPos = viewPos + lightDir * tE;
				vec3 eClipPos = viewToClipSpace(eViewPos);
				
				eClipPos.xy += depthJitter;
				
				if (sampleClipPosIsOutOfBounds(eClipPos)) {
					continue;
				}
				
				DepthSample dsE;
				float dzE;
				bool validE = evalDepthDeltaZ(eViewPos, eClipPos.xy, dzE, dsE);
				
				if (!validE) {
					continue;
				}

				float distE = max(-eViewPos.z, 0.0);
				float grazingE = 1.0 / max(abs(lightDir.z), 0.15);
				float depthBiasE = depthBiasBase + distE * 0.0005 * grazingE + fineStep * 0.01;
				float thicknessE = 0.03 + distE * 0.0015 * grazingE + max(0.25, fineStep * 2.0) * grazingE;
				float nearMissE = thicknessE * 0.45;
				float dzAdjE = dzE - depthBiasE;
				
				if (!hasBest || dzAdjE > bestDzAdj) {
					hasBest = true;
					bestDzAdj = dzAdjE;
					bestNearMiss = nearMissE;
				}
				
				if (dzAdjE > 0.0 && dzE < thicknessE) {
					occluded = true;
					break;
				}
				
				if (dzPrevFine <= 0.0 && dzE > 0.0) {
					float tHit;
					if (refineCrossingHit(viewPos, lightDir, depthJitter, tPrevFine, tE, fineStep, depthBiasBase, tHit)) {
						occluded = true;
						break;
					}
				}

				tPrevFine = tE;
				dzPrevFine = dzE;
				clipPrevFine = eClipPos.xy;
			}

			if (occluded) {
				break;
			}

			if (dzPrevFine <= 0.0 && dz > 0.0) {
				float tHit;
				
				if (refineCrossingHit(viewPos, lightDir, depthJitter, tPrevFine, t, fineStep, depthBiasBase, tHit)) {
					occluded = true;
					break;
				}
			}

			tPrevFine = t;
			dzPrevFine = dz;
			clipPrevFine = rayClipPos.xy;
		}
	}

	float occlusion = 0.0;
	
	if (occluded) {
		occlusion = 1.0;
	} else if (hasBest) {
		// Fallback: if we never caught a crossing, shadow based on closest approach.
		// This clamps down light-bleed near ridges when step sizes are large.
		float x = smoothstep(-bestNearMiss, 0.0, bestDzAdj);
		occlusion = x * x; // sharpen transition (fewer "half-shadow" cases)
	}
	
	float outputOcclusion = (occlusion * lightDistanceFadeFactor) * (1.0 - sunAngleFactor);
	return outputOcclusion;
}

// Switch

float getSunShadow(in vec3 viewPos, in vec3 lightDir, float noise, bool fast) {
	return getSunShadow_2Level(viewPos, lightDir, noise, fast);
}