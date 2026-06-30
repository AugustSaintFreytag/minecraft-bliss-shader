// Library

struct DepthSample {
	float value;
	float raw;
	vec3 pos;
	bool isLOD;
	bool isWaterSurface;
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

vec3 viewToClipSpace(in vec3 pos, bool depthCheck) {
	vec3 clipPos = toClipSpace3_DH(pos, depthCheck);
	clipPos.xy *= RENDER_SCALE;

	return clipPos;
}

vec3 viewToClipSpace(in vec3 pos) {
	return viewToClipSpace(pos, true);
}

DepthSample makeDepthSample(float value, float raw, vec3 pos, bool isLOD, bool isWaterSurface) {
	return DepthSample(value, raw, pos, isLOD, isWaterSurface);
}

DepthSample getDepthSample(in vec2 pos, bool waterSurfaceCap, sampler2D waterMaskTex) {
	float depth = 0.0;
	float depthRaw = 0.0;

	vec3 depthViewPos = vec3(0.0);
	bool depthIsLOD = false;
	bool depthIsWaterSurface = false;

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

	if (waterSurfaceCap) {
		bool water00 = texelFetch(waterMaskTex, p00, 0).a > 0.99;
		bool water10 = texelFetch(waterMaskTex, p10, 0).a > 0.99;
		bool water01 = texelFetch(waterMaskTex, p01, 0).a > 0.99;
		bool water11 = texelFetch(waterMaskTex, p11, 0).a > 0.99;

		float waterDepth = 1.0;
		vec2 waterUV = uv00;
		
		bool hasWaterSurface = false;
		bool waterSurfaceIsLOD = false;

		if (water00 && z0_00 < waterDepth) { waterDepth = z0_00; waterUV = uv00; hasWaterSurface = z0_00 < 1.0; }
		if (water10 && z0_10 < waterDepth) { waterDepth = z0_10; waterUV = uv10; hasWaterSurface = z0_10 < 1.0; }
		if (water01 && z0_01 < waterDepth) { waterDepth = z0_01; waterUV = uv01; hasWaterSurface = z0_01 < 1.0; }
		if (water11 && z0_11 < waterDepth) { waterDepth = z0_11; waterUV = uv11; hasWaterSurface = z0_11 < 1.0; }

		if (!hasWaterSurface) {
			float zLodTrans00 = texelFetch(LOD_DEPTHTEX0, p00, 0).r;
			float zLodTrans10 = texelFetch(LOD_DEPTHTEX0, p10, 0).r;
			float zLodTrans01 = texelFetch(LOD_DEPTHTEX0, p01, 0).r;
			float zLodTrans11 = texelFetch(LOD_DEPTHTEX0, p11, 0).r;

			waterDepth = 1.0;
			if (water00 && zLodTrans00 < waterDepth) { waterDepth = zLodTrans00; waterUV = uv00; hasWaterSurface = zLodTrans00 < 1.0; }
			if (water10 && zLodTrans10 < waterDepth) { waterDepth = zLodTrans10; waterUV = uv10; hasWaterSurface = zLodTrans10 < 1.0; }
			if (water01 && zLodTrans01 < waterDepth) { waterDepth = zLodTrans01; waterUV = uv01; hasWaterSurface = zLodTrans01 < 1.0; }
			if (water11 && zLodTrans11 < waterDepth) { waterDepth = zLodTrans11; waterUV = uv11; hasWaterSurface = zLodTrans11 < 1.0; }
			waterSurfaceIsLOD = hasWaterSurface;
		}

		float foregroundDepth = 1.0;
		vec2 foregroundUV = uv00;

		if (!water00 && z0_00 < foregroundDepth) { foregroundDepth = z0_00; foregroundUV = uv00; }
		if (!water10 && z0_10 < foregroundDepth) { foregroundDepth = z0_10; foregroundUV = uv10; }
		if (!water01 && z0_01 < foregroundDepth) { foregroundDepth = z0_01; foregroundUV = uv01; }
		if (!water11 && z0_11 < foregroundDepth) { foregroundDepth = z0_11; foregroundUV = uv11; }

		if (hasWaterSurface) {
			if (!waterSurfaceIsLOD && foregroundDepth < waterDepth) {
				depth = swapperLinZ(foregroundDepth, near, far * 4.0);
				depthViewPos = clipToViewSpace(foregroundUV, foregroundDepth, 0.0);
				return makeDepthSample(depth, foregroundDepth, depthViewPos, false, false);
			}

			if (waterSurfaceIsLOD && foregroundDepth < 1.0) {
				depth = swapperLinZ(foregroundDepth, near, far * 4.0);
				depthViewPos = clipToViewSpace(foregroundUV, foregroundDepth, 0.0);
				return makeDepthSample(depth, foregroundDepth, depthViewPos, false, false);
			}

			if (waterSurfaceIsLOD) {
				depth = swapperLinZ(waterDepth, LOD_NEARPLANE + far, LOD_FARPLANE);
				depthViewPos = clipToViewSpace(waterUV, 1.0, waterDepth);
				return makeDepthSample(depth, waterDepth, depthViewPos, true, true);
			}

			depth = swapperLinZ(waterDepth, near, far * 4.0);
			depthViewPos = clipToViewSpace(waterUV, waterDepth, 0.0);
			return makeDepthSample(depth, waterDepth, depthViewPos, false, true);
		}

		if (water00 || water10 || water01 || water11) {
			return makeDepthSample(1.0, 1.0, vec3(0.0), false, true);
		}
	}

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

	return makeDepthSample(depth, depthRaw, depthViewPos, depthIsLOD, depthIsWaterSurface);
}

bool isWithinViewBounds(in vec2 pos) {
	vec2 viewBounds = 2.0 / vec2(viewWidth, viewHeight) * RENDER_SCALE;
	return !(pos.x <= viewBounds.x || pos.x >= RENDER_SCALE.x - viewBounds.x || pos.y <= viewBounds.y || pos.y >= RENDER_SCALE.y - viewBounds.y);
}

// Daylight Disocclusion

float getSunAngleDisocclusionFactor() {
	// Returns 1.0 when sun is unobstructable (e.g. noon) and 0.0 when near horizon (e.g. sunrise and sunset).

	const float HOURS_PER_HALF_DAY = 12.0;
	const float HORIZON_ANGLE = PI * 0.5;

	const float sunAngleEventOffsetHours = 1.5;
	const float sunAngleTransitionHours = 1.0;

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

// Sun Shadow

struct SunShadowRay {
	vec3 clipStart;
	vec3 clipStep;
	vec3 viewStart;
	vec3 viewStep;
	float pointDistance;
	float rayLength;
	int sampleCount;
	bool depthCheck;
};

// Helpers

const int SUN_SHADOW_SUPPORT_WINDOW = 4;
const float SUN_SHADOW_SUPPORT_THRESHOLD = 2.6;
const float SUN_SHADOW_BOOTSTRAP_STEPS = 2.0;
const float SUN_SHADOW_START_JITTER = 0.45;
const float SUN_SHADOW_FETCH_JITTER = 0.65;
const float SUN_SHADOW_VANILLA_THICKNESS = 2.0;
const float SUN_SHADOW_LOD_THICKNESS = 5.0;
const int SUN_SHADOW_KERNEL_TAPS = 7;
// Fraction of the sample budget spent on the coarse uniform scan.
// The remainder is used for binary-search refinement around the first detected shadow edge.
const float SUN_SHADOW_COARSE_RATIO = 0.65;

float getSunFacingFactor(in vec3 viewPos, in vec3 lightDir) {
	float pointDistance = length(viewPos);

	if (pointDistance <= 1e-4) {
		return 0.0;
	}

	return smoothstep(0.15, 0.65, dot(viewPos / pointDistance, normalize(lightDir)));
}

bool shouldSkipSunShadow(float pointDistance, float sunFacingFactor, float sunAngleFactor, int maxSamples, float maxDistance) {
	return maxSamples <= 0 || pointDistance > maxDistance || sunAngleFactor >= 0.99 || sunFacingFactor <= 0.0;
}

float getSunShadowDistanceFade(float pointDistance, float maxDistance) {
	float fadeDistance = max(maxDistance * 0.25, 1e-4);
	float fadeStart = max(maxDistance - fadeDistance, 0.0);

	return 1.0 - smoothstep(fadeStart, maxDistance, pointDistance);
}

float getSunShadowRayDepth(in vec3 viewPos, bool depthCheck) {
	vec3 clipPos = toClipSpace3_DH(viewPos, depthCheck);

	if (depthCheck) {
		return swapperLinZ(clipPos.z, LOD_NEARPLANE + far, LOD_FARPLANE);
	}

	return swapperLinZ(clipPos.z, near, far * 4.0);
}

vec2 getSunShadowKernelOffset(int kernelIndex, int tapIndex) {
	if (kernelIndex == 0) {
		if (tapIndex == 0) {
			return vec2(0.0, 0.0);
		}
		if (tapIndex == 1) {
			return vec2(-1.0, 0.0);
		}
		if (tapIndex == 2) {
			return vec2(1.0, 0.0);
		}
		if (tapIndex == 3) {
			return vec2(0.0, -1.0);
		}
		if (tapIndex == 4) {
			return vec2(0.0, 1.0);
		}
		if (tapIndex == 5) {
			return vec2(-1.0, -1.0);
		}
		return vec2(1.0, 1.0);
	}

	if (kernelIndex == 1) {
		if (tapIndex == 0) {
			return vec2(0.0, 0.0);
		}
		if (tapIndex == 1) {
			return vec2(-1.0, 0.0);
		}
		if (tapIndex == 2) {
			return vec2(1.0, 0.0);
		}
		if (tapIndex == 3) {
			return vec2(0.0, -1.0);
		}
		if (tapIndex == 4) {
			return vec2(0.0, 1.0);
		}
		if (tapIndex == 5) {
			return vec2(1.0, -1.0);
		}
		return vec2(-1.0, 1.0);
	}

	if (kernelIndex == 2) {
		if (tapIndex == 0) {
			return vec2(0.0, 0.0);
		}
		if (tapIndex == 1) {
			return vec2(-1.0, -1.0);
		}
		if (tapIndex == 2) {
			return vec2(1.0, -1.0);
		}
		if (tapIndex == 3) {
			return vec2(-1.0, 1.0);
		}
		if (tapIndex == 4) {
			return vec2(1.0, 1.0);
		}
		if (tapIndex == 5) {
			return vec2(-1.0, 0.0);
		}
		return vec2(1.0, 0.0);
	}

	if (tapIndex == 0) {
		return vec2(0.0, 0.0);
	}
	if (tapIndex == 1) {
		return vec2(-1.0, -1.0);
	}
	if (tapIndex == 2) {
		return vec2(1.0, -1.0);
	}
	if (tapIndex == 3) {
		return vec2(-1.0, 1.0);
	}
	if (tapIndex == 4) {
		return vec2(1.0, 1.0);
	}
	if (tapIndex == 5) {
		return vec2(0.0, -1.0);
	}
	return vec2(0.0, 1.0);
}

vec2 getSunShadowFetchJitter(float stepSeed, int stepIndex) {
	vec2 pixelStep = texelSize * RENDER_SCALE;
	float sequenceIndex = float(stepIndex) + stepSeed * 17.0 + 1.0;
	vec2 r2 = fract(vec2(0.75487765, 0.56984026) * sequenceIndex) - 0.5;

	return r2 * pixelStep * SUN_SHADOW_FETCH_JITTER;
}

DepthSample getSunOcclusionDepthSample(in vec2 pos, float kernelNoise, vec2 fetchJitter, bool waterSurfaceCap, sampler2D waterMaskTex) {
	vec2 pixelStep = texelSize * RENDER_SCALE;
	int kernelIndex = min(int(floor(kernelNoise * 4.0)), 3);

	vec2 kernelOffset = getSunShadowKernelOffset(kernelIndex, 0) * pixelStep;
	DepthSample bestSample = getDepthSample(pos + fetchJitter + kernelOffset, waterSurfaceCap, waterMaskTex);

	for (int tapIndex = 1; tapIndex < SUN_SHADOW_KERNEL_TAPS; tapIndex++) {
		kernelOffset = getSunShadowKernelOffset(kernelIndex, tapIndex) * pixelStep;
		DepthSample candidateSample = getDepthSample(pos + fetchJitter + kernelOffset, waterSurfaceCap, waterMaskTex);

		if (candidateSample.value < bestSample.value) {
			bestSample = candidateSample;
		}
	}

	return bestSample;
}

SunShadowRay setupSunShadowRay(in vec3 viewPos, in vec3 lightDir, float maxSampleDistance, int maxSamples, bool fast, bool sourceIsLOD) {
	SunShadowRay ray;

	ray.pointDistance = length(viewPos);
	ray.depthCheck = sourceIsLOD;
	ray.sampleCount = fast ? max(1, min(maxSamples, max(maxSamples / 2, 4))) : max(1, maxSamples);

	float clipNear = ray.depthCheck ? LOD_NEARPLANE : near;
	float clipFar = ray.depthCheck ? LOD_FARPLANE : far * 4.0;
	float rayLength = clipFar * sqrt(3.0);

	if (abs(lightDir.z) > 1e-4 && (viewPos.z + lightDir.z * rayLength) > -clipNear) {
		rayLength = (-clipNear - viewPos.z) / lightDir.z;
	}

	ray.rayLength = clamp(min(rayLength, maxSampleDistance), 0.0, maxSampleDistance);

	vec3 rayEndViewPos = viewPos + lightDir * ray.rayLength;
	vec3 clipStart = viewToClipSpace(viewPos, ray.depthCheck);
	vec3 clipEnd = viewToClipSpace(rayEndViewPos, ray.depthCheck);
	float sampleCount = max(float(ray.sampleCount), 1.0);

	ray.clipStart = clipStart;
	ray.clipStep = (clipEnd - clipStart) / sampleCount;
	ray.viewStart = viewPos;
	ray.viewStep = (rayEndViewPos - viewPos) / sampleCount;

	return ray;
}

float getSunShadowThinGeometryScale() {
	float thinGeometryRejection = clamp(DH_VOLUMETRIC_OCCLUSION_BIAS, 0.0, 1.0);
	return mix(1.0, 0.35, thinGeometryRejection);
}

float getSunShadowBlockerThickness(DepthSample depthSample, float rayDepth) {
	const float depthBias = 0.05;
	float thicknessScale = depthSample.isLOD ? SUN_SHADOW_LOD_THICKNESS : SUN_SHADOW_VANILLA_THICKNESS;
	float blockerThickness = max(thicknessScale, rayDepth * depthBias * thicknessScale);

	return blockerThickness * getSunShadowThinGeometryScale();
}

bool isSunShadowBlockerCandidate(DepthSample depthSample, float rayDepth) {
	if (depthSample.isWaterSurface) {
		return false;
	}

	if (!depthSample.isLOD && depthSample.raw >= 1.0) {
		return false;
	}

	float depthDelta = rayDepth - depthSample.value;
	if (depthDelta <= 0.0) {
		return false;
	}

	float blockerThickness = getSunShadowBlockerThickness(depthSample, rayDepth);

	return depthDelta <= blockerThickness;
}

float getSunShadowBlockerSupport(DepthSample depthSample, float rayDepth, float sampleIndex) {
	if (!isSunShadowBlockerCandidate(depthSample, rayDepth)) {
		return 0.0;
	}

	float blockerThickness = getSunShadowBlockerThickness(depthSample, rayDepth);
	float depthDelta = rayDepth - depthSample.value;
	float normalizedCoverage = 1.0 - clamp(depthDelta / max(blockerThickness, 1e-4), 0.0, 1.0);
	float coverageWeight = smoothstep(0.05, 0.85, normalizedCoverage);
	float bootstrapWeight = sampleIndex < SUN_SHADOW_BOOTSTRAP_STEPS ? 1.35 : 1.0;

	return coverageWeight * bootstrapWeight;
}

float getViewPosPlayerY(in vec3 viewPos) {
	return (mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz).y;
}

bool isRejectedWaterSurfaceBlocker(DepthSample depthSample, bool waterSurfaceCap, float waterSurfacePlayerY) {
	if (!waterSurfaceCap || depthSample.isWaterSurface) {
		return false;
	}

	return getViewPosPlayerY(depthSample.pos) < waterSurfacePlayerY - 0.25;
}

float finalizeSunShadow(float baseOcclusion, float sunFacingFactor, float sunAngleFactor, float distanceFade) {
	return clamp(baseOcclusion * sunFacingFactor * (1.0 - sunAngleFactor) * distanceFade, 0.0, 1.0);
}


float getSunShadow(
	in vec3 viewPos,
	in vec3 lightDir,
	bool sourceIsLOD,
	bool fast,
	float noise,
	bool waterSurfaceCap,
	sampler2D waterMaskTex
) {
	// This is the function.

	// It should provide a reasonable level of sun shadowing from the sampled position towards the sun.

	// Occlusion between the player and the sun should be prioritised while arbitrary positions in the 
	// landscape where the player isn't even facing the sun should be ignored. This will also help us prevent overt artifacting.
	// Its main job is to detect large occluders (e.g. mountains) while thing occluders (trees) can be safely ignored.
	// The occlusion value itself should later be usable to suppress volumetric effects caused by direct sunlight.

	// Also use sun angle disocclusion to detect when sun occlusion is practically impossible due to steep angles.
	// Leave this instruction comment intant and add your code below.

	const int maxSamples = DH_VOLUMETRIC_OCCLUSION_SAMPLES;			// Max number of samples, configurable performance option.
	const float maxSampleDistance = DH_VOLUMETRIC_OCCLUSION_LENGTH;	// Max length for an occlusion ray cast if applicable.
	const float maxDistance = DH_VOLUMETRIC_OCCLUSION_DISTANCE;		// Max distance between player camera and sampled point.

	float sunAngleFactor = getSunAngleDisocclusionFactor();
	float sunFacingFactor = getSunFacingFactor(viewPos, lightDir);
	float startNoise = hashNoise(noise + 0.17);
	float kernelNoise = hashNoise(noise + 11.13);
	float stepSeed = hashNoise(noise + 23.71);
	float waterSurfacePlayerY = getViewPosPlayerY(viewPos);

	SunShadowRay ray = setupSunShadowRay(viewPos, lightDir, maxSampleDistance, maxSamples, fast, sourceIsLOD);

	if (shouldSkipSunShadow(ray.pointDistance, sunFacingFactor, sunAngleFactor, maxSamples, maxDistance) || ray.rayLength <= 0.0) {
		return 0.0;
	}

	float distanceFade = getSunShadowDistanceFade(ray.pointDistance, maxDistance);

	float currentStreak = 0.0;
	float maxStreak = 0.0;
	float supportWindow[SUN_SHADOW_SUPPORT_WINDOW] = float[](0.0, 0.0, 0.0, 0.0);
	float supportTotal = 0.0;
	float maxSupport = 0.0;
	float stepOffset = startNoise * SUN_SHADOW_START_JITTER;

	// Derived full-ray vectors so both phases can address any t in [0,1].
	vec3 clipFull = ray.clipStep * float(ray.sampleCount);
	vec3 viewFull = ray.viewStep * float(ray.sampleCount);

	// Split sample budget: coarse scan then bisection.
	int coarseCount = max(2, int(float(ray.sampleCount) * SUN_SHADOW_COARSE_RATIO));
	int refineCount = ray.sampleCount - coarseCount;

	// Phase 1: Uniform coarse scan
	
	// Identical blocker/support logic to the previous single-pass march.
	// Tracks the last clear and first hit normalised positions along the ray
	// so phase 2 knows exactly where to bisect.

	float lastClearT = 0.0;
	float firstHitT  = 1.0;
	bool  hitFound   = false;
	bool  earlyExited = false;

	for (int i = 0; i < maxSamples; i++) {
		if (i >= coarseCount) {
			break;
		}

		float t = (float(i) + stepOffset) / float(coarseCount);
		vec3 coarseClipPos = ray.clipStart + clipFull * t;
		vec3 coarseViewPos = ray.viewStart + viewFull * t;

		if (!isWithinViewBounds(coarseClipPos.xy)) {
			break;
		}

		float rayDepth = getSunShadowRayDepth(coarseViewPos, ray.depthCheck);
		vec2 fetchJitter = getSunShadowFetchJitter(stepSeed, i);
		DepthSample depthSample = getSunOcclusionDepthSample(coarseClipPos.xy, kernelNoise, fetchJitter, waterSurfaceCap, waterMaskTex);

		float support = isRejectedWaterSurfaceBlocker(depthSample, waterSurfaceCap, waterSurfacePlayerY) ? 0.0 : getSunShadowBlockerSupport(depthSample, rayDepth, float(i));

		supportTotal -= supportWindow[i % SUN_SHADOW_SUPPORT_WINDOW];
		supportWindow[i % SUN_SHADOW_SUPPORT_WINDOW] = support;
		supportTotal += support;
		maxSupport = max(maxSupport, supportTotal);

		if (support > 0.0) {
			currentStreak += 1.0;
			maxStreak = max(maxStreak, currentStreak);

			if (!hitFound) {
				firstHitT = t;
				hitFound  = true;
			}

			if (fast && supportTotal >= SUN_SHADOW_SUPPORT_THRESHOLD) {
				earlyExited = true;
				break;
			}
		} else {
			currentStreak = 0.0;
			if (!hitFound) {
				lastClearT = t;
			}
		}
	}

	// Phase 2: Binary-search refinement (between lastClearT and firstHitT)

	// Only runs when a blocker was found in the coarse scan and the fast path
	// did not already reach full confidence. Bisection samples land spatially
	// clustered at the mountain edge, so they contribute positively to both the
	// streak and support accumulators, sharpening the shadow boundary.

	if (hitFound && !earlyExited && refineCount > 0) {
		float loT = lastClearT;
		float hiT = firstHitT;

		for (int i = 0; i < maxSamples; i++) {
			if (i >= refineCount) {
				break;
			}

			int globalIndex = coarseCount + i;
			float midT = (loT + hiT) * 0.5;
			vec3 refineClipPos = ray.clipStart + clipFull * midT;
			vec3 refineViewPos = ray.viewStart + viewFull * midT;

			if (!isWithinViewBounds(refineClipPos.xy)) {
				break;
			}

			float rayDepth = getSunShadowRayDepth(refineViewPos, ray.depthCheck);
			vec2 fetchJitter = getSunShadowFetchJitter(stepSeed, globalIndex);
			DepthSample depthSample = getSunOcclusionDepthSample(refineClipPos.xy, kernelNoise, fetchJitter, waterSurfaceCap, waterMaskTex);

			float support = isRejectedWaterSurfaceBlocker(depthSample, waterSurfaceCap, waterSurfacePlayerY) ? 0.0 : getSunShadowBlockerSupport(depthSample, rayDepth, float(globalIndex));

			supportTotal -= supportWindow[globalIndex % SUN_SHADOW_SUPPORT_WINDOW];
			supportWindow[globalIndex % SUN_SHADOW_SUPPORT_WINDOW] = support;
			supportTotal += support;
			maxSupport = max(maxSupport, supportTotal);

			if (support > 0.0) {
				currentStreak += 1.0;
				maxStreak = max(maxStreak, currentStreak);
				hiT = midT; // edge is closer than midpoint; narrow towards viewer
			} else {
				currentStreak = 0.0;
				loT = midT; // edge is further than midpoint; narrow towards sun
			}
		}
	}

	float streakThreshold = fast ? 3.0 : 4.0;
	float streakOcclusion = smoothstep(2.0, streakThreshold, maxStreak);
	float supportOcclusion = smoothstep(1.8, SUN_SHADOW_SUPPORT_THRESHOLD, maxSupport);
	float baseOcclusion = max(streakOcclusion * 0.6, supportOcclusion);

	return finalizeSunShadow(baseOcclusion, sunFacingFactor, sunAngleFactor, distanceFade);
}
