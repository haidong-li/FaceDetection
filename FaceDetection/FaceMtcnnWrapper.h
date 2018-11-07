//
//  FaceMtcnnWrapper.h
//  FaceDetection
//
//  Created by hfjk on 2018/11/2.
//  Copyright © 2018 Huafu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Face.h"

@interface FaceMtcnnWrapper : NSObject
- (NSArray <Face *>*)detectMaxFace:(UIImage *)image;

@end
