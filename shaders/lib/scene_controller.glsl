#if !defined READ_SCENE_CONTROLLER_PARAMETERS
#if defined USE_SCENE_CONTROLLER_SETTINGS

uniform int worldDay;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPosition;

uniform bool isInColdArea;
uniform bool isInHotArea;
uniform bool isInJungleBiomes;
uniform bool isInSwampBiomes;
uniform bool isInSpecialEnvironment;
uniform bool isInSnowFallEnvironment;
uniform bool isInRainFallEnvironment;
uniform bool isInNoRainFallEnvironment;

uniform int worldTime;

#define DECLARE_UNIFORMS_OR_WRITE_FUNCTIONS_FOR_CUSTOM_SCENE_CONTROLLER_PROFILES
#include "/CUSTOM_SCENE_PARAMETERS.glsl"

// https://www.shadertoy.com/view/llGSzw
float hash11( uint n ) 
{
    // integer hash copied from Hugo Elias
	n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float( n & uint(0x7fffffffU))/float(0x7fffffff);
}

bool playerIsWithinArea(in vec3 positionA, in vec3 positionB){
    return cameraPositionInt.x > positionA.x && cameraPositionInt.y > positionA.y && cameraPositionInt.z > positionA.z && cameraPositionInt.x < positionB.x && cameraPositionInt.y < positionB.y && cameraPositionInt.z < positionB.z; 
}

bool playerIsOutsideArea(in vec3 positionA, in vec3 positionB){
    return !(cameraPositionInt.x > positionA.x && cameraPositionInt.y > positionA.y && cameraPositionInt.z > positionA.z && cameraPositionInt.x < positionB.x && cameraPositionInt.y < positionB.y && cameraPositionInt.z < positionB.z); 
}

