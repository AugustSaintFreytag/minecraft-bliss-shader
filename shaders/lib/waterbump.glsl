float waterCaustics(vec3 worldPos, vec3 sunVec, float surfacePos) {

	vec3 projectedPos = worldPos + (sunVec/abs(sunVec.y))*surfacePos;
	vec2 pos = projectedPos.xz;
	

	float movement = frameTimeCounter * 0.035 * WATER_WAVE_SPEED;

	float radiance = 2.39996;
	mat2 rotationMatrix  = mat2(vec2(cos(radiance),  -sin(radiance)),  vec2(sin(radiance),  cos(radiance)));

 	vec2 wave_size[3] = vec2[](
		vec2(48.,12.),
		vec2(12.,48.),
		vec2(32.,32.)
	);

	float largeWaves = texture(noisetex, pos / 600.0 ).b;
	float largeWavesCurved = pow(1.0-pow(1.0-largeWaves,2.5),4.5);

	float heightSum = 0.0;
	for (int i = 0; i < 3; i++){
		pos = rotationMatrix * pos;
		heightSum += pow(abs(abs(texture(noisetex, pos / wave_size[i] + largeWavesCurved * 0.5 + movement).b * 2.0 - 1.0) * 2.0 - 1.0), 1.0+largeWavesCurved) ;
	}

	return exp((1.0 + 5.0 * sqrt(largeWavesCurved)) * (heightSum / 3.0 - 0.5));

}

float getWaterHeightmap(vec2 posxz, in float largeWaves, in float largeWavesCurved) {
	vec2 pos = posxz;

	float movement = frameTimeCounter * 0.035 * WATER_WAVE_SPEED;

	float radiance = 2.39996;
	mat2 rotationMatrix  = mat2(vec2(cos(radiance),  -sin(radiance)),  vec2(sin(radiance),  cos(radiance)));

 	vec2 wave_size[3] = vec2[](
		vec2(48.,12.),
		vec2(12.,48.),
		vec2(32.,32.)
	);


	float heightSum = 0.0;
	for (int i = 0; i < 3; i++){

		pos = rotationMatrix * pos;
		heightSum += texture(noisetex, pos / wave_size[i] + largeWavesCurved * 0.5 + movement).b;
	}

	return (heightSum/4.5) * max(largeWavesCurved,0.3);
}

float waterRippleHash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 waterRippleHash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 waterRippleHash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float getRainRippleLattice(vec2 posxz, float cellSize, float rippleSpeed, float rippleRadius, float rippleWidth, float spawnChance, float seed, float amplitude) {
	vec2 gridPos = posxz / cellSize;
	vec2 baseCell = floor(gridPos);
	float height = 0.0;

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 cell = baseCell + vec2(float(x), float(y));
			vec2 stableSeed = cell + vec2(seed, seed * 1.37);

			float eventRate = rippleSpeed * mix(0.7, 1.6, waterRippleHash12(stableSeed + vec2(3.17, 9.43)));
			float phase = waterRippleHash12(stableSeed + vec2(17.11, 41.73));
			float timeline = frameTimeCounter * eventRate + phase;
			float baseCycle = floor(timeline);
			float baseAge = fract(timeline);

			for (int eventOffset = 0; eventOffset < 2; eventOffset++) {
				float cycle = baseCycle - float(eventOffset);
				float age = baseAge + float(eventOffset);

				vec2 eventSeed = stableSeed + vec2(cycle * 17.0, cycle * 29.0);
				vec3 rippleA = waterRippleHash32(eventSeed);
				vec3 rippleB = waterRippleHash32(eventSeed + vec2(57.23, 19.91));

				float active = step(1.0 - spawnChance, rippleB.z);
				float growth = mix(0.75, 1.15, waterRippleHash12(eventSeed + vec2(7.13, 83.19)));

				vec2 center = (cell + mix(vec2(0.08), vec2(0.92), rippleA.xy)) * cellSize;
				float radius = age * cellSize * rippleRadius * growth * mix(0.45, 1.35, rippleA.z);
				float width = cellSize * rippleWidth * mix(0.75, 1.25, rippleB.x);
				float distFromRing = abs(length(posxz - center) - radius);
				float ring = exp(-distFromRing * distFromRing / max(width * width, 0.0001));
				float envelope = smoothstep(0.03, 0.16, age) * (1.0 - smoothstep(1.45, 2.0, age));

				height += ring * envelope * active * mix(0.6, 1.2, rippleB.y);
			}
		}
	}

	return height * amplitude;
}

