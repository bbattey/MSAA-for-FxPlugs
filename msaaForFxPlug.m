//
//  msaaForFxPlug.m
//
//  NOT A STANDALONE SOURCE FILE
//
//  Code elements for implementing OpenGL Multisampled Fullscreen Antialiasing in the context of an
//  Apple Objective-C FxPlug project.
//
//  Could also be useful to people programming in other contexts. Just ignore the stuff about
//  setting up and reading FxPlug menu items and about storing/restoring the Motion context.
//
//  Developed and tested on Mac OS 10.11.2 with FxPlug 3.1 on Xcode 7.2 on Motion 5.2.2
//
//  Use at your own risk. I know just enough OpenGL and Objective-C to be dangerous.
//  Corrections and suggested improvements welcomed.
//
//  Created by Bret Battey on Dec 22, 2015. www.BatHatMedia.com
//


// ------------------------

// Some class variables that will be needed (I declare them in the FxPlug header file)
GLint       motionFB;
GLuint      framebuffer, renderbuffer;
GLenum      status;
GLint       msaaMaxSamples;


// ------------------------
// Code inside the
// - (id)initWithAPIManager:(id)apiManager
// method

// Check for the MSAA Max Samples supported by the
// GPU. Stricly speaking, the code should probably query to see
// if MSAA is even supported on the GPU, but it wouldn't be worth my time. Maybe
// it would be worth yours.

glGetIntegerv(GL_MAX_SAMPLES, &msaaMaxSamples);


// ------------------------

// What I placed inside the
// - (BOOL)addParameters
// method
// to create a popup populated with appropriate MSAA samples values

NSMutableArray *msaaSamplesMenuItems;
msaaSamplesMenuItems = [[NSMutableArray alloc] init];
// First menu item = 0
[msaaSamplesMenuItems addObject:@0];
// Populate menu items array with powers of two.
// I can't find confirmation that powers of two is necessary, but seems like a
// reasonable approach.
// Set the default value to menu item 2 (MSAA 4), since MSAA support up to 4 is supposed to
// be standard.
// I wonder how Motion will react if a user sets the MSAA samples to a level on one machine
// that isn't available when the project is moved to another machine, when this menu will change.
for (int i = 2; i <= msaaMaxSamples; i=i*2) {
    NSLog(@"i = %d",i);
    [msaaSamplesMenuItems addObject:[NSString stringWithFormat:@"%d", i]];
}

[parmsApi addPopupMenuWithName:[bundle localizedStringForKey: @"Antialiasing Samples"
                                                       value: NULL
                                                       table: NULL]
                        parmId:kMsaaMaxSamplesPopupID
                  defaultValue:2
                   menuEntries:msaaSamplesMenuItems
                     parmFlags:kFxParameterFlag_DEFAULT ] ;


// ------------------------

// Most action occurs in the
// - (BOOL)renderOutput: ...
// method, of course.
//

// First, get the MSAA samples menu value
int	msaaSamples ;
int	msaaSamplesMenuItem ;
[parmsApi getIntValue:&msaaSamplesMenuItem
             fromParm:kMsaaMaxSamplesPopupID
               atTime:renderInfo.time.frame];
// Convert menu item number to power of 2
msaaSamples = pow(2,msaaSamplesMenuItem);


// Then do the work... (if requested MSAA samples > 0, of course)

// Push recommended by FxPlug examples
// I haven't tested without a push/pop surrounding the code
glPushAttrib( GL_CURRENT_BIT );

// Create and activate a multisampled FBO for Multisample Antialiasing (MSAA).
// Based on clues from the following sites, accessed October 31 2015:
// https://www.opengl.org/wiki/Multisampling
// https://developer.apple.com/library/ios/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/WorkingwithEAGLContexts/WorkingwithEAGLContexts.html
// https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_offscreen/opengl_offscreen.html
// http://www.learnopengl.com/#!Advanced-OpenGL/Anti-aliasing
// And the FxPlug DirectionalBlur example

