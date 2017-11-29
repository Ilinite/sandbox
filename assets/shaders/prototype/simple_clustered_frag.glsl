#version 450

uniform vec3 u_diffuse;
uniform vec3 u_eye;

uniform float u_nearClip;
uniform float u_farClip;
uniform vec2 u_rcpViewportSize;

const int MAX_POINT_LIGHTS = 1024;
const float NUM_TILES_X = 8.0;
const float NUM_TILES_Y = 8.0;
const float NUM_SLICES_Z = 8.0;

struct PointLight
{
    vec4 position;
    vec4 color;
};

layout(binding = 7, std140) uniform ClusteredLighting
{
    PointLight pointLights[MAX_POINT_LIGHTS];
};

uniform usampler3D s_clusterTexture;
uniform usamplerBuffer s_lightIndexTexture;

vec3 cluster_coord_for_vertex(const in vec2 texcoord, const in float vertexDepth, out int indexOffset, out int sphereLightCount)
{
    float linearDepth = (-vertexDepth - u_nearClip) / (u_farClip - u_nearClip);
    int slice = int(max(linearDepth * NUM_SLICES_Z, 0.0));

    ivec3 clusterCoordinate;
    clusterCoordinate.xy = ivec2(texcoord * u_rcpViewportSize * ivec2(NUM_TILES_X, NUM_TILES_Y));
    clusterCoordinate.z = slice;

    uvec4 data = texelFetch(s_clusterTexture, clusterCoordinate, 0);
    indexOffset = int(data.x);
    sphereLightCount = int(data.y);

    return clusterCoordinate;
}

PointLight get_point_light_for_index(const in int idx)
{
    return pointLights[texelFetch(s_lightIndexTexture, idx).r]; 
}

in vec3 v_position;
in vec3 v_normal;
in vec3 v_position_vs;

out vec4 f_color;

float cubic_gaussian(float h) 
{
    if (h < 1.0) 
    {
        return 0.25 * pow(2.0 - h, 3.0) - pow(1.0 - h, 3.0);
    } 
    else if (h < 2.0) 
    {
        return 0.25 * pow(2.0 - h, 3.0);
    } 
    else 
    {
        return 0.0;
    }
}

void main()
{
    vec3 eyeDir = normalize(u_eye - v_position);
    vec3 light = vec3(0, 0, 0);

    int indexOffset = 0;
    int sphereLightCount = 0;
    vec3 clusterCoord = cluster_coord_for_vertex(gl_FragCoord.xy, v_position_vs.z, indexOffset, sphereLightCount);

    for(int i = 0; i < sphereLightCount; ++i)
    {
        vec3 L = vec3(0, 0, 0);

        vec3 lightDir = normalize(pointLights[i].position.xyz - v_position);
        L += pointLights[i].color.rgb * max(dot(v_normal, lightDir), 0);

        vec3 halfDir = normalize(lightDir + eyeDir);
        L += pointLights[i].color.rgb * pow(max(dot(v_normal, halfDir), 0), 128);

        float dist = distance(pointLights[i].position.xyz, v_position);
        float lightIntensity = cubic_gaussian(2.0 * dist / pointLights[i].position.w); 

        light += L * lightIntensity * 8; // multiplier for debugging only
    }
    f_color = vec4(light, 1);
}