vec4 timesOfDay(){
	float time = float(worldTime%24000);

	// set schedules for fog to appear at specific ranges of time in the day.
	float morning = clamp((time-22000.0)/2000.0,0.0,1.0) + clamp((2000.0-time)/2000.0,0.0,1.0);
	float noon 	  = clamp(time/2000.0,0.0,1.0) * clamp((12000.0-time)/2000.0,0.0,1.0);
	float evening = clamp((time-10000.0)/2000.0,0.0,1.0) * clamp((14000.0-time)/2000.0,0.0,1.0);
	float night   = clamp((time-13000.0)/2000.0,0.0,1.0) * clamp((23000.0-time)/2000.0,0.0,1.0);

    return (float(TOD_FOG_AMOUNT) / 100.0) * vec4(morning, noon, evening, night);
}
void applySceneControllerParameters(
	out float smallCumulusCoverage, out float smallCumulusDensity,
	out float largeCumulusCoverage, out float largeCumulusDensity,
	out float altostratusCoverage, out float altostratusDensity,
	out float uniformFogDensity, out float clumpyFogDensity, out float clumpyFogCoverage,
    out float localUniformFogDensity, out float localClumpyFogDensity, out float localClumpyFogCoverage, out vec3 localFogColor
){
    // these are the default parameters if no "trigger" or custom uniform is being used.
    // do not remove them
    smallCumulusCoverage = 0.0;
	smallCumulusDensity = 0.0;
	largeCumulusCoverage = 0.0;
    largeCumulusDensity = 0.0;
	altostratusCoverage = 0.0;
    altostratusDensity = 0.0;
	uniformFogDensity = 0.0;
    clumpyFogDensity = 0.0;
    clumpyFogCoverage = 0.0;

    localUniformFogDensity = 0.0;
    localClumpyFogDensity = 0.0;
    localClumpyFogCoverage = -1.0;
    localFogColor = vec3(1.0);

// the seed is the in-game day counter. 
// give a random value within the range 0.0-1.0 which is scaled up to the wanted range, and then quantized to choose a profile
float RNG = hash11(worldDay + 0.2);

#if USE_CUSTOM_DAILY_WEATHER_PROFILE == 0
    int dailyWeatherProfile = int(RNG * 11.0);
    switch (dailyWeatherProfile){
        default: {
            // Clear & Crisp
            smallCumulusCoverage = 0.0;
            largeCumulusCoverage = 0.0;
            altostratusCoverage = 0.0;

            smallCumulusDensity = 0.0;
            largeCumulusDensity = 0.0;
            altostratusDensity = 0.0;

            uniformFogDensity = 0.0;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 1: {
            // Clear, Lightly Cloudy
            smallCumulusCoverage = 0.5;
            largeCumulusCoverage = 0.4;
            altostratusCoverage = 0.8;

            smallCumulusDensity = 0.2;
            largeCumulusDensity = 0.2;
            altostratusDensity = 0.25;

            uniformFogDensity = 0.0;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 2: {
            // Clear, Lightly Cloudy, Chunky
            smallCumulusCoverage = 0.6;
            largeCumulusCoverage = 0.7;
            altostratusCoverage = 0.5;

            smallCumulusDensity = 0.25;
            largeCumulusDensity = 0.75;
            altostratusDensity = 0.1;

            uniformFogDensity = 0.0;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 3: {
            // Clear, Lightly Cloudy, w/ Cloudy Fog
            smallCumulusCoverage = 0.0;
            largeCumulusCoverage = 0.5;
            altostratusCoverage = 1.0;

            smallCumulusDensity = 0.0;
            largeCumulusDensity = 0.2;
            altostratusDensity = 0.2;

            uniformFogDensity = 0.1;
            clumpyFogDensity = 0.4;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 4: {
            // Lightly Overcast
            smallCumulusCoverage = 0.0;
            largeCumulusCoverage = 0.9;
            altostratusCoverage = 1.0;

            smallCumulusDensity = 0.0;
            largeCumulusDensity = 0.5;
            altostratusDensity = 0.5;

            uniformFogDensity = 0.0;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 5: {
            // Overcast w/ Cloudy Fog
            smallCumulusCoverage = 0.8;
            largeCumulusCoverage = 0.0;
            altostratusCoverage = 1.2;

            smallCumulusDensity = 0.5;
            largeCumulusDensity = 0.45;
            altostratusDensity = 0.85;

            uniformFogDensity = 0.15;
            clumpyFogDensity = 0.25;
            clumpyFogCoverage = 0.3;
            break;
        }
        case 6: {
            // Overcast, Foggy, w/ Distant Fog
            smallCumulusCoverage = 0.0;
            largeCumulusCoverage = 0.0;
            altostratusCoverage = 1.4;

            smallCumulusDensity = 0.0;
            largeCumulusDensity = 0.0;
            altostratusDensity = 0.5;

            uniformFogDensity = 0.2;
            clumpyFogDensity = 0.25;
            clumpyFogCoverage = 0.2;
            break;
        }
        case 7: {
            // Dark Overcast
            smallCumulusCoverage = 1.3;
            largeCumulusCoverage = 0.0;
            altostratusCoverage = 1.0;

            smallCumulusDensity = 0.35;
            largeCumulusDensity = 0.1;
            altostratusDensity = 0.5;

            uniformFogDensity = 0.05;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 8: {
            // Dark Overcast, w/ Minor Fog
            smallCumulusCoverage = 0.7;
            largeCumulusCoverage = 1.0;
            altostratusCoverage = 1.3;

            smallCumulusDensity = 0.9;
            largeCumulusDensity = 0.85;
            altostratusDensity = 1.0;

            uniformFogDensity = 0.08;
            clumpyFogDensity = 0.4;
            clumpyFogCoverage = 0.1;
            break;
        }
        case 9: {
            // Mixed Overcast
            smallCumulusCoverage = 0.0;
            largeCumulusCoverage = 0.8;
            altostratusCoverage = 0.9;

            smallCumulusDensity = 0.0;
            largeCumulusDensity = 0.6;
            altostratusDensity = 0.9;

            uniformFogDensity = 0.0;
            clumpyFogDensity = 0.0;
            clumpyFogCoverage = 0.0;
            break;
        }
        case 10: {
            // Heavy Fog (Sea of Trees)
            smallCumulusCoverage = 1.0;
            largeCumulusCoverage = 1.2;
            altostratusCoverage = 1.0;

            smallCumulusDensity = 0.25;
            largeCumulusDensity = 0.7;
            altostratusDensity = 0.5;

            uniformFogDensity = 0.25;
            clumpyFogDensity = 0.85;
            clumpyFogCoverage = 0.3;
            break;
        }
    }
#endif
#if USE_CUSTOM_DAILY_WEATHER_PROFILE > 0
    int customDailyWeatherProfile = int(RNG * float(USE_CUSTOM_DAILY_WEATHER_PROFILE));
    switch (customDailyWeatherProfile){
        default : {
            smallCumulusCoverage = DAILY_PROFILE_1_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_1_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_1_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_1_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_1_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_1_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_1_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_1_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_1_CLUMPY_FOG_COVERAGE;
            break;
        }
    #if USE_CUSTOM_DAILY_WEATHER_PROFILE >= 2
        case 1: {
            smallCumulusCoverage = DAILY_PROFILE_2_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_2_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_2_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_2_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_2_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_2_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_2_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_2_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_2_CLUMPY_FOG_COVERAGE;
            break;
        }
    #endif
    #if USE_CUSTOM_DAILY_WEATHER_PROFILE >= 3
        case 2: {
            smallCumulusCoverage = DAILY_PROFILE_3_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_3_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_3_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_3_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_3_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_3_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_3_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_3_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_3_CLUMPY_FOG_COVERAGE;
            break;
        }
    #endif
    #if USE_CUSTOM_DAILY_WEATHER_PROFILE >= 4
        case 3: {
            smallCumulusCoverage = DAILY_PROFILE_4_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_4_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_4_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_4_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_4_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_4_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_4_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_4_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_4_CLUMPY_FOG_COVERAGE;
            break;
        }
    #endif
    #if USE_CUSTOM_DAILY_WEATHER_PROFILE >= 5
        case 4: {
            smallCumulusCoverage = DAILY_PROFILE_5_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_5_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_5_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_5_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_5_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_5_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_5_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_5_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_5_CLUMPY_FOG_COVERAGE;
            break;
        }
    #endif
    #if USE_CUSTOM_DAILY_WEATHER_PROFILE >= 6
        case 5 : {
            smallCumulusCoverage = DAILY_PROFILE_6_LAYER0_COVERAGE;
            largeCumulusCoverage = DAILY_PROFILE_6_LAYER1_COVERAGE;
            altostratusCoverage =  DAILY_PROFILE_6_LAYER2_COVERAGE;
            smallCumulusDensity =  DAILY_PROFILE_6_LAYER0_DENSITY;
            largeCumulusDensity =  DAILY_PROFILE_6_LAYER1_DENSITY;
            altostratusDensity =   DAILY_PROFILE_6_LAYER2_DENSITY;
            uniformFogDensity = DAILY_PROFILE_6_UNIFORM_FOG;
            clumpyFogDensity = DAILY_PROFILE_6_CLUMPY_FOG;
            clumpyFogCoverage = DAILY_PROFILE_6_CLUMPY_FOG_COVERAGE;
            break;
        }
    #endif
    }
#endif

#if TOD_FOG_AMOUNT > 0
    vec4 timesOfDay = timesOfDay();
    float todUniformFogDensity = dot(timesOfDay, vec4(Morning_Uniform_Fog, Noon_Uniform_Fog, Evening_Uniform_Fog, Night_Uniform_Fog));
    float todClumpyFogDensity = dot(timesOfDay, vec4(Morning_Cloudy_Fog, Noon_Cloudy_Fog, Evening_Cloudy_Fog, Night_Cloudy_Fog));

    // uniformFogDensity = mix(todUniformFogDensity * TOD_FOG_BOOST, uniformFogDensity, TOD_FOG_MIX);
    // clumpyFogDensity = mix(todClumpyFogDensity * TOD_FOG_BOOST, clumpyFogDensity, TOD_FOG_MIX);
    // clumpyFogCoverage = mix(todClumpyFogDensity * (TOD_FOG_BOOST * 0.5), clumpyFogDensity, TOD_FOG_MIX);
    uniformFogDensity += todUniformFogDensity;
    clumpyFogDensity += todClumpyFogDensity;
    clumpyFogCoverage += clamp(clumpyFogCoverage + todClumpyFogDensity * 0.25, 0.0, 1.0);

#endif

if(rainStrength > 0.0001) {
    float weatherSmallCumulusCoverage = smallCumulusCoverage;
    float weatherSmallCumulusDensity = smallCumulusDensity;
    float weatherLargeCumulusCoverage = largeCumulusCoverage;
    float weatherLargeCumulusDensity  = largeCumulusDensity;
    float weatherAltostratusCoverage = altostratusCoverage;
    float weatherAltostratusDensity = altostratusDensity;
    float weatherUniformFogDensity = uniformFogDensity;
    float weatherClumpyFogDensity = clumpyFogDensity;
    float weatherClumpyFogCoverage = clumpyFogCoverage;

    #if USE_CUSTOM_DAILY_RAIN_PROFILE == 0
        int rainyWeatherProfile = int(RNG * 7.0);

        switch (rainyWeatherProfile) {
            ///////////////////////// TEMPERATE WEATHER PROFILES
            default: { 
                // Light Rain
                weatherSmallCumulusCoverage = 1.0;
	            weatherLargeCumulusCoverage = 1.2;
	            weatherAltostratusCoverage = 0.0;

                weatherSmallCumulusDensity = 0.7;
                weatherLargeCumulusDensity = 0.4;
	            weatherAltostratusDensity = 0.0;

	            weatherUniformFogDensity = 0.1;
                weatherClumpyFogDensity = 0.0;
                weatherClumpyFogCoverage = 0.0;
                break;
            }
            case 1: {
                // Light Rain
                weatherSmallCumulusCoverage = 0.0;
	            weatherLargeCumulusCoverage = 1.2;
	            weatherAltostratusCoverage = 1.0;

                weatherSmallCumulusDensity = 0.0;
                weatherLargeCumulusDensity = 0.35;
                weatherAltostratusDensity = 0.5;

	            weatherUniformFogDensity = 0.1;
                weatherClumpyFogDensity = 0.35;
                weatherClumpyFogCoverage = 0.0;
                break;
            }
            case 2: {
                // Medium Rain
                weatherSmallCumulusCoverage = 1.3;
	            weatherLargeCumulusCoverage = 1.0;
	            weatherAltostratusCoverage = 1.2;

                weatherSmallCumulusDensity = 0.65;
                weatherLargeCumulusDensity = 0.6;
	            weatherAltostratusDensity = 0.5;

	            weatherUniformFogDensity = 0.15;
                weatherClumpyFogDensity = 0.4;
                weatherClumpyFogCoverage = 0.0;
                break;
            }
            case 3: {
                // Medium Rain
                weatherSmallCumulusCoverage = 0.0;
	            weatherLargeCumulusCoverage = 1.3;
	            weatherAltostratusCoverage = 1.5;

                weatherSmallCumulusDensity = 0.0;
                weatherLargeCumulusDensity = 1.0;
	            weatherAltostratusDensity = 0.75;

	            weatherUniformFogDensity = 0.1;
                weatherClumpyFogDensity = 0.25;
                weatherClumpyFogCoverage = 0.5;
                break;
            }
            case 4: {
                // Heavy Rain w/ Cloudy Fog
                weatherSmallCumulusCoverage = 0.4;
	            weatherLargeCumulusCoverage = 1.5;
                weatherAltostratusCoverage = 1.2;

                weatherSmallCumulusDensity = 0.8;
                weatherLargeCumulusDensity = 0.8;
	            weatherAltostratusDensity = 0.7;

	            weatherUniformFogDensity = 0.15;
                weatherClumpyFogDensity = 0.5;
                weatherClumpyFogCoverage = 0.25;
                break;
            }
            case 5: {
                // Heavy Rain
                weatherSmallCumulusCoverage = 1.7;
	            weatherLargeCumulusCoverage = 1.0;
	            weatherAltostratusCoverage = 1.0;

                weatherSmallCumulusDensity = 0.8;
	            weatherLargeCumulusDensity = 0.5;
                weatherAltostratusDensity = 0.5;

	            weatherUniformFogDensity = 0.15;
                weatherClumpyFogDensity = 0.25;
                weatherClumpyFogCoverage = 1.0;
                break;
            }
            case 6: {
                // Heavy Rain w/ Cloudy Fog
                weatherSmallCumulusCoverage = 1.2;
	            weatherLargeCumulusCoverage = 1.4;
	            weatherAltostratusCoverage = 0.0;

                weatherSmallCumulusDensity = 1.0;
	            weatherLargeCumulusDensity = 1.0;
                weatherAltostratusDensity = 0.0;

	            weatherUniformFogDensity = 0.05;
                weatherClumpyFogDensity = 1.0;
                weatherClumpyFogCoverage = 0.2;
                break;
            }
        }
    #endif
    #if USE_CUSTOM_DAILY_RAIN_PROFILE > 0
        int customRainyWeatherProfile = int(RNG * USE_CUSTOM_DAILY_RAIN_PROFILE);

        switch (customRainyWeatherProfile){
            default : {
                weatherSmallCumulusCoverage = RAINY_PROFILE_1_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_1_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_1_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_1_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_1_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_1_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_1_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_1_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_1_CLUMPY_FOG_COVERAGE;
                break;
            }
        #if USE_CUSTOM_DAILY_RAIN_PROFILE >= 2
            case 1: {
                weatherSmallCumulusCoverage = RAINY_PROFILE_2_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_2_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_2_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_2_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_2_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_2_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_2_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_2_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_2_CLUMPY_FOG_COVERAGE;
                break;
            }
        #endif
        #if USE_CUSTOM_DAILY_RAIN_PROFILE >= 3
            case 2: {
                weatherSmallCumulusCoverage = RAINY_PROFILE_3_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_3_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_3_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_3_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_3_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_3_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_3_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_3_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_3_CLUMPY_FOG_COVERAGE;
                break;
            }
        #endif
        #if USE_CUSTOM_DAILY_RAIN_PROFILE >= 4
            case 3: {
                weatherSmallCumulusCoverage = RAINY_PROFILE_4_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_4_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_4_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_4_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_4_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_4_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_4_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_4_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_4_CLUMPY_FOG_COVERAGE;
                break;
            }
        #endif
        #if USE_CUSTOM_DAILY_RAIN_PROFILE >= 5
            case 4: {
                weatherSmallCumulusCoverage = RAINY_PROFILE_5_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_5_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_5_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_5_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_5_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_5_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_5_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_5_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_5_CLUMPY_FOG_COVERAGE;
                break;
            }
        #endif
        #if USE_CUSTOM_DAILY_RAIN_PROFILE >= 6
            case 5 : {
                weatherSmallCumulusCoverage = RAINY_PROFILE_6_LAYER0_COVERAGE;
                weatherLargeCumulusCoverage = RAINY_PROFILE_6_LAYER1_COVERAGE;
                weatherAltostratusCoverage =  RAINY_PROFILE_6_LAYER2_COVERAGE;
                weatherSmallCumulusDensity =  RAINY_PROFILE_6_LAYER0_DENSITY;
                weatherLargeCumulusDensity =  RAINY_PROFILE_6_LAYER1_DENSITY;
                weatherAltostratusDensity =   RAINY_PROFILE_6_LAYER2_DENSITY;
                weatherUniformFogDensity = RAINY_PROFILE_6_UNIFORM_FOG;
                weatherClumpyFogDensity = RAINY_PROFILE_6_CLUMPY_FOG;
                weatherClumpyFogCoverage = RAINY_PROFILE_6_CLUMPY_FOG_COVERAGE;
                break;
            }
        #endif
        }
    #endif

    #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE == 0 || USE_CUSTOM_COLD_BIOME_RAIN_PROFILE == 0
        // simply shift the index ahead for environment switching
        int biomeRainyWeatherProfile = int(RNG * 3.0);
        
        #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE == 0
            if(isInHotArea && isInNoRainFallEnvironment) biomeRainyWeatherProfile += 3;
        #endif
        #if USE_CUSTOM_COLD_BIOME_RAIN_PROFILE == 0
            if(isInColdArea && isInSnowFallEnvironment) biomeRainyWeatherProfile += 6;
        #endif

        switch (biomeRainyWeatherProfile){
            default : {
                break;
            }
            #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE == 0
                case 3: {  // dust storm
                    localUniformFogDensity = 0.025;
                    localClumpyFogDensity = 0.15;
                    localClumpyFogCoverage = 0.75;
                    localFogColor = vec3(0.95, 0.65, 0.35);

	                weatherUniformFogDensity = 0.0;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
                case 4: { // sand storm
                    localUniformFogDensity = 0.05;
                    localClumpyFogDensity = 0.5;
                    localClumpyFogCoverage = 0.65;
                    localFogColor = vec3(0.95, 0.65, 0.35);

	                weatherUniformFogDensity = 0.0;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
                case 5: { // heavy sand storm
                    localUniformFogDensity = 0.05;
                    localClumpyFogDensity = 0.3;
                    localClumpyFogCoverage = 0.95;
                    localFogColor = vec3(0.95, 0.65, 0.35);

	                weatherUniformFogDensity = 0.0;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
            #endif
            #if USE_CUSTOM_COLD_BIOME_RAIN_PROFILE == 0
                case 6: { // light snow
                    localUniformFogDensity = 0.1;
                    localClumpyFogDensity = 0.2;
                    localClumpyFogCoverage = 0.05;
                    localFogColor = vec3(1.25, 1.25, 1.25);

	                weatherUniformFogDensity = 0.1;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
                case 7: { // snow storm
                    localUniformFogDensity = 0.1;
                    localClumpyFogDensity = 0.5;
                    localClumpyFogCoverage = 0.05;
                    localFogColor = vec3(1.5, 1.5, 1.5);

	                weatherUniformFogDensity = 0.3;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
                case 8: { // blizzard
                    localUniformFogDensity = 0.25;
                    localClumpyFogDensity = 0.5;
                    localClumpyFogCoverage = 0.25;
                    localFogColor = vec3(1.5, 1.5, 1.5);

	                weatherUniformFogDensity = 0.5;
                    weatherClumpyFogDensity = 0.0;
                    weatherClumpyFogCoverage = 0.0;
                    break;
                }
            #endif
        }
    #endif
    #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE > 0
        if(isInHotArea && isInNoRainFallEnvironment){
	        weatherUniformFogDensity = uniformFogDensity;
            weatherClumpyFogDensity = clumpyFogDensity;
            weatherClumpyFogCoverage = clumpyFogCoverage;

            int customHotBiomeRainyWeatherProfile = int(RNG * USE_CUSTOM_HOT_BIOME_RAIN_PROFILE);

            switch (customHotBiomeRainyWeatherProfile){
                default : {
                    localUniformFogDensity = HOT_BIOME_RAINY_PROFILE_1_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = HOT_BIOME_RAINY_PROFILE_1_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = HOT_BIOME_RAINY_PROFILE_1_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(HOT_BIOME_RAINY_PROFILE_1_FOG_COLOR_R, HOT_BIOME_RAINY_PROFILE_1_FOG_COLOR_G, HOT_BIOME_RAINY_PROFILE_1_FOG_COLOR_B);
                    break;
                }
            #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE >= 2
                case 1: {
                    localUniformFogDensity = HOT_BIOME_RAINY_PROFILE_2_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = HOT_BIOME_RAINY_PROFILE_2_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = HOT_BIOME_RAINY_PROFILE_2_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(HOT_BIOME_RAINY_PROFILE_2_FOG_COLOR_R, HOT_BIOME_RAINY_PROFILE_2_FOG_COLOR_G, HOT_BIOME_RAINY_PROFILE_2_FOG_COLOR_B);
                    break;
                }
            #endif
            #if USE_CUSTOM_HOT_BIOME_RAIN_PROFILE >= 3
                case 2: {
                    localUniformFogDensity = HOT_BIOME_RAINY_PROFILE_3_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = HOT_BIOME_RAINY_PROFILE_3_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = HOT_BIOME_RAINY_PROFILE_3_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(HOT_BIOME_RAINY_PROFILE_3_FOG_COLOR_R, HOT_BIOME_RAINY_PROFILE_3_FOG_COLOR_G, HOT_BIOME_RAINY_PROFILE_3_FOG_COLOR_B);
                    break;
                }
            #endif
            }
        }
    #endif
    #if USE_CUSTOM_COLD_BIOME_RAIN_PROFILE > 0
        if(isInColdArea && isInSnowFallEnvironment){
	        weatherUniformFogDensity = uniformFogDensity;
            weatherClumpyFogDensity = clumpyFogDensity;
            weatherClumpyFogCoverage = clumpyFogCoverage;

            int customHotBiomeRainyWeatherProfile = int(RNG * USE_CUSTOM_COLD_BIOME_RAIN_PROFILE);
            
            switch (customHotBiomeRainyWeatherProfile){
                default : {
                    localUniformFogDensity = COLD_BIOME_RAINY_PROFILE_1_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = COLD_BIOME_RAINY_PROFILE_1_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = COLD_BIOME_RAINY_PROFILE_1_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(COLD_BIOME_RAINY_PROFILE_1_FOG_COLOR_R, COLD_BIOME_RAINY_PROFILE_1_FOG_COLOR_G, COLD_BIOME_RAINY_PROFILE_1_FOG_COLOR_B);
                    break;
                }
            #if USE_CUSTOM_COLD_BIOME_RAIN_PROFILE >= 2
                case 1: {
                    localUniformFogDensity = COLD_BIOME_RAINY_PROFILE_2_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = COLD_BIOME_RAINY_PROFILE_2_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = COLD_BIOME_RAINY_PROFILE_2_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(COLD_BIOME_RAINY_PROFILE_2_FOG_COLOR_R, COLD_BIOME_RAINY_PROFILE_2_FOG_COLOR_G, HCOLDBIOME_RAINY_PROFILE_2_FOG_COLOR_B);
                    break;
                }
            #endif
            #if USE_CUSTOM_COLD_BIOME_RAIN_PROFILE >= 3
                case 2: {
                    localUniformFogDensity = COLD_BIOME_RAINY_PROFILE_3_UNIFORM_FOG_DENSITY;
                    localClumpyFogDensity = COLD_BIOME_RAINY_PROFILE_3_CLUMPY_FOG_DENSITY;
                    localClumpyFogCoverage = COLD_BIOME_RAINY_PROFILE_3_CLUMPY_FOG_COVERAGE;
                    localFogColor = vec3(HCOLDBIOME_RAINY_PROFILE_3_FOG_COLOR_R, COLD_BIOME_RAINY_PROFILE_3_FOG_COLOR_G, COLD_BIOME_RAINY_PROFILE_3_FOG_COLOR_B);
                    break;
                }
            #endif
            }
        }
    #endif

    // Blend

    float weatherBlend = smoothstep(0.0, 1.0, rainStrength);
    float cloudWeatherBlend = 0.8 * weatherBlend;
    float fogWeatherBlend = 0.7 * weatherBlend;

    smallCumulusCoverage = mix(smallCumulusCoverage, weatherSmallCumulusCoverage, cloudWeatherBlend);
    smallCumulusDensity = mix(smallCumulusDensity, weatherSmallCumulusDensity, cloudWeatherBlend);
    largeCumulusCoverage = mix(largeCumulusCoverage, weatherLargeCumulusCoverage, cloudWeatherBlend);
    largeCumulusDensity = mix(largeCumulusDensity, weatherLargeCumulusDensity, cloudWeatherBlend);
    altostratusCoverage = mix(altostratusCoverage, weatherAltostratusCoverage, cloudWeatherBlend);
    altostratusDensity = mix(altostratusDensity, weatherAltostratusDensity, cloudWeatherBlend);

    uniformFogDensity = clamp(mix(uniformFogDensity, weatherUniformFogDensity, fogWeatherBlend), 0.0, 1.0);
    clumpyFogDensity = clamp(mix(clumpyFogDensity, weatherClumpyFogDensity, fogWeatherBlend), 0.0, 1.0);
    clumpyFogCoverage = clamp(mix(clumpyFogCoverage, weatherClumpyFogCoverage, fogWeatherBlend), 0.0, 1.0);
}

#if USE_CUSTOM_SWAMP_CATEGORY_PROFILE == 0
    if(isInSwampBiomes){
	    // uniformFogDensity = mix(uniformFogDensity, 0.0, swampBlend);
        // clumpyFogDensity = mix(clumpyFogDensity, 0.0, swampBlend);
        // clumpyFogCoverage = mix(clumpyFogCoverage, 0.0, swampBlend);

        localUniformFogDensity = 0.0;
        localClumpyFogDensity = 0.05;
        localClumpyFogCoverage = 0.5;
        localFogColor = vec3(0.8,0.95,0.8);
    }
#endif
#if USE_CUSTOM_SWAMP_CATEGORY_PROFILE == 1
    if(isInSwampBiomes){
	    // uniformFogDensity = mix(uniformFogDensity, 0.0, swampBlend);
        // clumpyFogDensity = mix(clumpyFogDensity, 0.0, swampBlend);
        // clumpyFogCoverage = mix(clumpyFogCoverage, 0.0, swampBlend);

        localUniformFogDensity = CUSTOM_SWAMP_PROFILE_1_UNIFORM_FOG_DENSITY;
        localClumpyFogDensity = CUSTOM_SWAMP_PROFILE_1_CLUMPY_FOG_DENSITY;
        localClumpyFogCoverage = CUSTOM_SWAMP_PROFILE_1_CLUMPY_FOG_COVERAGE;
        localFogColor = vec3(CUSTOM_SWAMP_PROFILE_1_FOG_COLOR_R, CUSTOM_SWAMP_PROFILE_1_FOG_COLOR_G, CUSTOM_SWAMP_PROFILE_1_FOG_COLOR_B);
    }
#endif
#if USE_CUSTOM_JUNGLE_CATEGORY_PROFILE == 0
    if(isInJungleBiomes){
	    // uniformFogDensity = mix(uniformFogDensity, 0.0, jungleBlend);
        // clumpyFogDensity = mix(clumpyFogDensity, 0.0, jungleBlend);
        // clumpyFogCoverage = mix(clumpyFogCoverage, 0.0, jungleBlend);
        
        localUniformFogDensity = 0.015;
        localClumpyFogDensity = 0.3;
        localClumpyFogCoverage = 0.0;
        localFogColor = vec3(0.39, 0.6, 0.55);
    }
#endif
#if USE_CUSTOM_JUNGLE_CATEGORY_PROFILE == 1
    if(isInJungleBiomes){
	    // uniformFogDensity = mix(uniformFogDensity, 0.0, jungleBlend);
        // clumpyFogDensity = mix(clumpyFogDensity, 0.0, jungleBlend);
        // clumpyFogCoverage = mix(clumpyFogCoverage, 0.0, jungleBlend);

        localUniformFogDensity = CUSTOM_JUNGLE_PROFILE_1_UNIFORM_FOG_DENSITY;
        localClumpyFogDensity = CUSTOM_JUNGLE_PROFILE_1_CLUMPY_FOG_DENSITY;
        localClumpyFogCoverage = CUSTOM_JUNGLE_PROFILE_1_CLUMPY_FOG_COVERAGE;
        localFogColor = vec3(CUSTOM_JUNGLE_PROFILE_1_FOG_COLOR_R, CUSTOM_JUNGLE_PROFILE_1_FOG_COLOR_G, CUSTOM_JUNGLE_PROFILE_1_FOG_COLOR_B);
    }
#endif

if(localClumpyFogCoverage < 0.0) {
    localClumpyFogCoverage = clumpyFogCoverage;
}


#define WRITE_CUSTOM_SCENE_CONTROLLER_PROFILES
#undef DECLARE_UNIFORMS_OR_WRITE_FUNCTIONS_FOR_CUSTOM_SCENE_CONTROLLER_PROFILES
#include "/CUSTOM_SCENE_PARAMETERS.glsl"

}
#endif

flat varying struct sceneController {
  vec2 smallCumulus;
  vec2 largeCumulus;
  vec2 altostratus;
  vec3 fog;
  vec3 localFog;
  vec3 localFogColor;
} parameters;

vec3 writeSceneControllerParameters(
	vec2 uv,
    vec2 smallCumulus,
	vec2 largeCumulus,
	vec2 altostratus,
	vec3 fog,
    vec3 localFog,
    vec3 localFogColor
){

    // in colortex4, data is written in a 3x3 pixel area from (1,1) to (3,3)
    // avoiding use of any variation of (0,0) to avoid weird textture wrapping issues
    // 4th compnent/alpha is storing 1/4 res depth so i cant store there lol
    
    /* (1,3) */ bool topLeft = uv.x > 1 && uv.x < 2 && uv.y > 3 && uv.y < 4;
    /* (2,3) */ bool topMiddle = uv.x > 2 && uv.x < 3 && uv.y > 3 && uv.y < 4;
    /* (3,3) */ bool topRight = uv.x > 3 && uv.x < 5 && uv.y > 3 && uv.y < 4;
    /* (1,2) */ bool middleLeft = uv.x > 1 && uv.x < 2 && uv.y > 2 && uv.y < 3;
    /* (2,2) */ bool middleMiddle = uv.x > 2 && uv.x < 3 && uv.y > 2 && uv.y < 3;
    // /* (3,2) */ bool middleRight = uv.x > 3 && uv.x < 5 && uv.y > 2 && uv.y < 3;
    // /* (1,1) */ bool bottomLeft = uv.x > 1 && uv.x < 2 && uv.y > 1 && uv.y < 2;
    // /* (2,1) */ bool bottomMiddle = uv.x > 2 && uv.x < 3 && uv.y > 1 && uv.y < 2;
    // /* (3,1) */ bool bottomRight = uv.x > 3 && uv.x < 5 && uv.y > 1 && uv.y < 2;

    vec3 data = vec3(0.0,0.0,0.0);

    if(topLeft) data = vec3(smallCumulus.xy, largeCumulus.x);
    if(topMiddle) data = vec3(largeCumulus.y, altostratus.xy);
    if(topRight) data = vec3(fog.xyz);
    if(middleLeft) data = vec3(localFog.xy, localFog.z);
    if(middleMiddle) data = vec3(localFogColor.rgb);
    

    // if(topRight)  	 data = vec4(groundSunColor,fogSunColor.r);
    // if(middleLeft)   data = vec4(groundAmbientColor,fogSunColor.g);
    // if(middleMiddle) data = vec4(fogAmbientColor,fogSunColor.b);
    // if(middleRight)  data = vec4(cloudSunColor,cloudAmbientColor.r);
    // if(bottomLeft)   data = vec4(cloudAmbientColor.gb,0.0,0.0);
    // if(bottomMiddle) data = vec4(0.0);
    // if(bottomRight)  data = vec4(0.0);

    return data;
}

void readSceneControllerParameters(
	sampler2D colortex,
	out vec2 smallCumulus,
	out vec2 largeCumulus,
	out vec2 altostratus,
	out vec3 fog,
    out vec3 localFog,
    out vec3 localFogColor
){
    
    // in colortex4, read the data stored within the 3 components of the sampled pixels, and pass it to the fragment stage
    // 4th compnent/alpha is storing 1/4 res depth so i cant store there lol
	vec3 data1 = texelFetch(colortex,ivec2(1,3),0).rgb/150.0;
	vec3 data2 = texelFetch(colortex,ivec2(2,3),0).rgb/150.0;
	vec3 data3 = texelFetch(colortex,ivec2(3,3),0).rgb/150.0;
	vec3 data4 = texelFetch(colortex,ivec2(1,2),0).rgb/150.0;
	vec3 data5 = texelFetch(colortex,ivec2(2,2),0).rgb/150.0;

	smallCumulus = vec2(data1.x,data1.y);
	largeCumulus = vec2(data1.z,data2.x);
	altostratus = vec2(data2.y,data2.z);
	fog = vec3(data3.x, data3.y, data3.z);
    localFog = vec3(data4.x, data4.y, data4.z);
    localFogColor = vec3(data5.r,data5.g,data5.b);
}
#endif



// call the reading function within the main function
// this is so i dont have to edit the function call across every file :)))))))))))))

#if defined READ_SCENE_CONTROLLER_PARAMETERS
readSceneControllerParameters(
    colortex4, 
    parameters.smallCumulus, 
    parameters.largeCumulus, 
    parameters.altostratus, 
    parameters.fog,
    parameters.localFog,
    parameters.localFogColor
);
#endif
