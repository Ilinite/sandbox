#ifdef FOUR_CASCADES
vec4 get_cascade_weights(float depth, vec4 splitNear, vec4 splitFar)
{
    return (step(splitNear, vec4(depth))) * (step(depth, splitFar));
}

mat4 get_cascade_viewproj(vec4 weights, mat4 viewProj[4])
{
    return viewProj[0] * weights.x + viewProj[1] * weights.y + viewProj[2] * weights.z + viewProj[3] * weights.w;
}

float get_cascade_layer(vec4 weights) 
{
    return 0.0 * weights.x + 1.0 * weights.y + 2.0 * weights.z + 3.0 * weights.w;   
}

vec3 get_cascade_weighted_color(vec4 weights) 
{
    return vec3(1,0,0) * weights.x + vec3(0,1,0) * weights.y + vec3(0,0,1) * weights.z + vec3(1,0,1) * weights.w;
}
#endif

#ifdef TWO_CASCADES
vec2 get_cascade_weights(float depth, vec2 splitNear, vec2 splitFar)
{
    return (step(splitNear, vec2(depth))) * (step(depth, splitFar)); 
}

mat4 get_cascade_viewproj(vec2 weights, mat4 viewProj[2])
{
    return viewProj[0] * weights.x + viewProj[1] * weights.y;
}

float get_cascade_layer(vec2 weights) 
{
    return 0.0 * weights.x +  1.0 * weights.y; 
}

vec3 get_cascade_weighted_color(vec2 weights) 
{
    return vec3(1,0,0) * weights.x + vec3(0,1,0) * weights.y;
}
#endif

float random(vec2 seed2) 
{
    vec4 seed4 = vec4(seed2.x, seed2.y, seed2.y, 1.0);
    float dot_product = dot(seed4, vec4(12.9898, 78.233, 45.164, 94.673));
    return fract(sin(dot_product) * 43758.5453);
}

float depth_test(sampler2DArray shadowMap, vec3 uv, float compare)
{
    float depth = texture(shadowMap, uv).r;
    return step(compare, depth);
}

float sample_shadowmap(sampler2DArray shadowMap, vec2 size, vec2 uv, float compare, float layer)
{
    vec2 texelSize = vec2(1) / size;
    vec2 f = fract(uv * size + 0.5);
    vec2 centroidUV = floor(uv * size + 0.5) / size;

    float lb = depth_test(shadowMap, vec3(centroidUV + texelSize * vec2(0.0, 0.0),layer), compare);
    float lt = depth_test(shadowMap, vec3(centroidUV + texelSize * vec2(0.0, 1.0),layer), compare);
    float rb = depth_test(shadowMap, vec3(centroidUV + texelSize * vec2(1.0, 0.0),layer), compare);
    float rt = depth_test(shadowMap, vec3(centroidUV + texelSize * vec2(1.0, 1.0),layer), compare);

    float a = mix(lb, lt, f.y);
    float b = mix(rb, rt, f.y);
    float c = mix(a, b, f.x);
    
    return c;
}

float calculate_csm_coefficient(sampler2DArray map, vec3 biasedWorldPos, vec3 viewPos, mat4 viewProjArray[NUM_CASCADES], vec4 splitPlanes[NUM_CASCADES], out vec3 weightedColor)
{
    #ifdef FOUR_CASCADES
    vec4 weights = get_cascade_weights(-viewPos.z,
        vec4(splitPlanes[0].x, splitPlanes[1].x, splitPlanes[2].x, splitPlanes[3].x),
        vec4(splitPlanes[0].y, splitPlanes[1].y, splitPlanes[2].y, splitPlanes[3].y)
    );
    #endif

    #ifdef TWO_CASCADES
    vec2 weights = get_cascade_weights(-viewPos.z,
        vec2(splitPlanes[0].x, splitPlanes[1].x),
        vec2(splitPlanes[0].y, splitPlanes[1].y));
    #endif

    // Get vertex position in light space
    mat4 lightViewProj = get_cascade_viewproj(weights, viewProjArray);
    vec4 vertexLightPostion = lightViewProj * vec4(biasedWorldPos, 1.0);

    // Compute perspective divide and transform to 0-1 range
    const vec3 coords = (vertexLightPostion.xyz / vertexLightPostion.w) / 2.0 + 0.5;

    if (!(coords.z > 0.0 && coords.x > 0.0 && coords.y > 0.0 && coords.x <= 1.0 && coords.y <= 1.0)) return 0;

    // float shadow_bias[5] = {0.00005, 0.00014, 0.0006, 0.0012, 0.005};

    float contant_bias = 0.002;
    float currentDepth = coords.z;

    float shadowTerm = 0.0;

    // Non-PCF path, hard shadows
    float closestDepth = texture(map, vec3(coords.xy, get_cascade_layer(weights))).r;
    shadowTerm = (currentDepth - contant_bias) > closestDepth ? 1.0 : 0.0;

    // Percentage-closer filtering
    /*
    vec2 texelSize = 1.0 / textureSize(map, 0).xy;
    for (int x = -1; x <= 1; ++x)
    {
        for (int y = -1; y <= 1; ++y)
        {
            float pcfDepth = texture(map, vec3(coords.xy + vec2(x, y) * texelSize, get_cascade_layer(weights))).r;
            shadowTerm += currentDepth - contant_bias > pcfDepth  ? 1.0 : 0.0;
        }
    }
    shadowTerm /= 9.0;
    */

    /*
    // Stratified Poisson sampling for shadow map
    float packing = 4096.0; // how close together are the samples
    const vec2 poissonDisk[4] = 
    {
        vec2(-0.94201624,  -0.39906216),
        vec2( 0.94558609,  -0.76890725),
        vec2(-0.094184101, -0.92938870),
        vec2( 0.34495938,   0.29387760)
    };

    int samples = 8;
    for (uint i = 0; i < samples; i++)
    {
        uint index = uint(samples * random(coords.xy * i)) % samples; // A pseudo-random number between 0 and 15, different for each pixel and each index
        float d = sample_shadowmap(map, textureSize(map, 0).xy, coords.xy + (poissonDisk[index] / packing),  coords.z, get_cascade_layer(weights));
        shadowTerm += currentDepth - contant_bias > d  ? 1.0 : 0.0;
    }   
    shadowTerm /= samples;
    */

    weightedColor = get_cascade_weighted_color(weights);

    /*
    // Exponential Shadow Filtering
    const float overshadowConstant = 140;
    float depth = (coords.z + bias);
    float occluderDepth = texture(map, vec3(coords.xy, get_cascade_layer(weights))).r;
    float occluder = exp(overshadowConstant * occluderDepth);
    float receiver = exp(-overshadowConstant * depth);
    shadowTerm = 1.0 - clamp(occluder * receiver, 0.0, 1.0);
    */

    return shadowTerm;
}
