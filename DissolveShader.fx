    //DX10 - GEOMETRY SHADER: DISSOLVE EFFECT
    //Digital Arts & Entertainment

    //************
    // VARIABLES *
    //************
    cbuffer cbPerObject
    {
        float4x4 gWorldViewProj : WorldViewProjection;
        float4x4 gWorldInverse : WorldInverse;
        float4x4 gViewInverse : VIEWINVERSE;
        float4x4 gWorld : World;
        float gTime : Time;

        float4 gColorDiffuse : COLOR = float4(0.75, 0.78, 0.5, 1.0);
        float3 gLightDirection = { 0.57f, -0.57f, 0.57f };
        bool gUseTexture = false;

        // Explode parameters
        float gExplodeDistance
	    <
		    string UIName = "Explode distance";
		    string UIWidget = "Slider";
		    float UIMin = 0;
		    float UIMax = 2;
		    float UIStep = 0.01;
	    > = 0.25f;
	
        float gExplodeTime
	    <
		    string UIName = "Explode duration";
		    string UIWidget = "Slider";
		    float UIMin = 0;
		    float UIMax = 5;
		    float UIStep = 0.01;
	    > = 1.5f;

        float gExplodeNoiseImpact = 2.0f;
        float gExplodeHeightInfluence = 1.0f;

        // Gravity parameters
        float gFloorHeight = 0;
        float gPileFlatness = 0.2f;
        float gPileShape = 0.1f;
        float gHeightDelay = 1.0f;
        float gSpeed = 1.0f;
    }

    Texture2D gTexture;

    Texture2D gNoiseMap
    <
	    string UIWidget = "Texture";
	    string ResourceName = "CobbleStone_HeightMap.dds";
    >;

    //SPECULAR
    //********
    float4 gColorSpecular
    <
	    string UIName = "Specular Color";
	    string UIWidget = "Color";
    > = float4(1, 1, 1, 1);

    Texture2D gTextureSpecularIntensity
    <
	    string UIName = "Specular Intensity Texture";
	    string UIWidget = "Texture";
	    string ResourceName = "CobbleStone_HeightMap.dds";
    >;

    bool gUseTextureSpecular
    <
	    string UIName = "Use Specular Level Texture?";
	    string UIWidget = "Bool";
    > = false;

    int gShininess
    <
	    string UIName = "Shininess";
	    string UIWidget = "Slider";
	    float UIMin = 1;
	    float UIMax = 100;
	    float UIStep = 0.01;
    > = 15;

    RasterizerState FrontCulling
    {
        CullMode = NONE;
    };

    SamplerState samLinear
    {
        Filter = MIN_MAG_MIP_LINEAR;
        AddressU = Wrap;
        AddressV = Wrap;
    };

    //**********
    // STRUCTS *
    //**********
    struct VS_DATA
    {
        float3 Position : POSITION;
        float3 Normal : NORMAL;
        float2 TexCoord : TEXCOORD;
    };

    struct GS_DATA
    {
        float4 PositionWorldView : SV_POSITION;
        float3 PositionWorld : POSITION;
        float3 Normal : NORMAL;
        float2 TexCoord : TEXCOORD0;
    };

    //SPECULAR FUNCTION (BLINN)
    float3 CalculateSpecularBlinn(float3 viewDirection, float3 normal, float2 texCoord)
    {
        float3 specularColor = float3(0.0f, 0.0f, 0.0f);
	
        float3 halfVector = -normalize(viewDirection - gLightDirection);
        float specularStrength = dot(halfVector, normal);
        specularStrength = saturate(specularStrength);
        specularStrength = pow(specularStrength, gShininess);
	
        if (gUseTextureSpecular)
        {
            specularColor = mul(gColorSpecular,
					    gTextureSpecularIntensity.Sample(samLinear, texCoord));
            specularColor = specularColor * specularStrength;
        }
        else
        {
            specularColor = gColorSpecular * specularStrength;
        }
	 
        return specularColor;
    }

    //****************
    // VERTEX SHADER *
    //****************
    VS_DATA MainVS(VS_DATA vsData)
    {
        return vsData;
    }

    //******************
    // GEOMETRY SHADER *
    //******************
    void Subdivide(VS_DATA vertsIn[3], out VS_DATA vertsOut[12])
    {
        VS_DATA m[3];
        // Calculate the 3 midpoints of the triangle edges
        m[0].Position = (vertsIn[0].Position + vertsIn[1].Position) * 0.5f;
        m[1].Position = (vertsIn[1].Position + vertsIn[2].Position) * 0.5f;
        m[2].Position = (vertsIn[2].Position + vertsIn[0].Position) * 0.5f;
        // Calculate normals of the midpoints
        m[0].Normal = (vertsIn[0].Normal + vertsIn[1].Normal) * 0.5f;
        m[1].Normal = (vertsIn[1].Normal + vertsIn[2].Normal) * 0.5f;
        m[2].Normal = (vertsIn[2].Normal + vertsIn[0].Normal) * 0.5f;
        // Calculate texture coordinates of the midpoints
        m[0].TexCoord = (vertsIn[0].TexCoord + vertsIn[1].TexCoord) * 0.5f;
        m[1].TexCoord = (vertsIn[1].TexCoord + vertsIn[2].TexCoord) * 0.5f;
        m[2].TexCoord = (vertsIn[2].TexCoord + vertsIn[0].TexCoord) * 0.5f;

        //            1
        //            *
        //	         / \
        //          /   \
        //         /  4  \
        //     m0 *-------* m1
        //       / \  2  / \
        //	    /   \   /   \
        //	   /  1  \ /  3  \
        //    *-------*-------*
        //    0 	 m2	      2

        // tri 1
        vertsOut[0] = vertsIn[0];
        vertsOut[1] = m[0];
        vertsOut[2] = m[2];

        // tri 2
        vertsOut[3] = m[0];
        vertsOut[4] = m[1];
        vertsOut[5] = m[2];

        // tri 3
        vertsOut[6] = m[2];
        vertsOut[7] = m[1];
        vertsOut[8] = vertsIn[2];

        // tri 4
        vertsOut[9] = m[0];
        vertsOut[10] = vertsIn[1];
        vertsOut[11] = m[1];
    }

    void ApplyGravity(inout VS_DATA vertsOut[12])
    {
        /**********************/
        /* DISSOLVE + GRAVITY */
        for (uint i = 0; i < 12; i += 3)
        {
            // Scale time
            float time = gTime * gSpeed;

            // Get vertices in world space
            float3 pointA = vertsOut[i].Position;
            float3 pointB = vertsOut[i + 1].Position;
            float3 pointC = vertsOut[i + 2].Position;

            pointA = mul(pointA, (float3x3) gWorld);
            pointB = mul(pointB, (float3x3) gWorld);
            pointC = mul(pointC, (float3x3) gWorld);

            // Noise Sample
            float3 noiseSample = float3(0.0f, 0.0f, 0.0f);
            noiseSample = gNoiseMap.SampleLevel(samLinear, vertsOut[i].TexCoord, 1.0f) - gFloorHeight;

            // Average height of the 3 vertices
            float averageHeight = (pointA.y + pointB.y + pointC.y) / 3.0f;

            // Average distance from center
            float localX = vertsOut[i].Position.x;
            float localZ = vertsOut[i].Position.z;
            float outwardDistance = sqrt(localX * localX + localZ * localZ);
        
            /*****************/
            /* ---EXPLODE--- */
            /*****************/
            float3 explodeNormal = (vertsOut[i].Normal + vertsOut[i + 1].Normal + vertsOut[i + 2].Normal) / 3;
            explodeNormal = normalize(explodeNormal);
            float3 explodeOffset = explodeNormal *gExplodeDistance;

            float explodeHeightInfluence = averageHeight * gExplodeHeightInfluence;

            pointA += explodeOffset * saturate(max(0, ((time - explodeHeightInfluence)))) * noiseSample.y * gExplodeNoiseImpact;
            pointB += explodeOffset * saturate(max(0, ((time - explodeHeightInfluence)))) * noiseSample.y * gExplodeNoiseImpact;
            pointC += explodeOffset * saturate(max(0, ((time - explodeHeightInfluence)))) * noiseSample.y * gExplodeNoiseImpact;

            /*****************/
            /* ---GRAVITY--- */
            /*****************/

            /* POINT A */
            // calculate a factor related to time and height to make the lowest points fall at a certain rate faster than the ones above
            float heightTimeOffset = max(0, time * time - averageHeight * gHeightDelay);
            // calculate noise factor
            float noise = (1 + noiseSample.z) / 2;
            // calculate factor that determines the fall depth
            float pileHeightFactor = pointA.y - pow(pointB.y / 4, 2) + outwardDistance * gPileShape;
            pileHeightFactor = max(0, pileHeightFactor);
            pileHeightFactor *= gPileFlatness;
            // calculate the actual offset with the above factors and the gHeightDelay
            float offset = heightTimeOffset * noise;
            offset = pow(offset, 2);
            // clamp the offset to the pile height
            offset = clamp(offset, 0, pileHeightFactor);
            pointA.y -= offset;
            pointA.y = max(gFloorHeight, gFloorHeight + pointA.y);

            /* POINT B */
            pileHeightFactor = pointB.y - pow(pointC.y / 4, 2) + outwardDistance * gPileShape;
            offset = heightTimeOffset * noise;
            offset = pow(offset, 2);
            offset = clamp(offset, 0, pointB.y);
            // lerp point B to floor height in order to connect each triangle to the floor
            pointB.y = lerp(pointB.y, gFloorHeight, offset / pointB.y);
            pointB.y = max(gFloorHeight, pointB.y);

            /* POINT C */
            pileHeightFactor = pointC.y - pow(pointA.y / 4, 2) + outwardDistance * gPileShape;
            pileHeightFactor = max(0, pileHeightFactor);
            pileHeightFactor *= gPileFlatness;
            offset = heightTimeOffset * noise;
            offset = pow(offset, 2);
            offset = clamp(offset, 0, pileHeightFactor);
            pointC.y -= offset;
            pointC.y = max(gFloorHeight, gFloorHeight + pointC.y);

            /* ------------ */
            /* ---OUTPUT--- */
            /* ------------ */
            vertsOut[i].Position = mul(pointA, (float3x3) gWorldInverse);
            vertsOut[i + 1].Position = mul(pointB, (float3x3) gWorldInverse);
            vertsOut[i + 2].Position = mul(pointC, (float3x3) gWorldInverse);
        }
    }

    void GenerateTriangles(triangle VS_DATA vertices[12], inout TriangleStream<GS_DATA> triStream)
    {
        GS_DATA vertsOut[12];
    
        // Put values in correct space
        for (int i = 0; i < 12; ++i)
        {
            vertsOut[i].PositionWorld = mul(float4(vertices[i].Position, 1.0f), gWorld).xyz;
            vertsOut[i].Normal = mul(vertices[i].Normal, (float3x3) gWorldInverse);
            vertsOut[i].PositionWorldView = mul(float4(vertices[i].Position, 1.0f), gWorldViewProj);
            vertsOut[i].TexCoord = vertices[i].TexCoord;
        }

        for (int j = 0; j < 12; j += 3)
        {
            // Append each tri to the stream separately
            triStream.Append(vertsOut[j]);
            triStream.Append(vertsOut[j + 1]);
            triStream.Append(vertsOut[j + 2]);
            triStream.RestartStrip();
        }
    }

    
    [maxvertexcount(48)]
    void GS(triangle VS_DATA vertsIn[3], inout TriangleStream<GS_DATA> triStream)
    {
        // Subdivide each triangle once (3 vertices -> 12 vertices)
        VS_DATA vertsSubdiv1[12];
        Subdivide(vertsIn, vertsSubdiv1);
        VS_DATA solidVerts[12] = vertsSubdiv1;

        // Subdivide each subdivided triangle again (12 vertices -> 48 vertices)
        VS_DATA vertsSubdiv2[4][12];
    
        for (int i = 0; i < 4; ++i)
        {
            VS_DATA input[3];
            input[0] = vertsSubdiv1[i * 3];
            input[1] = vertsSubdiv1[i * 3 + 1];
            input[2] = vertsSubdiv1[i * 3 + 2];
    
            Subdivide(input, vertsSubdiv2[i]);
            ApplyGravity(vertsSubdiv2[i]);
            GenerateTriangles(vertsSubdiv2[i], triStream);
        }
    }

    //***************
    // PIXEL SHADER *
    //***************
    float4 MainPS(GS_DATA input) : SV_TARGET
    {
        float diffuseStrength = max(dot(-gLightDirection, input.Normal), 0);
        float4 diffuse;
        if (gUseTexture)
            diffuse = gTexture.Sample(samLinear, input.TexCoord);
        else
            diffuse = gColorDiffuse * diffuseStrength;

        //SPECULAR
        float3 viewDirection = normalize(input.PositionWorld.xyz - gViewInverse[3].xyz);
        float3 specColor = CalculateSpecularBlinn(viewDirection, input.Normal, input.TexCoord);
		
        return diffuse + float4(specColor, 1);
    }


    //*************
    // TECHNIQUES *
    //************* 
    technique10 DefaultTechnique
    {
        pass p0
        {
            SetRasterizerState(FrontCulling);
            SetVertexShader(CompileShader(vs_4_0, MainVS()));
            SetGeometryShader(CompileShader(gs_4_0, GS()));
            SetPixelShader(CompileShader(ps_4_0, MainPS()));
        }
    }