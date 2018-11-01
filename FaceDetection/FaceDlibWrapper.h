//
//  FaceDlibWrapper.h
//  FaceDetection
//
//  Created by hfjk on 2018/8/2.
//  Copyright © 2018年 Huafu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
@interface FaceDlibWrapper : NSObject
- (NSArray <NSArray <NSValue *> *>*)detecitonOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects;
@end
