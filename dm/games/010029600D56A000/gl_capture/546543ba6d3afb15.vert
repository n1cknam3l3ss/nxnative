#define LOWPREC lowp
#define MAX_VS_LIGHTS 1
#define MATRIX_VIEW                    0                               
#define MATRIX_PROJECTION              1                               
#define MATRIX_WORLD                   2                               
#define MATRIX_WORLD_VIEW              3                               
#define MATRIX_WORLD_VIEW_PROJECTION   4                               
#define MATRICES_MAX                   5                               

uniform mat4 gm_Matrices[MATRICES_MAX];								

uniform bool gm_LightingEnabled;										
uniform bool gm_VS_FogEnabled;											
uniform float gm_FogStart;												
uniform float gm_RcpFogRange;											

#ifndef MAX_VS_LIGHTS                                                  
#define MAX_VS_LIGHTS	8												
#endif                                                                 
#define MIRROR_WIN32_LIGHTING_EQUATION									

struct LightEnv														
{																		
	vec4 ambientcol;													
	vec4 m_dirLights_dir[MAX_VS_LIGHTS];								
	vec4 m_dirLights_diffusecol[MAX_VS_LIGHTS];							
	vec4 m_pointLights_posrange[MAX_VS_LIGHTS];							
	vec4 m_pointLights_diffusecol[MAX_VS_LIGHTS];						
};																		

uniform LightEnv u_LightEnv;											

float CalcFogFactor(vec4 pos)											
{																		
#ifdef USE_FOG															
	{																	
		vec4 viewpos = gm_Matrices[MATRIX_WORLD_VIEW] * pos;							
		float fogfactor = ((viewpos.z - gm_FogStart) * gm_RcpFogRange);	
		return fogfactor;												
	}																	
#else // USE_FOG														
	{																	
		return 0.0;														
	}																	
#endif	// USE_FOG														
}																		

vec4 DoDirLight(vec3 ws_normal, vec4 dir, vec4 diffusecol)				
{																		
	float dotresult = dot(ws_normal, dir.xyz);							
	dotresult = max(0.0, dotresult);									

	return dotresult * diffusecol;										
}																		

vec4 DoPointLight(vec3 ws_pos, vec3 ws_normal, vec4 posrange, vec4 diffusecol)		
{																		
	vec3 diffvec = ws_pos - posrange.xyz;								
	float veclen = length(diffvec);										
	diffvec /= veclen;	// normalise									
#ifdef MIRROR_WIN32_LIGHTING_EQUATION									
	// This is based on the Win32 D3D and OpenGL falloff model, where:	
	// Attenuation = 1.0f / (factor0 + (d * factor1) + (d*d * factor2))	
	// For some reason, factor0 is set to 0.0f while factor1 is set to 1.0f/lightrange (on both D3D and OpenGL)	
	// This'll result in no visible falloff as 1.0f / (d / lightrange) will always be larger than 1.0f (if the vertex is within range) 
	float atten = veclen < posrange.w ? 1.0 : 0.0;						
#else																	
	float atten = clamp( (1.0 - (veclen / posrange.w)), 0.0, 1.0);		
#endif																	
	float dotresult = dot(ws_normal, diffvec);							
	dotresult = max(0.0, dotresult);									

	return dotresult * atten * diffusecol;								
}																		

vec4 DoLighting(vec4 vertexcolour, vec4 objectspacepos, vec3 objectspacenormal) 
{																		
	{																	
		// Normally we'd have the light positions\directions back-transformed from world to object space 
		// But to keep things simple for the moment we'll just transform the normal to world space 
       // Also, depending on what world transforms have been set, the sphere of the light radius   
       // may become a non-axis aligned irregularly scaled and sheared ellipsoid in object space 
       // which is obviously much harder to test against               
		vec4 objectspacenormal4 = vec4(objectspacenormal, 0.0);			
		vec3 ws_normal;													
		ws_normal = (gm_Matrices[MATRIX_WORLD] * objectspacenormal4).xyz;				
		ws_normal = -normalize(ws_normal);								

		vec3 ws_pos;													
		ws_pos = (gm_Matrices[MATRIX_WORLD] * objectspacepos).xyz;					

		// Accumulate lighting from different light types				
		vec4 accumcol = vec4(0.0, 0.0, 0.0, 0.0);						
		for(int i = 0; i < MAX_VS_LIGHTS; i++)								
		{																
			accumcol += DoDirLight(ws_normal, u_LightEnv.m_dirLights_dir[i], u_LightEnv.m_dirLights_diffusecol[i]); 
		}																

		for(int i = 0; i < MAX_VS_LIGHTS; i++)								
		{																
			accumcol += DoPointLight(ws_pos, ws_normal, u_LightEnv.m_pointLights_posrange[i], u_LightEnv.m_pointLights_diffusecol[i]); 
		}																

		accumcol *= vertexcolour;										
		accumcol += u_LightEnv.ambientcol;								
		accumcol = min(vec4(1.0, 1.0, 1.0, 1.0), accumcol);				
		accumcol.a = vertexcolour.a;									
		return accumcol;												
	}																	
}																		
attribute vec3 in_Position;								
attribute vec3 in_Normal;									
attribute vec2 in_TextureCoord;								
attribute LOWPREC vec4 in_Colour;									
varying vec2 v_vTexcoord;									
varying LOWPREC vec4 v_vColour;									
varying float v_fFog;										
void main()												
{															
	vec4 objectspacepos = vec4(in_Position, 1.0);			

	float fogfactor = CalcFogFactor(objectspacepos);		

	vec4 pos = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * objectspacepos;		
	gl_Position = pos;										
   gl_PointSize = 1.0;                                     

	v_vColour = DoLighting(in_Colour, objectspacepos, in_Normal); 

	v_vTexcoord = in_TextureCoord;								
	v_fFog = fogfactor;										
}															
