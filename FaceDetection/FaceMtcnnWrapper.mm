//
//  FaceMtcnnWrapper.m
//  FaceDetection
//
//  Created by hfjk on 2018/11/2.
//  Copyright © 2018 Huafu. All rights reserved.
//

#import "FaceMtcnnWrapper.h"
#import "mtcnn.h"
#import <opencv2/imgproc/types_c.h>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/opencv.hpp>
@implementation FaceMtcnnWrapper
{
    MTCNN *mtcnn;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        mtcnn = new MTCNN([[[NSBundle mainBundle] bundlePath] UTF8String]);
        mtcnn->SetMinFace(40);
    }
    return self;
}


- (NSArray <Face  *>*)detectMaxFace:(UIImage *)image
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
    
    
    
    ncnn::Mat ncnn_img;
    ncnn_img = ncnn::Mat::from_pixels(rgba, ncnn::Mat::PIXEL_RGBA2RGB, w, h);
    
    std::vector<Bbox> finalBbox;
    mtcnn->detect(ncnn_img, finalBbox);
    
    int32_t num_face = static_cast<int32_t>(finalBbox.size());
    
    int out_size = 1+num_face*14;
    
    NSMutableArray *faceInfoArr = [NSMutableArray arrayWithCapacity:0];

    int *faceInfo = new int[out_size];
    faceInfo[0] = num_face;
    for(int i=0;i<num_face;i++){
        NSMutableArray *points = [NSMutableArray arrayWithCapacity:0];

        Face *faceInfo = [[Face alloc] init];
        CGRect rect = CGRectMake(finalBbox[i].x1, finalBbox[i].y1, finalBbox[i].x2 - finalBbox[i].x1, finalBbox[i].y2 - finalBbox[i].y1);
       
        for (int j =0;j<5;j++){
            CGPoint point = CGPointMake(finalBbox[i].ppoint[j], finalBbox[i].ppoint[j + 5]);
            [points addObject:[NSValue valueWithCGPoint:point]];
        }
        faceInfo.landmarks = points;
        faceInfo.rect = rect;
        [faceInfoArr addObject:faceInfo];
    }
    
 
    
    delete [] rgba;
    delete [] faceInfo;
    finalBbox.clear();
    return faceInfoArr;
}


@end