// Store the Motion FBO information
GLint   oldFBO;
GLint   oldTextureRect;
GLint   oldActiveTexture;
glGetIntegerv(GL_FRAMEBUFFER_BINDING, (GLint*)&oldFBO);
glGetIntegerv(GL_ACTIVE_TEXTURE, &oldActiveTexture);
glGetIntegerv(GL_TEXTURE_BINDING_RECTANGLE_ARB, &oldTextureRect);

// Make the multisample render buffer and its framebuffer.
// For now, only setting up a color buffer. Could set up additional buffer
// types to attach to the Framebuffer (see the OpenGLES reference above)
GLuint sampleFramebuffer;
GLuint sampleColorRenderbuffer;

// Generate a framebuffer and bind
glGenFramebuffers(1, &sampleFramebuffer);
glBindFramebuffer(GL_FRAMEBUFFER, sampleFramebuffer);
// Generate a render buffer and bind
glGenRenderbuffers(1, &sampleColorRenderbuffer);
glBindRenderbuffer(GL_RENDERBUFFER, sampleColorRenderbuffer);
// Create MSA buffer storage for the renderbuffer
glRenderbufferStorageMultisample(GL_RENDERBUFFER, msaaSamples, GL_RGBA8, (GLsizei)inWidth, (GLsizei)inHeight);
// Link
glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, sampleColorRenderbuffer);
// Check for framebuffer completeness
if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
// I GL ERROR-CHECK HERE

// Clear the new buffer
glClearColor( 0.0, 0.0, 0.0, 0.0 );
glClear(GL_COLOR_BUFFER_BIT);

// And enable the multisampling antialiasing joy
// (though by default is should already be on)
glEnable(GL_MULTISAMPLE);


// DRAW YOUR STUFF.
//
// Recognising that MSAA does NOT apply to line and point primitives. For those, as I understand it
// strictly one should do the following:
glDisable(GL_MULTISAMPLE);
glEnable(GL_POINT_SMOOTH); // or line smooth as the case may be
// draw your points
glEnable(GL_MULTISAMPLE);
glDisable(GL_POINT_SMOOTH);
// and return to drawing polygons

// AND WHEN DONE DRAWING...

// Setup to read from the multisampling buffer and draw to the Motion buffer
glBindFramebuffer(GL_DRAW_FRAMEBUFFER, oldFBO);
glBindFramebuffer(GL_READ_FRAMEBUFFER, sampleFramebuffer);
// Bit Block Transfer the sampleFramebuffer to the Motion FBO,
// OpenGL doc sez, "The lower bounds of the rectangle are inclusive,
// while the upper bounds are exclusive," so we can use inWidth, inHeight.
// The filter type (here GL_NEAREST) is not relevant, since the source and destination windows are the same size.
glBlitFramebuffer(0, 0, (GLint)inWidth, (GLint)inHeight, 0, 0, (GLint)inWidth, (GLint)inHeight, GL_COLOR_BUFFER_BIT, GL_NEAREST);
// I GL ERROR-CHECK HERE

// Restore Motion's original OpenGL state
glBindFramebuffer(GL_FRAMEBUFFER, oldFBO);
glActiveTexture(oldActiveTexture);
glBindTexture(GL_TEXTURE_RECTANGLE_ARB, oldTextureRect);

// Delete multisampling resources.
// Not sure if there is any significant gain to trying to retain some of these instead
// of deleting.
glDeleteRenderbuffers(1, &sampleColorRenderbuffer);
glDeleteFramebuffersEXT(1, &sampleFramebuffer);
// I GL ERROR-CHECK HERE

// Pop recommended by FxPlug examples
glPopAttrib();


// ------------------------

// If you work with image wells (drop zones)
// then you might need these codes to convert
// textures from RGB to RGBA
// this code is intended to be inserted below DRAW YOUR STUFF above

