//
//  MtcnnDetectionViewController.m
//  FaceDetection
//
//  Created by hfjk on 2018/11/7.
//  Copyright © 2018 Huafu. All rights reserved.
//

#import "MtcnnDetectionViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <opencv2/imgproc/types_c.h>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/opencv.hpp>
#import "FaceMtcnnWrapper.h"
#import "Face.h"
@interface MtcnnDetectionViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic,strong) AVCaptureSession *session;
@property (nonatomic,strong) UIImageView *cameraView;
@property (nonatomic,strong) dispatch_queue_t sample;
@property (nonatomic,strong) dispatch_queue_t faceQueue;
@property (nonatomic,copy) NSArray *currentMetadata; //?< 如果检测到了人脸系统会返回一个数组 我们将这个数组存起来

@property (nonatomic,strong) FaceMtcnnWrapper *mt;
@end

@implementation MtcnnDetectionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view addSubview: self.cameraView];
    
    _mt = [[FaceMtcnnWrapper alloc] init];
    _sample = dispatch_queue_create("sample", NULL);
//    _faceQueue = dispatch_queue_create("face", NULL);
    
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *deviceF;
    for (AVCaptureDevice *device in devices )
    {
        if ( device.position == AVCaptureDevicePositionFront )
        {
            deviceF = device;
            break;
        }
    }
    
    // 如果改变曝光设置，可以将其返回到默认配置
    if ([deviceF isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        NSError *error = nil;
        if ([deviceF lockForConfiguration:&error]) {
            CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);
            [deviceF setExposurePointOfInterest:exposurePoint];
            [deviceF setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        
        
    }
    if ([deviceF isFocusModeSupported:AVCaptureFocusModeLocked]) {
        NSError *error = nil;
        if ([deviceF lockForConfiguration:&error]) {
            deviceF.focusMode = AVCaptureFocusModeLocked;
            [deviceF unlockForConfiguration];
        }
        else {
        }
    }
    
    AVCaptureDeviceInput*input = [[AVCaptureDeviceInput alloc] initWithDevice:deviceF error:nil];
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    
    [output setSampleBufferDelegate:self queue:_sample];
    
//    AVCaptureMetadataOutput *metaout = [[AVCaptureMetadataOutput alloc] init];
//    [metaout setMetadataObjectsDelegate:self queue:_faceQueue];
    self.session = [[AVCaptureSession alloc] init];
    
    
    [self.session beginConfiguration];
    if ([self.session canAddInput:input]) {
        [self.session addInput:input];
    }
    
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        [self.session setSessionPreset:AVCaptureSessionPreset640x480];
    }
    if ([self.session canAddOutput:output]) {
        [self.session addOutput:output];
    }
    
//    if ([self.session canAddOutput:metaout]) {
//        [self.session addOutput:metaout];
//    }
    [self.session commitConfiguration];
    
    NSString     *key           = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber     *value         = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    
    [output setVideoSettings:videoSettings];
    
    //这里 我们告诉要检测到人脸 就给我一些反应，里面还有QRCode 等 都可以放进去，就是 如果视频流检测到了你要的 就会出发下面第二个代理方法
//    [metaout setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];
    
    AVCaptureSession* session = (AVCaptureSession *)self.session;
    //前置摄像头一定要设置一下 要不然画面是镜像
    for (AVCaptureVideoDataOutput* output in session.outputs) {
        for (AVCaptureConnection * av in output.connections) {
            //判断是否是前置摄像头状态
            if (av.supportsVideoMirroring) {
                //镜像设置
                av.videoOrientation = AVCaptureVideoOrientationPortrait;
                av.videoMirrored = YES;
            }
        }
    }
    [self.session startRunning];

}



#pragma mark - AVCaptureSession Delegate -
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    
    
    
    NSMutableArray *bounds = [NSMutableArray arrayWithCapacity:0];
    for (AVMetadataFaceObject *faceobject in self.currentMetadata) {
        AVMetadataObject *face = [output transformedMetadataObjectForMetadataObject:faceobject connection:connection];
        [bounds addObject:[NSValue valueWithCGRect:face.bounds]];
    }
    
    UIImage *image = [self imageFromPixelBuffer:sampleBuffer];
    cv::Mat mat;
    UIImageToMat(image, mat);
    
    NSArray <Face *>*info = [_mt detectMaxFace:image];
    
    for (Face *face in info) {
        cv::rectangle(mat, cv::Rect(face.rect.origin.x,face.rect.origin.y,face.rect.size.width,face.rect.size.height), cv::Scalar(0,255,0,255));

        for (int i = 0; i < face.landmarks.count; i++) {
            NSValue *point = face.landmarks[i];
            CGPoint p = [point CGPointValue];
            cv::rectangle(mat, cv::Rect(p.x,p.y,4,4), cv::Scalar(0,255,0,255),-1);
        }
    }
    
    //这里不考虑性能 直接怼Image
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cameraView.image = MatToUIImage(mat);
    });
}



- (UIImage*)imageFromPixelBuffer:(CMSampleBufferRef)p {
    CVImageBufferRef buffer;
    buffer = CMSampleBufferGetImageBuffer(p);
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base;
    size_t width, height, bytesPerRow;
    base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    width = CVPixelBufferGetWidth(buffer);
    height = CVPixelBufferGetHeight(buffer);
    bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    CGColorSpaceRef colorSpace;
    CGContextRef cgContext;
    colorSpace = CGColorSpaceCreateDeviceRGB();
    cgContext = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    
    CGImageRef cgImage;
    UIImage *image;
    cgImage = CGBitmapContextCreateImage(cgContext);
    image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
    
    return image;
}

- (UIImageView *)cameraView
{
    if (!_cameraView) {
        _cameraView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        //不拉伸
        _cameraView.contentMode = UIViewContentModeScaleAspectFill;
    }
    return _cameraView;
}


@end
