precision mediump float;
#define LOWPREC lowp
// Uniforms look like they're shared between vertex and fragment shaders in GLSL, so we have to be careful to avoid name clashes

uniform sampler2D gm_BaseTexture;

uniform bool gm_PS_FogEnabled;
uniform vec4 gm_FogColour;
uniform bool gm_AlphaTestEnabled;
uniform float gm_AlphaRefValue;

void DoAlphaTest(vec4 SrcColour)
{
	if (gm_AlphaTestEnabled)
	{
		if (SrcColour.a <= gm_AlphaRefValue)
		{
			discard;
		}
	}
}

void DoFog(inout vec4 SrcColour, float fogval)
{
	if (gm_PS_FogEnabled)
	{
		SrcColour = mix(SrcColour, gm_FogColour, clamp(fogval, 0.0, 1.0)); 
	}
}

#define _YY_GLSLES_ 1
varying vec2 v_texcoord;

uniform float time;
uniform vec2 mouse_pos;
uniform vec2 resolution;
uniform float radial_blur_offset;
uniform float radial_brightness;
uniform float quality;

void main()
{ 
    vec2 uv = vec2(v_texcoord);
//    uv.x *= (resolution.x/resolution.y);
    vec2 radial_size = vec2(1.0/resolution);
    radial_size.x *= (resolution.x/resolution.y);
    vec2 radial_origin = vec2(mouse_pos/resolution);
    vec4 colour = vec4(0.0);
    
    //float blur_amount = 30.0;
    float blur_amount = quality;
	
    uv += radial_size * 0.5 - radial_origin;
 
    for (float i = 0.0; i < blur_amount; i++)
    {
        float offset = 1.0 - radial_blur_offset * (i / (blur_amount - 1.0));
        colour += texture2D(gm_BaseTexture, uv * offset + radial_origin);  
    }
 
  gl_FragColor = colour / (blur_amount - 1.0) * radial_brightness;
}