FxTexture *objectTexture = nil;
FxRenderInfo renderInfoObj = {0};
renderInfoObj.time.frame = 0;       //put your actual time here
renderInfoObj.qualityLevel = kFxQuality_HIGH;
renderInfoObj.fieldOrder = kFxFieldOrder_PROGRESSIVE;
renderInfoObj.scaleX = 1;
renderInfoObj.scaleY = 1;
renderInfoObj.depth = kFxDepth_FLOAT32;

BOOL bRes = [parmsApi getTexture:&objectTexture layerOffsetX:0 layerOffsetY:0 requestInfo:renderInfoObj fromParm:kLayerParamID atTime:renderInfoObj.time.frame];


//first we need to convert a texture from the drop zone to a RGBA texture
GLuint renderBufferInterm;
GLuint textureRGBA;

double objLeft, objRight, objTop, objBottom;

[objectTexture getTextureCoords:&objLeft
                          right:&objRight
                         bottom:&objBottom
                            top:&objTop];

//Generate FBO
glGenFramebuffers(1, &renderBufferInterm);
glBindFramebuffer(GL_FRAMEBUFFER, renderBufferInterm);

//Generate empty RGBA texture
glGenTextures(1, &textureRGBA);
glBindTexture(GL_TEXTURE_RECTANGLE_ARB, textureRGBA);

//remember current parameters
GLint oldMinFilter, oldMagFilter;
glGetTexParameteriv( GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, &oldMinFilter );
glGetTexParameteriv( GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, &oldMagFilter );

glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA, objRight - objLeft, objTop - objBottom, 0, GL_BGR, GL_UNSIGNED_BYTE, 0);

glFramebufferTextureEXT(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, textureRGBA, 0);
// Check for framebuffer completeness
if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));

//save current viewport and matrix mode
float viewPortDims[4];
glGetFloatv(GL_VIEWPORT, viewPortDims);

GLint matrixMode;
glGetIntegerv(GL_MATRIX_MODE, &matrixMode);

//set the coordinate system, with the origin in the top left
glViewport(0, 0, objRight - objLeft, objTop - objBottom);

glMatrixMode(GL_PROJECTION);
glPushMatrix();
glLoadIdentity();
glOrtho(0, objRight - objLeft, 0, objTop - objBottom, -1, 1);

//now draw  objectTexture to textureRGBA
[objectTexture bind];
[objectTexture enable];

glBegin(GL_QUADS);
{
    glTexCoord2d( objLeft, objBottom );     glVertex2d( objLeft, objBottom );
    glTexCoord2d( objRight, objBottom );    glVertex2d( objRight, objBottom );
    glTexCoord2d( objRight, objTop );       glVertex2d( objRight, objTop );
    glTexCoord2d( objLeft, objTop );        glVertex2d( objLeft, objTop );
}
glEnd();

//restore view port, matrix and FBO
glViewport(viewPortDims[0], viewPortDims[1], viewPortDims[2], viewPortDims[3]);
glPopMatrix();
glMatrixMode(matrixMode);
glBindFramebuffer(GL_FRAMEBUFFER, sampleFramebuffer);

//bind result RGBA texture
glBindTexture(GL_TEXTURE_RECTANGLE_ARB, textureRGBA);

// DRAW YOUR STUFF.
//

//delete resources
glDeleteTextures(1, &textureRGBA);
glDeleteRenderbuffers(1, &renderBufferInterm);


//Clear error state to not interfere with downstreaming plugins
glGetError();



// ------------------------

// I adapted the following from the FxPlug DirectionalBlur example and call it
// at the points labeled "I GL ERROR-CHECK HERE" above. Using a different
// checkpoint number at each location makes debugging much easier


+ (BOOL)isGlOKat:(int)checkpointNumber;
{
    BOOL    isOK = YES;
    
#if !NDEBUG
    GLenum  err     = glGetError();
    if (err != GL_NO_ERROR)
    {
        NSLog(@"GLError %d (0x%0x) in OptiNelder at checkpoint %d\n", err, err, checkpointNumber);
        isOK = NO;
    }
#endif // _DEBUG
    
    return isOK;
}

