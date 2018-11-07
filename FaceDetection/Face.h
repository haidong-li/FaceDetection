//
//  Face.h
//  FaceDetection
//
//  Created by hfjk on 2018/11/7.
//  Copyright © 2018 Huafu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface Face : NSObject

@property (nonatomic,assign) CGRect rect;
@property (nonatomic,assign) NSArray *landmarks;

@end
