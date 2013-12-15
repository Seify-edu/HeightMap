//
//  HMViewController.m
//  HeightMap
//
//  Created by Roman Smirnov on 08.12.13.
//  Copyright (c) 2013 Roman Smirnov. All rights reserved.
//

#import "HMViewController.h"

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

@interface HMViewController()
{
    int landscapeVertexArrayHeight;
    int landscapeVertexArrayWidth;
}

@end

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_NORMAL,
    NUM_ATTRIBUTES
};

@interface HMViewController () {
    GLuint _program;
    
    GLKMatrix4 _modelViewProjectionMatrix;
    GLKMatrix3 _normalMatrix;
    float _rotation;
    
    GLuint _vertexArray;
    GLuint _vertexBuffer;
}
@property (strong, nonatomic) EAGLContext *context;
@property GLfloat *terrain;

- (void)setupGL;
- (void)tearDownGL;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation HMViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    self.preferredFramesPerSecond = 60;
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [self loadLevel];
    [self setupGL];
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
    
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    

    
    glEnable(GL_DEPTH_TEST);
    
    glGenVertexArraysOES(1, &_vertexArray);
    glBindVertexArrayOES(_vertexArray);
    
    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, landscapeVertexArrayWidth * landscapeVertexArrayHeight * 2 * 6 * sizeof(GLfloat), self.terrain, GL_STATIC_DRAW);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribNormal);
    glVertexAttribPointer(GLKVertexAttribNormal, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(12));
    
    glBindVertexArrayOES(0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteVertexArraysOES(1, &_vertexArray);
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

#pragma mark - Game logic

- (GLfloat *)loadTerrainFromImage:(UIImage *)map
{
    CGImageRef imageRef = [map CGImage];
    int imageWidth = [@( CGImageGetWidth(imageRef) ) intValue];
    int imageHeight = [@( CGImageGetHeight(imageRef) ) intValue];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(imageHeight * imageWidth * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * imageWidth;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, imageWidth, imageHeight,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, imageWidth, imageHeight), imageRef);
    CGContextRelease(context);
        
    // Now your rawData contains the image data in the RGBA8888 pixel format.
//    int byteIndex = (bytesPerRow * yy) + xx * bytesPerPixel;
//    for (int ii = 0 ; ii < count ; ++ii)
//    {
//        CGFloat red   = (rawData[byteIndex]     * 1.0) / 255.0;
//        CGFloat green = (rawData[byteIndex + 1] * 1.0) / 255.0;
//        CGFloat blue  = (rawData[byteIndex + 2] * 1.0) / 255.0;
//        CGFloat alpha = (rawData[byteIndex + 3] * 1.0) / 255.0;
//        byteIndex += 4;
//        
//        UIColor *acolor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
//        [result addObject:acolor];
//    }
    
    const GLfloat LANDSCAPE_MIN_X = -0.5;
    const GLfloat LANDSCAPE_MAX_X = 0.5;
    const GLfloat LANDSCAPE_WIDTH = LANDSCAPE_MAX_X - LANDSCAPE_MIN_X;
    const GLfloat LANDSCAPE_MIN_Z = -0.5;
    const GLfloat LANDSCAPE_MAX_Z = 0.5;
    const GLfloat LANDSCAPE_HEIGHT = LANDSCAPE_MAX_Z - LANDSCAPE_MIN_Z;
    
    const int POINTS_IN_TRIANGLE = 3;
    const int COORDS_PER_POINT = 3;
    const int NORMAL_COORDS_PER_POINT = 3;

    int redundantTriOffset = 1;
    
    const int BUFFER_MAX_WIDTH = 256;
    const int BUFFER_MAX_HEIGHT = 256;
    
    landscapeVertexArrayHeight = MIN( BUFFER_MAX_WIDTH, imageHeight );
    landscapeVertexArrayWidth =  MIN( BUFFER_MAX_HEIGHT, imageWidth + redundantTriOffset );
    
    NSLog(@"rawData is %lu", imageHeight * imageWidth * 4 * sizeof(unsigned char));
    
    float scaleX = imageWidth / ( landscapeVertexArrayWidth - redundantTriOffset );
    float scaleY = imageHeight / landscapeVertexArrayHeight;
    
    self.terrain = calloc(landscapeVertexArrayHeight * landscapeVertexArrayWidth * POINTS_IN_TRIANGLE * (COORDS_PER_POINT + NORMAL_COORDS_PER_POINT), sizeof(GLfloat));

    for ( int j = 0; j < landscapeVertexArrayHeight; j++ )
    {
        for ( int i = 0; i < landscapeVertexArrayWidth - redundantTriOffset; i++ )
        {
            GLKVector3 point1;
            point1.x = LANDSCAPE_MIN_X + LANDSCAPE_WIDTH * [@(i) doubleValue] / [@(landscapeVertexArrayWidth - redundantTriOffset) doubleValue];
            int point1indexInRaw = ( imageWidth * j * scaleY + i * scaleX ) * 4;
            point1.y = [@(rawData[point1indexInRaw]) doubleValue] / 255.0;
            point1.z = LANDSCAPE_MIN_Z + LANDSCAPE_HEIGHT * j / ( landscapeVertexArrayHeight );
            
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 0] = point1.x;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 1] = point1.y;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 2] = point1.z;
            
            GLKVector3 normalPoint1 = GLKVector3Normalize(point1);

            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 3] = normalPoint1.x;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 4] = normalPoint1.y;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 5] = normalPoint1.z;
            
            GLKVector3 point2;
            point2.x = LANDSCAPE_MIN_X + LANDSCAPE_WIDTH * [@( i ) doubleValue] / [@(landscapeVertexArrayWidth - redundantTriOffset) doubleValue];
            int point2indexInRaw = ( j >= landscapeVertexArrayHeight - redundantTriOffset - 1 ) ?
            ( imageWidth * j * scaleY + i * scaleX) * 4 :
            ( imageWidth * ( j + 1 ) * scaleY + i * scaleX ) * 4;
            point2.y =  [@(rawData[point2indexInRaw]) doubleValue] / 255.0;
            point2.z = LANDSCAPE_MIN_Z + LANDSCAPE_HEIGHT * [@( j + 1 ) doubleValue] / [@( landscapeVertexArrayHeight ) doubleValue];
            
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 6] = point2.x;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 7] = point2.y;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 8] = point2.z;
            
            GLKVector3 normalPoint2 = GLKVector3Normalize(point2);

            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 9 ] = normalPoint2.x;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 10] = normalPoint2.y;
            self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 11] = normalPoint2.z;
        }
    }
    
    for ( int j = 0; j < landscapeVertexArrayHeight; j++ )
    {
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 0] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 2 ) * 12 + 6];
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 1] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 2 ) * 12 + 7];
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 2] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 2 ) * 12 + 8];
        
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 6] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth + 0 ) * 12 + 0];
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 7] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth + 0 ) * 12 + 1];
        self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth - 1 ) * 12 + 8] = self.terrain[( ( j + 1 ) * landscapeVertexArrayWidth + 0 ) * 12 + 2];
    }
    