float getRainRippleHeight(vec2 posxz, float rainRippleAmount, bool isLOD) {
	#ifdef WATER_RAIN_RIPPLES
		float cellSize = 3.5;
		float rippleSpeed = 1.25;
		float rippleRadius = 0.29;
		float rippleWidth = 0.07;
		float spawnChance = 0.72;
		float lodMult = 1.0;
		float rippleSize = WATER_RAIN_RIPPLE_SIZE;
		float rippleDensity = WATER_RAIN_RIPPLE_DENSITY;

		if (isLOD) {
			cellSize = 8.0;
			rippleSpeed = 0.72;
			rippleRadius = 0.22;
			rippleWidth = 0.09;
			spawnChance = 0.45;
			lodMult = 0.18;
		}

		spawnChance = clamp(spawnChance * min(rippleDensity, 1.5), 0.0, 0.95);

		float sizedRadius = rippleRadius * rippleSize;
		float sizedWidth = rippleWidth * rippleSize;
		float height = getRainRippleLattice(posxz, cellSize, rippleSpeed, sizedRadius, sizedWidth, spawnChance, 11.0, 1.0);

		mat2 rippleRotation = mat2(0.819152, -0.573576, 0.573576, 0.819152);
		vec2 offsetPos = rippleRotation * posxz + vec2(19.17, -11.73);
		height += getRainRippleLattice(offsetPos, cellSize * 1.27, rippleSpeed * 0.83, sizedRadius * 0.92, sizedWidth * 1.08, spawnChance * 0.55, 53.0, 0.45);

		float extraDensity = max(rippleDensity - 1.0, 0.0);
		if (extraDensity > 0.001) {
			vec2 densePos = mat2(0.342020, -0.939693, 0.939693, 0.342020) * posxz + vec2(-31.41, 24.63);
			float denseAmplitude = min(extraDensity * 0.28, 0.75);
			height += getRainRippleLattice(densePos, cellSize * 0.91, rippleSpeed * 1.09, sizedRadius * 0.84, sizedWidth * 0.96, spawnChance * 0.68, 97.0, denseAmplitude);
		}

		if (extraDensity > 2.0) {
			vec2 densePos = mat2(-0.173648, -0.984808, 0.984808, -0.173648) * posxz + vec2(43.89, 7.52);
			float denseAmplitude = min((extraDensity - 2.0) * 0.18, 0.55);
			height += getRainRippleLattice(densePos, cellSize * 1.43, rippleSpeed * 0.76, sizedRadius * 1.05, sizedWidth * 1.12, spawnChance * 0.5, 149.0, denseAmplitude);
		}

		return height * rainRippleAmount * WATER_RAIN_RIPPLE_STRENGTH * lodMult;
	#else
		return 0.0;
	#endif
}

vec3 getWaveNormal(vec3 waterPos, vec3 playerpos, bool isLOD, float rainRippleAmount){
	
	float largeWaves = texture(noisetex, waterPos.xy / 600.0 ).b;
	float largeWavesCurved = pow(1.0-pow(1.0-largeWaves,2.5),4.5);
	
	#ifdef HYPER_DETAILED_WAVES
		float deltaPos = 0.025;
	#else
		float deltaPos = mix(1.0, 0.15, largeWavesCurved);
		// reduce high frequency detail as distance increases. reduces noise on waves. why have more details than pixels?
		float range = min(length(playerpos) / (16.0*24.0), 3.0);
		deltaPos += range;
	#endif

	vec2 coord = waterPos.xy;

	float rainRippleFade = clamp(1.0 - length(playerpos) / 192.0, 0.0, 1.0);
	if (isLOD) rainRippleFade = clamp(1.0 - length(playerpos) / 512.0, 0.0, 1.0) * 0.45;
	rainRippleAmount = clamp(rainRippleAmount, 0.0, 1.0) * rainRippleFade;

	float h0 = getWaterHeightmap(coord, largeWaves, largeWavesCurved);
	float h1 = getWaterHeightmap(coord + vec2(deltaPos,0.0), largeWaves,largeWavesCurved);
	float h3 = getWaterHeightmap(coord + vec2(0.0,deltaPos), largeWaves,largeWavesCurved);

	if (rainRippleAmount > 0.001) {
		h0 += getRainRippleHeight(coord, rainRippleAmount, isLOD);
		h1 += getRainRippleHeight(coord + vec2(deltaPos,0.0), rainRippleAmount, isLOD);
		h3 += getRainRippleHeight(coord + vec2(0.0,deltaPos), rainRippleAmount, isLOD);
	}

	float xDelta = (h1-h0)/deltaPos;
	float yDelta = (h3-h0)/deltaPos;

	vec3 wave = normalize(vec3(xDelta, yDelta, 1.0-pow(abs(xDelta+yDelta),2.0)));

	return wave;
}
