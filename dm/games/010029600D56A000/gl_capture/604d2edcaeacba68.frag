precision mediump float;						
#define LOWPREC lowp                           
#define USE_FOG
#define MAX_VS_LIGHTS 8
uniform sampler2D gm_BaseTexture;              

uniform bool gm_PS_FogEnabled;					
uniform LOWPREC vec4 gm_FogColour;             
uniform bool gm_AlphaTestEnabled;				
uniform LOWPREC float gm_AlphaRefValue;		

void DoAlphaTest(LOWPREC vec4 SrcColour)		
{												
#ifdef USE_ALPHATEST							
	{											
		if (SrcColour.a <= gm_AlphaRefValue)	
		{										
			discard;							
		}										
	}											
#endif // USE_ALPHATEST						
}												

LOWPREC vec4 DoFog(LOWPREC vec4 SrcColour, float fogval) 
{												
	vec4 retCol;								
#ifdef USE_FOG									
	{											
		retCol.rgb = mix(SrcColour.rgb, gm_FogColour.rgb, clamp(fogval, 0.0, 1.0)); 
		retCol.a = SrcColour.a;					
	}											
#else	// USE_FOG								
	retCol = SrcColour;							
#endif	// USE_FOG								
	return retCol;								
}												

varying vec2 v_vTexcoord;										
varying LOWPREC vec4 v_vColour;										
varying float v_fFog;											

void main()													
{																
	LOWPREC vec4 vertColour = v_vColour;								
	LOWPREC vec4 texelColour = texture2D( gm_BaseTexture, v_vTexcoord );	
	LOWPREC vec4 combinedColour = vertColour * texelColour;				

	DoAlphaTest(combinedColour);								
	combinedColour = DoFog(combinedColour, v_fFog);								

	gl_FragColor = combinedColour;								
}																