//    for ( int j = 30; j < 32; j++ )
//    {
//        for ( int i = 0; i < landscapeVertexArrayWidth; i++ )
//        {
//            NSLog(@"vao[%d][%d] 1 = %.2f, %.2f, %.2f", j, i,
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 0],
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 1],
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 2]
//                  );
//
//            NSLog(@"vao[%d][%d] 2 = %.2f, %.2f, %.2f", j, i,
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 6],
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 7],
//                  self.terrain[( j * landscapeVertexArrayWidth + i ) * 12 + 8]
//                  );
//        }
//    }
    
    free(rawData);
    
    return nil;
}

- (void)loadLevel
{
    UIImage *mapHeight = [UIImage imageNamed:@"Map.png"];
    [self loadTerrainFromImage:mapHeight];
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    GLKMatrix4 baseModelViewMatrix = GLKMatrix4Identity;
    
    GLKMatrix4 modelViewMatrix;
    
//    modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, -0.5f, -2.0f);
//    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 0.0f, 1.0f, 0.0f);
    
    modelViewMatrix = GLKMatrix4MakeLookAt( 0.0, -5.0, -3.0,
                                            0.0, 0.0, 0.0,
                                            1.0, 0.0, 0.0);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 1.0f, .0f, 0.0f);

    
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelViewMatrix), NULL);
    
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    _rotation += self.timeSinceLastUpdate * 0.5f;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glBindVertexArrayOES(_vertexArray);
    
    // Render the object with ES2
    glUseProgram(_program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
    glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, _normalMatrix.m);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, landscapeVertexArrayWidth * landscapeVertexArrayHeight * 2);
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(_program, GLKVertexAttribNormal, "normal");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    uniforms[UNIFORM_NORMAL_MATRIX] = glGetUniformLocation(_program, "normalMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

@end
