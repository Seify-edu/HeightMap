//
//  Shader.fsh
//  HeightMap
//
//  Created by Roman Smirnov on 08.12.13.
//  Copyright (c) 2013 Roman Smirnov. All rights reserved.
//

varying lowp vec4 colorVarying;

void main()
{
    gl_FragColor = colorVarying;
}