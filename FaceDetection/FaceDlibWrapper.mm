//
//  FaceDlibWrapper.m
//  FaceDetection
//
//  Created by hfjk on 2018/8/2.
//  Copyright © 2018年 Huafu. All rights reserved.
//

#import "FaceDlibWrapper.h"

#import <dlib/image_processing.h>
#import <dlib/image_io.h>
//#import <dlib/f>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

typedef unsigned char uchar;

@implementation FaceDlibWrapper
{
    dlib::shape_predictor sp;
//    dlib::
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        //初始化 检测器
        NSString *modelFileName = [[NSBundle mainBundle] pathForResource:@"shape_predictor_68_face_landmarks" ofType:@"dat"];
        std::string modelFileNameCString = [modelFileName UTF8String];
     
        dlib::deserialize(modelFileNameCString) >> sp;
    }
    return self;
}

- (NSArray <NSArray <NSValue *> *>*)detecitonOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects {
    

    dlib::array2d<dlib::bgr_pixel> img;
    dlib::array2d<dlib::bgr_pixel> img_gray;
    // MARK: magic
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    char *baseBuffer = (char *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    // set_size expects rows, cols format
    img.set_size(height, width);
    
    // copy samplebuffer image data into dlib image format
    img.reset();
    long position = 0;
    while (img.move_next()) {
        dlib::bgr_pixel& pixel = img.element();
        
        // assuming bgra format here
        long bufferLocation = position * 4; //(row * width + column) * 4;
        char b = baseBuffer[bufferLocation];
        char g = baseBuffer[bufferLocation + 1];
        char r = baseBuffer[bufferLocation + 2];
        //        we do not need this
        //        char a = baseBuffer[bufferLocation + 3];
        
        dlib::bgr_pixel newpixel(b, g, r);
        pixel = newpixel;
        
        position++;
    }
    
    // unlock buffer again until we need it again
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    
    // convert the face bounds list to dlib format
    std::vector<dlib::rectangle> convertedRectangles = [self convertCGRectValueArray:rects];
    dlib::assign_image(img_gray, img);
  
    
    NSMutableArray *facesLandmarks = [NSMutableArray arrayWithCapacity:0];
    for (unsigned long j = 0; j < convertedRectangles.size(); ++j)
    {
        dlib::rectangle oneFaceRect = convertedRectangles[j];
        
        // detect all landmarks
        dlib::full_object_detection shape = sp(img, oneFaceRect);
        
        //shape 里面就是我们所需要的68 个点 因为dilb 跟 opencv 冲突 所以我们转换成Foundation 的 Array

        NSMutableArray *landmarks = [NSMutableArray arrayWithCapacity:0];
        for (int i = 0; i < shape.num_parts(); i++) {
            dlib::point p = shape.part(i);
            [landmarks addObject:[NSValue valueWithCGPoint:CGPointMake(p.x(), p.y())]];
        }
        [facesLandmarks addObject:landmarks];
    }

    
    return facesLandmarks;
}
- (std::vector<dlib::rectangle>)convertCGRectValueArray:(NSArray<NSValue *> *)rects {
    std::vector<dlib::rectangle> myConvertedRects;
    for (NSValue *rectValue in rects) {
        CGRect rect = [rectValue CGRectValue];
        long left = rect.origin.x;
        long top = rect.origin.y;
        long right = left + rect.size.width;
        long bottom = top + rect.size.height;
        dlib::rectangle dlibRect(left, top, right, bottom);
        
        myConvertedRects.push_back(dlibRect);
    }
    return myConvertedRects;
}


- (NSArray <NSValue*>*)detecitonOnSampleBuffer:(UIImage *)image faceRect:(CGRect)rect
{
    
    int w = image.size.width;
    int h = image.size.height;
    unsigned char* rgba = new unsigned char[w*h*4];
    {
        CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
        CGContextRef contextRef = CGBitmapContextCreate(rgba, w, h, 8, w*4,
                                                        colorSpace,
                                                        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
        
        CGContextDrawImage(contextRef, CGRectMake(0, 0, w, h), image.CGImage);
        CGContextRelease(contextRef);
    }

    dlib::array2d<dlib::bgr_pixel> img;
    dlib::array2d<dlib::bgr_pixel> img_gray;
    
    // set_size expects rows, cols format
    img.set_size(image.size.height, image.size.width);
    
    // copy samplebuffer image data into dlib image format
    img.reset();
    
    UIImageToDlibImage(image, img, true);
    
    dlib::assign_image(img_gray, img);
    
    dlib::rectangle oneFaceRect(rect.origin.x,rect.origin.y,rect.size.width,rect.size.height);
    
    // detect all landmarks
    dlib::full_object_detection shape = sp(img, oneFaceRect);
    
    //shape 里面就是我们所需要的68 个点 因为dilb 跟 opencv 冲突 所以我们转换成Foundation 的 Array
    
    NSMutableArray *landmarks = [NSMutableArray arrayWithCapacity:0];
    for (int i = 0; i < shape.num_parts(); i++) {
        dlib::point p = shape.part(i);
        [landmarks addObject:[NSValue valueWithCGPoint:CGPointMake(p.x(), p.y())]];
    }
    
    delete [] rgba;
    return landmarks;
}


void UIImageToDlibImage(const UIImage* uiImage, dlib::array2d<dlib::bgr_pixel> &dlibImage, bool alphaExist)
{
    CGFloat width = uiImage.size.width, height = uiImage.size.height;
    CGContextRef context;
    size_t pixelBits = CGImageGetBitsPerPixel(uiImage.CGImage);
    size_t pixelBytes = pixelBits/8;
    size_t dataSize = pixelBytes * ((size_t) width*height);
    uchar* imageData = (uchar*) malloc(dataSize);
    memset(imageData, 0, dataSize);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(uiImage.CGImage);
    
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast;
    bool isGray = false;
    if (CGColorSpaceGetModel(colorSpace) == kCGColorSpaceModelMonochrome) {
        // gray image
        bitmapInfo = kCGImageAlphaNone;
        isGray = true;
    }
    else
    {
        // color image
        if (!alphaExist) {
            bitmapInfo = kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault;
        }
    }
    
    context = CGBitmapContextCreate(imageData, (size_t) width, (size_t) height,
                                    8, pixelBytes*((size_t)width), colorSpace,
                                    bitmapInfo);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), uiImage.CGImage);
    CGContextRelease(context);
    
    dlibImage.clear();
    dlibImage.set_size((long)height, (long)width);
    dlibImage.reset();
    long position = 0;
    while (dlibImage.move_next()){
        dlib::bgr_pixel& pixel = dlibImage.element();
        
        long offset = position*((long) pixelBytes);
        uchar b, g, r;
        if (isGray) {
            b = imageData[offset];
            g = imageData[offset];
            r = imageData[offset];
        } else {
            b = imageData[offset];
            g = imageData[offset+1];
            r = imageData[offset+2];
        }
        pixel = dlib::bgr_pixel(b, g, r);
        position++;
    }
    free(imageData);
}


- (CGRect)findFace:(UIImage *)image
{
    //1 将UIImage转换成CIImage
    CIImage* ciimage = [CIImage imageWithCGImage:image.CGImage];
    //2.设置人脸识别精度
    NSDictionary* opts = [NSDictionary dictionaryWithObject:
                          CIDetectorAccuracyHigh forKey:CIDetectorAccuracy];
    //3.创建人脸探测器
    CIDetector* detector = [CIDetector detectorOfType:CIDetectorTypeFace
                                              context:nil options:opts];
    //4.获取人脸识别数据
    NSArray* features = [detector featuresInImage:ciimage];
    
    CGRect maxFace ;
    CGFloat area = 0;
    for (CIFaceFeature *faceFeature in features){
        if ((faceFeature.bounds.size.width * faceFeature.bounds.size.width) > area) {
            maxFace  =faceFeature.bounds;
            area = faceFeature.bounds.size.width * faceFeature.bounds.size.width;
        }
    }
    return maxFace;
}
@end
