Shader "Custom/UnityStandard_WaterFlow" {
	Properties{
		_BumpTex("Normal", 2D) = "bump" {}
		_NormalTiling("Normal Tiling", Vector) = (1,1,0,0)
		_FlowmapTex("Flowmap", 2D) = "white" {}
		_FlowSpeed("Flow Speed", Float) = 1
		_NoiseTex("Noise", 2D) = "white" {}
		_NoiseTiling("Noise Tiling", Vector) = (1,1,0,0)
		_NoiseScale("Noise Scale", Float) = 1
		_AnimLength("Animation Length", Float) = 8
		_SpecColor("Specular", Color) = (0.5,0.5,0.5,1)
		_Shininess("Shininess", Range(0.01, 10)) = 0.5
		_Cube("Reflection Cubemap", Cube) = "white" {}
		[HideInInspector]_ReflectionTex("Internal Reflection", 2D) = "" {}
		[HideInInspector]_RefractionTex("Internal Refraction", 2D) = "" {}
		[NoScaleOffset] _Fresnel("Fresnel (A) ", 2D) = "gray" {}
		_RefrColor("Refraction color", COLOR) = (.34, .85, .92, 1)
		_WaveScale("Wave scale", Range(0.02,0.15)) = 0.063
		_ReflDistort("Reflection distort", Range(0,30)) = 0.44
		_RefrDistort("Refraction distort", Range(0,30)) = 0.40
		[NoScaleOffset] _ReflectiveColor("Reflective color (RGB) fresnel (A) ", 2D) = "" {}
		[HideInInspector]WaveSpeed ("Wave speed (map1 x,y; map2 x,y)", Vector) = (19,9,-16,-7)
		_HorizonColor("Simple water horizon color", COLOR) = (.172, .463, .435, 1)
		_Tint("Tint Simple Water Reflection", Color) = (0.5,0.5,0.5,1)
		_Blend("Blend", Range(0.0,1.0)) = 0.5
	}

		SubShader{
		Tags{ "WaterMode" = "Refractive" "Queue" = "Transparent" }

		CGPROGRAM
	
	#pragma target 3.0

	
	#pragma surface surf Lambert alpha noforwardadd 		
	#pragma multi_compile WATER_REFRACTIVE WATER_REFLECTIVE WATER_SIMPLE

	#if defined (WATER_REFLECTIVE) || defined (WATER_REFRACTIVE)
	#define HAS_REFLECTION 1
	#endif
	#if defined (WATER_REFRACTIVE)
	#define HAS_REFRACTION 1
	#endif
	#include "UnityCG.cginc"

	#if HAS_REFLECTION
	float _ReflDistort;
	#endif

	#if HAS_REFRACTION
	float _RefrDistort;
	#endif

	sampler2D _BumpTex;
	sampler2D _FlowmapTex;
	sampler2D _NoiseTex;
	float4 _FlowmapUV;
	float _FlowSpeed;
	float _NoiseScale;
	float _AnimLength;
	float _Shininess;
	float2 _NormalTiling, _NoiseTiling;
	
	float _EditorTime;
	
	#if defined(WATER_REFRACTIVE)
	sampler2D _RefractionTex;
	sampler2D _Fresnel;
	float4 _RefrColor;
	#endif

	#if defined (WATER_REFLECTIVE) || defined (WATER_REFRACTIVE)
	sampler2D _ReflectionTex;
	#endif

	#if defined (WATER_REFLECTIVE) || defined (WATER_SIMPLE)
	sampler2D _ReflectiveColor;
	#endif

	#if defined(WATER_SIMPLE)
	samplerCUBE _Cube;
	float _Blend;
	half4 _Tint;
	half4 _HorizonColor;
	#endif

	struct Input {
		float2 uv_FlowmapTex;
		float3 worldRefl;
		float3 worldPos;
		float3 viewDir;
		float4 screenPos;
		INTERNAL_DATA
	};

	inline void GetFlowmapValues(float2 flowUV, sampler2D flowTex, sampler2D noiseTex, float noiseScale, float2 noiseTiling,
		float flowSpeed, float animLength, out float2 flowDir, out float4 flowmap, out float flowPhase0, out float flowPhase1, out float flowLerp) {
		//	offset the cycle reset to prevent pulsing		
		half phaseOffset = noiseScale * tex2D(noiseTex, flowUV * noiseTiling).g;
		//	uses information about the flowmap generator to offset uvs so that they match the flowmap generator in world space
		flowmap = tex2D(flowTex, flowUV);
		flowDir = (flowmap.xy * 2 - 1) * flowSpeed.xx;
		flowDir.x = clamp(flowDir.x, -1, 1);
		flowDir.y = clamp(flowDir.y, -1, 1);
		//	_EditorTime is assigned by an EditorShaderTime component in the scene, this allows the flowmap to work in the editor when not playing the game
		//	When the game is playing _EditorTime will be 0
		//	_AnimLength controls the length of a time cycle
		//	frac loops the value from 0->1
		flowPhase0 = frac(phaseOffset + (_Time.y + _EditorTime) / animLength);
		flowPhase1 = frac(phaseOffset + (_Time.y + _EditorTime) / animLength + 0.5);
		flowLerp = abs(0.5 - flowPhase0) * 2;
	}

	inline half Fresnel(float3 viewDir, float3 normal, float bias) {
		return lerp(pow(1.001 - dot(normalize(viewDir), normal), 1), 1, bias);
	}

	inline half3 GetFlowmapNormalsVelocityScaled(float2 flowUV, sampler2D normalTex, float2 tiling, float2 flowDir, float4 flowmap, float flowPhase0, float flowPhase1, float flowLerp) {
		//	lerp between two normal maps, fading out when the uvs are most distorted to the other normal map
		half4 detailNormalTex0 = tex2D(normalTex, flowUV * tiling + flowDir * flowPhase0);
		half4 detailNormalTex1 = tex2D(normalTex, flowUV * tiling + flowDir * flowPhase1);
		return lerp(float3(0, 0, 1), UnpackNormal(lerp(detailNormalTex0, detailNormalTex1, flowLerp)), clamp(pow(length(flowDir), 2), 0.1, 1));
	}

	void surf(Input IN, inout SurfaceOutput o) {
		float2 flowUV = IN.uv_FlowmapTex;
		float flowPhase0, flowPhase1, flowLerp;
		float2 flowDir;
		float4 flowmap;
		
		GetFlowmapValues(flowUV, _FlowmapTex, _NoiseTex, _NoiseScale, _NoiseTiling, _FlowSpeed, _AnimLength, flowDir, flowmap, flowPhase0, flowPhase1, flowLerp);
		float3 normal = GetFlowmapNormalsVelocityScaled(flowUV, _BumpTex, _NormalTiling, flowDir, flowmap, flowPhase0, flowPhase1, flowLerp);

		half fresnelFac = dot(IN.viewDir, normal);
				
		#if HAS_REFLECTION
		float4 uv1 = IN.screenPos; uv1.xy += normal * _ReflDistort;
		float3 refl = tex2Dproj(_ReflectionTex, UNITY_PROJ_COORD(uv1));
		#endif

		#if HAS_REFRACTION
		float4 uv2 = IN.screenPos; uv2.xy -= normal * _RefrDistort;
		float3 refr = tex2Dproj(_RefractionTex, UNITY_PROJ_COORD(uv2))* _RefrColor;
		#endif
		
		o.Normal = normal;
		o.Gloss = _SpecColor.rgb * Fresnel(IN.viewDir, o.Normal, 0.3);
		o.Specular = _Shininess;
		o.Alpha = 1;
				
		#if defined(WATER_REFRACTIVE)
		half fresnel = UNITY_SAMPLE_1CHANNEL(_Fresnel, float2(fresnelFac, fresnelFac));
		o.Emission = lerp(refr, refl, fresnel);
		#endif

		#if defined(WATER_REFLECTIVE)
		half4 water = tex2D(_ReflectiveColor, float2(fresnelFac, fresnelFac));
		o.Emission = lerp(water.rgb, refl.rgb, water.a);
		#endif

		#if defined(WATER_SIMPLE)
		half4 water = tex2D(_ReflectiveColor, float2(fresnelFac, fresnelFac));
		float3 x = texCUBE(_Cube, WorldReflectionVector(IN, o.Normal)).rgb;
		o.Emission = lerp(x * _Tint.rgb, x, _Blend) * o.Gloss;
		#endif

	}
	ENDCG
	}
		//FallBack "Specular"
}