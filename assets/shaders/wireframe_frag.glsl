#version 450 core

in vec3 triangleDist;
out vec4 f_color;

// http://codeflow.org/entries/2012/aug/02/easy-wireframe-display-with-barycentric-coordinates/
float edgeFactor(float lineWidth) 
{
    vec3 d = fwidth(triangleDist);
    vec3 a3 = smoothstep(vec3(0.0), d * lineWidth, triangleDist);
    return min(min(a3.x, a3.y), a3.z);
}

// returns a wireframed color from a fill, stroke and linewidth
vec3 wireframe(vec3 fill, vec3 stroke, float lineWidth) 
{
    return mix(stroke, fill, edgeFactor(lineWidth));
}

// returns a black wireframed color from a fill and linewidth
vec3 wireframe(vec3 color, float lineWidth) 
{
    return wireframe(color, vec3(0.0), lineWidth);
}

// returns a black wireframed color
vec3 wireframe(vec3 color) 
{
    return wireframe(color, 1.5);
}

void main()
{
    f_color = vec4(wireframe(vec3(0.5) + vec3(1, 1, 1)), 0.1);
}
