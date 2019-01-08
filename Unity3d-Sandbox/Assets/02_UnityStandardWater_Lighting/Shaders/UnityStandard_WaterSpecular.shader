Shader "Custom/UnityStandard_WaterSpecular" {
	Properties{
		_WaveScale("Wave scale", Range(0.02,0.15)) = 0.063
		_ReflDistort("Reflection distort", Range(0,1.5)) = 0.44
		_RefrDistort("Refraction distort", Range(0,1.5)) = 0.40
		_RefrColor("Refraction color", COLOR) = (.34, .85, .92, 1)
		[NoScaleOffset] _Fresnel("Fresnel (A) ", 2D) = "gray" {}
		[NoScaleOffset] _BumpMap("Normalmap ", 2D) = "bump" {}
		WaveSpeed("Wave speed (map1 x,y; map2 x,y)", Vector) = (19,9,-16,-7)
		[NoScaleOffset] _ReflectiveColor("Reflective color (RGB) fresnel (A) ", 2D) = "" {}
		_ReflectionTex("Internal Reflection", 2D) = "" {}
		_RefractionTex("Internal Refraction", 2D) = "" {}
		_Gloss("Gloss", Range(0.1, 50)) = 1.
		_Specular("Specular", Range(0.1, 50)) = 1.
		_SpecColor("Specular color", color) = (1., 1., 1., 1.)
	}

		Subshader
		{
			Tags { "WaterMode" = "Refractive" "RenderType" = "Opaque" "Queue" = "Transparent"}
			Pass {

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag

			#include "Lighting.cginc"

			uniform float4 _WaveScale4;
			uniform float4 _WaveOffset;

			uniform float _ReflDistort;
			uniform float _RefrDistort;

			sampler2D _ReflectionTex;
			float4 _RefractionTex_ST;

			sampler2D _ReflectiveColor;

			sampler2D _Fresnel;
			sampler2D _RefractionTex;
			uniform float4 _RefrColor;

			sampler2D _BumpMap;

			struct appdata {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 texcoord : TEXCOORD0;
			};

			struct v2f {

				UNITY_POSITION(pos);
				float4 ref : TEXCOORD0;
				float4 wpos : TEXCOORD1;
				float2 bumpuv0 : TEXCOORD2;
				float2 bumpuv1 : TEXCOORD3;
				float3 viewDir : TEXCOORD4;
				fixed3 lightDir : TEXCOORD6;
				float3 worldNormal : TEXCOORD7;
				float3 worldViewDir : TEXCOORD8;
				float4 tSpace0 : TEXCOORD9;
				float4 tSpace1 : TEXCOORD10;
				float4 tSpace2 : TEXCOORD11;
			};

			v2f vert(appdata_full v)
			{
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				o.pos = UnityObjectToClipPos(v.vertex);

				float4 temp;
				o.wpos = mul(unity_ObjectToWorld, v.vertex);
				temp.xyzw = o.wpos.xzxz * _WaveScale4 + _WaveOffset;
				o.bumpuv0 = temp.xy;
				o.bumpuv1 = temp.wz;

				o.viewDir.xzy = WorldSpaceViewDir(v.vertex);
				o.ref.y = 1 - o.ref.y;

				o.worldNormal = normalize(mul(v.normal, (float3x3)unity_WorldToObject));
				o.worldViewDir = normalize(UnityWorldSpaceViewDir(o.wpos));

				fixed3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
				fixed tangentSign = v.tangent.w * unity_WorldTransformParams.w;
				fixed3 worldBinormal = cross(o.worldNormal, worldTangent) * tangentSign;

				o.tSpace0 = float4(worldTangent.x, worldBinormal.x, o.worldNormal.x, o.wpos.x);
				o.tSpace1 = float4(worldTangent.y, worldBinormal.y, o.worldNormal.y, o.wpos.y);
				o.tSpace2 = float4(worldTangent.z, worldBinormal.z, o.worldNormal.z, o.wpos.z);
				o.lightDir = WorldSpaceLightDir(v.vertex);
				o.ref = ComputeNonStereoScreenPos(o.pos);
				return o;
			}

			uniform float4 _Normal_ST;


			uniform half _Specular;
			uniform half _Gloss;

			half3 bump;
			half4 color;

			void surf(appdata i, inout SurfaceOutput o)
			{
				o.Normal = bump;
				o.Albedo = color;
				o.Specular = _Specular;
				o.Gloss = _Gloss;
				o.Alpha = 1;
			}


			half4 frag(v2f i) : SV_Target
			{
				appdata surfIN;

				_Normal_ST.xy = i.bumpuv0;
				_Normal_ST.zw = i.bumpuv1;

				UNITY_EXTRACT_TBN(i);

				UNITY_INITIALIZE_OUTPUT(appdata, surfIN);

				SurfaceOutput o;

				o.Albedo = 0.0;
				o.Emission = 0.0;
				o.Specular = 0.0;
				o.Alpha = 0.0;
				o.Gloss = 0.0;
				o.Normal = fixed3(0, 0, 1);

				// call surface function
				i.viewDir = normalize(i.viewDir);

				half dist = distance(i.wpos, _WorldSpaceCameraPos);

				// combine two scrolling bumpmaps into one
				half3 bump1 = UnpackNormal(tex2D(_BumpMap, i.bumpuv0)).rgb;
				half3 bump2 = UnpackNormal(tex2D(_BumpMap, i.bumpuv1)).rgb;
				bump = (bump1 + bump2) * 0.5;

				surf(surfIN, o);

				fixed4 c = 0;
				float3 worldN;
				worldN.x = dot(_unity_tbn_0, o.Normal);
				worldN.y = dot(_unity_tbn_1, o.Normal);
				worldN.z = dot(_unity_tbn_2, o.Normal);
				worldN = normalize(worldN);
				o.Normal = worldN;

				// fresnel factor
				half fresnelFac = dot(i.viewDir, bump);
				// perturb reflection/refraction UVs by bumpmap, and lookup colors
				float4 uv1 = i.ref; uv1.xy += bump * _ReflDistort;
				half4 refl = tex2Dproj(_ReflectionTex, UNITY_PROJ_COORD(uv1));

				UnityLight ul;
				UNITY_INITIALIZE_OUTPUT(UnityLight, ul);
				ul.color = refl;
				ul.dir = i.lightDir;

				c += UnityBlinnPhongLight(o, i.worldViewDir, ul);
				refl = c + refl;

				float4 uv2 = i.ref; uv2.xy -= bump * _RefrDistort;
				half4 refr = tex2Dproj(_RefractionTex, UNITY_PROJ_COORD(uv2)) * _RefrColor;

				half fresnel = UNITY_SAMPLE_1CHANNEL(_Fresnel, float2(fresnelFac, fresnelFac));
				color = lerp(refr, refl, fresnel);

				return color;
			}
			ENDCG

			}
		}

}