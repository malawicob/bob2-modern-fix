//------------------------------------------------------------------------------
// Water.fx
//
// Author: Miro "Jammer" Torrielli
//
// Last Update: 17 May 2005
//
// **Modded Mar 21 2010, "Rummy" **
//
//------------------------------------------------------------------------------

float4x4 mView;
float4x4 mViewProj;
float3 ViewPos;
float4 WaterCol;
// float SpecularExponent = -10.0f;
// float SpecularFactor = -1.0f;
float FogStart;
float RFogRange;
texture NormalMap; // < string name = "weather\\wave2.dds";>;
texture EnvMap;    // < string name = "weather\\Cube.dds";>;
texture   FresnelMap;
float4 normalModifier = {6.0f,2.0f, 1.0f, 1.0f};   // liked swell size
// --- Enhanced sea, BOB2 Modern Fix (sun glitter). The sun is already in
// the reflection cube, so we amplify bright reflected highlights instead
// of needing a sun-direction the shader is never given. Dial to taste.
float glintBoost     = 1.8f;   // strength of the sun sparkle on the water
float glintThreshold = 0.72f;  // how bright a reflection must be to sparkle
float reflectDamp    = 0.65f;  // <1 darkens the sea (less sky reflection)
float speckTile   = 90.0f;  // speck density (bigger = more/finer)
float speckThresh = 0.97f;  // higher = fewer specks (was 0.85, cut ~80%)
float speckAmount = 0.85f;  // whiteness of a speck

sampler NormalSamp = sampler_state
{
    Texture = <NormalMap>;
    MipFilter = NONE;
    MinFilter = ANISOTROPIC;
    MagFilter = LINEAR;
    MaxAnisotropy = 8;
//    MipFilter = ANISOTROPIC;
//    MinFilter = ANISOTROPIC;
//    MagFilter = ANISOTROPIC;
   AddressU  = WRAP;     
   AddressV  = WRAP;     
};

samplerCUBE EnvSamp = sampler_state
{
    Texture = <EnvMap>;
    MipFilter = NONE;
    MinFilter = ANISOTROPIC;
    MagFilter = LINEAR;
    MaxAnisotropy = 8;
//    MipFilter = ANISOTROPIC;
//    MinFilter = ANISOTROPIC;
//    MagFilter = ANISOTROPIC;
   AddressU  = WRAP;     
    AddressV  = WRAP;
    AddressW  = WRAP;
};

sampler FresnelSamp = sampler_state
{
    Texture = <FresnelMap>;
    MipFilter = NONE;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
   AddressU  = CLAMP;     
   AddressV  = CLAMP;     
};

struct WATER_VS_INPUT
{
    float3 Pos         : POSITION;
   float2 NormUV      : TEXCOORD0;
};

struct WATER_VS_OUTPUT
{
    float4 Pos         : POSITION;
    float2 NormUV      : TEXCOORD0;
   float3 vView      : TEXCOORD1;
   float Fog         : TEXCOORD2;
};

WATER_VS_OUTPUT WaterVShader(WATER_VS_INPUT i)
{
    WATER_VS_OUTPUT o;
         
   o.Pos = mul(float4(i.Pos.xyz,1),mViewProj);

   o.Fog = dot(i.Pos,float3(mView._13,mView._23,mView._33)) + mView._43;
   o.Fog = 1 - (o.Fog-FogStart) * RFogRange;

   o.NormUV = i.NormUV;
   
   o.vView = normalize(i.Pos.xyz - ViewPos);

   return o;
}

float4 WaterPShader(WATER_VS_OUTPUT i) : COLOR
{
    float4 o;

   float3 vNorm  = tex2D(NormalSamp,i.NormUV * normalModifier.xyzw)*2 - 1;
   float3 vRefl  = normalize(reflect(i.vView,vNorm));
   float3 envCol = texCUBE(EnvSamp,vRefl).rgb;              // sky + sun reflection
   float  fres   = tex1D(FresnelSamp,dot(vRefl,vNorm)).r;   // grazing-angle mix
   fres = fres * reflectDamp;
   o.rgb = lerp(WaterCol,envCol,fres);
   // Sun glitter: the brightest reflected pixels are the sun in the cube;
   // amplify them, weighted to grazing angles, for moving glints on the sea.
   float lum = dot(envCol,float3(0.299f,0.587f,0.114f));
   o.rgb += envCol * saturate(lum - glintThreshold) * fres * glintBoost;
   // white specks
   float2 g1 = i.NormUV * speckTile;
   float  h1 = frac(sin(dot(floor(g1), float2(12.9898f,78.233f))) * 43758.5453f);
   float  d1 = length(frac(g1) - 0.5f);
   float  s1 = step(speckThresh, h1) * smoothstep(0.42f, 0.12f, d1) * speckAmount;
   o.rgb = lerp(o.rgb, float3(0.97f,0.98f,1.0f), saturate(s1));
   o.a = i.Fog;

    return o;
}

technique T1
{
   pass P0
   {       
      vertexshader = compile vs_1_1 WaterVShader();       
      pixelshader = compile ps_2_0 WaterPShader();
   }
}

struct FILLER_VS_INPUT
{
    float3 Pos         : POSITION;
   float2 NormUV      : TEXCOORD0;
};

struct FILLER_VS_OUTPUT
{
    float4 Pos         : POSITION;
   float Fog         : TEXCOORD0;
   float2 NormUV      : TEXCOORD1;
};

FILLER_VS_OUTPUT FillerVShader(FILLER_VS_INPUT i)
{
    FILLER_VS_OUTPUT o;
         
   o.Pos = mul(float4(i.Pos.xyz,1),mViewProj);

   o.Fog = dot(i.Pos,float3(mView._13,mView._23,mView._33)) + mView._43;
   o.Fog = 1 - (o.Fog-FogStart) * RFogRange;
   o.NormUV = i.NormUV;

   return o;
}

float4 FillerPShader(FILLER_VS_OUTPUT i) : COLOR
{
    float4 o;

   o.rgb = WaterCol;
   // white specks on the distant sea
   float2 g0 = i.NormUV * speckTile;
   float  h0 = frac(sin(dot(floor(g0), float2(12.9898f,78.233f))) * 43758.5453f);
   float  d0 = length(frac(g0) - 0.5f);
   float  s0 = step(speckThresh, h0) * smoothstep(0.42f, 0.12f, d0) * speckAmount;
   o.rgb = lerp(o.rgb, float3(0.97f,0.98f,1.0f), saturate(s0));
   o.a = i.Fog;

    return o;
}

technique T0
{
   pass P0
   {       
      vertexshader = compile vs_1_1 FillerVShader();       
      pixelshader = compile ps_2_0 FillerPShader();
   }
}