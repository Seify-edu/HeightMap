//
//  Shader.vsh
//  HeightMap
//
//  Created by Roman Smirnov on 08.12.13.
//  Copyright (c) 2013 Roman Smirnov. All rights reserved.
//

attribute highp vec4 position;
attribute vec3 normal;

varying lowp vec4 colorVarying;

uniform highp mat4 modelViewProjectionMatrix;
uniform mat3 normalMatrix;

void main()
{
    gl_Position = modelViewProjectionMatrix * position;
}
