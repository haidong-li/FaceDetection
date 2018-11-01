//
//  ViewController.m
//  FaceDetection
//
//  Created by MDJJCW on 2018/7/31.
//  Copyright © 2018年 MDJJCW. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <opencv2/imgproc/types_c.h>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/opencv.hpp>
#import "FaceDlibWrapper.h"
#import <GPUImage/GPUImage.h>
#import <mach/message.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic,strong) AVCaptureSession *session;
@property (nonatomic,strong) UIImageView *cameraView;
@property (nonatomic,strong) dispatch_queue_t sample;
@property (nonatomic,strong) dispatch_queue_t faceQueue;
@property (nonatomic,strong) FaceDlibWrapper *dr;
@property (nonatomic,copy) NSArray *currentMetadata; //?< 如果检测到了人脸系统会返回一个数组 我们将这个数组存起来
@property (nonatomic,strong) UIImageView *top;
@property (nonatomic, strong) GPUImageChromaKeyFilter *filter1;//?< 滤镜
@property (nonatomic, strong) GPUImageBulgeDistortionFilter *filter2;//?< 滤镜
@property (nonatomic,strong) GPUImageFilterGroup    *filterGroup;
@property (nonatomic,strong) UILabel *distance;
@property(nonatomic,retain) CIDetector*faceDetector;

@property (nonatomic,strong) UIView *scoreZone;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    UIImageView *back = [[UIImageView alloc] initWithFrame:self.view.bounds];
    back.image = [UIImage imageNamed:@"1.jpg"];
    [self.view addSubview: back];
    self.filter1 = [[GPUImageChromaKeyFilter alloc] init];
    [self.filter1 setColorToReplaceRed:1. green:0 blue:0.];
    [self.filter1 setThresholdSensitivity:0.4];
    self.filter2 = [[GPUImageBulgeDistortionFilter alloc] init];
    self.filterGroup = [[GPUImageFilterGroup alloc] init];

    NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
    self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];

    _top = [[UIImageView alloc] initWithFrame:CGRectMake(0, 10, 100, 50)];
    _top.contentMode = UIViewContentModeScaleAspectFill;

    [self.cameraView addSubview: _top];
    _dr = [[FaceDlibWrapper alloc] init];
    _currentMetadata = [NSMutableArray arrayWithCapacity:0];
   
    [self.view addSubview: self.cameraView];
    
    _sample = dispatch_queue_create("sample", NULL);
    _faceQueue = dispatch_queue_create("face", NULL);
    
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
    
    AVCaptureMetadataOutput *metaout = [[AVCaptureMetadataOutput alloc] init];
    [metaout setMetadataObjectsDelegate:self queue:_faceQueue];
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
    
    if ([self.session canAddOutput:metaout]) {
        [self.session addOutput:metaout];
    }
    [self.session commitConfiguration];
    
    NSString     *key           = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber     *value         = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    
    [output setVideoSettings:videoSettings];
    
    //这里 我们告诉要检测到人脸 就给我一些反应，里面还有QRCode 等 都可以放进去，就是 如果视频流检测到了你要的 就会出发下面第二个代理方法
    [metaout setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];
    
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
    
    NSArray *facesLandmarks = [_dr detecitonOnSampleBuffer:sampleBuffer inRects:bounds];
    
    std::vector< std::vector<cv::Point> >  co_ordinates;

    CGPoint mouthCenter ;
    CGPoint leftCenter ;
    CGPoint rightCenter ;
    CGFloat mouthWith = 0;
    co_ordinates.push_back(std::vector<cv::Point>());
    for (NSArray *landmarks in facesLandmarks) {
        
        for (int i = 0; i < landmarks.count; i++) {
            NSValue *point = landmarks[i];
            CGPoint p = [point CGPointValue];
            cv::rectangle(mat, cv::Rect(p.x,p.y,4,4), cv::Scalar(0,255,0,255),-1);
   
        }
        
        CGFloat mouthCenterX = abs([landmarks[48] CGPointValue].x - [landmarks[54] CGPointValue].x) / 2 + [landmarks[48] CGPointValue].x;
        CGFloat mouthCenterY = abs([landmarks[51] CGPointValue].y - [landmarks[57] CGPointValue].y) / 2 + [landmarks[51] CGPointValue].y;
        mouthWith = abs([landmarks[48] CGPointValue].x - [landmarks[54] CGPointValue].x);
        mouthCenter = CGPointMake(mouthCenterX, mouthCenterY);
        
        CGFloat leftCenterX = abs([landmarks[36] CGPointValue].x - [landmarks[39] CGPointValue].x) / 2 + [landmarks[36] CGPointValue].x;
        CGFloat leftCenterY = (abs([landmarks[37] CGPointValue].y - [landmarks[41] CGPointValue].y)) / 2 + [landmarks[37] CGPointValue].y;
        leftCenter = CGPointMake(leftCenterX, leftCenterY);
        
        
        CGFloat rightCenterX = abs([landmarks[42] CGPointValue].x - [landmarks[45] CGPointValue].x) / 2 + [landmarks[42] CGPointValue].x;
        CGFloat rightCenterY = (abs([landmarks[44] CGPointValue].y - [landmarks[46] CGPointValue].y)) / 2 + [landmarks[44] CGPointValue].y;
        rightCenter = CGPointMake(rightCenterX, rightCenterY);
    }
    
    for (NSValue *rect in bounds) {
        CGRect r = [rect CGRectValue];
        //画框
        cv::rectangle(mat, cv::Rect(r.origin.x,r.origin.y,r.size.width,r.size.height), cv::Scalar(0,255,0,255));

    }
    
    CGRect r = [bounds.firstObject CGRectValue];
    CGFloat size = r.size.width * r.size.height;
   
    //这里不考虑性能 直接怼Image
    dispatch_async(dispatch_get_main_queue(), ^{
        self.distance.text = [NSString stringWithFormat:@"%@",size < 15000 ? @"大于一米" : @"小于一米"];
        self.cameraView.image = MatToUIImage(mat);
    });
}



- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    //当检测到了人脸会走这个回调
    _currentMetadata = metadataObjects;
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
