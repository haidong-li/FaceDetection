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

    [self addGPUImageFilter:self.filter1];
    [self addGPUImageFilter:self.filter2];
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
        [self.session setSessionPreset:AVCaptureSessionPreset1920x1080];
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

    self.distance = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, 200, 50)];
    self.distance.textColor = [UIColor blackColor];
    [self.cameraView addSubview:self.distance];
    
    self.scoreZone = [[UIView alloc] initWithFrame:CGRectMake(0, 400, [UIScreen mainScreen].bounds.size.width, 100)];
    self.scoreZone.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.5];
    [self.view addSubview: self.scoreZone];
    
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
//        self.filter1.center = CGPointMake(leftCenter.x / image.size.width, leftCenter.y / image.size.height);
//        self.filter1.radius = 0.03;
//
        self.distance.text = [NSString stringWithFormat:@"%@",size < 15000 ? @"大于一米" : @"小于一米"];

//        self.filter2.center = CGPointMake(rightCenter.x / image.size.width, rightCenter.y / image.size.height);
//        self.filter2.radius = 0.03;
//
//        GPUImagePicture *stillImageSource = [[GPUImagePicture alloc]initWithImage:MatToUIImage(mat) smoothlyScaleOutput:YES];
//        [stillImageSource addTarget:self.filter1];
//
//
//        [stillImageSource processImage];
//
//        [self.filter1 useNextFrameForImageCapture];
//
//         UIImage *newImage = [self.filter1 imageFromCurrentFramebuffer];
//
        self.cameraView.image = MatToUIImage(mat);
    });
}

- (void)detectionFace:(CMSampleBufferRef)buffer
{
    NSLog(@"Faces thinking");
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, buffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *convertedImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
    
    if (attachments)
        CFRelease(attachments);
    NSDictionary *imageOptions = nil;
    
    imageOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:6] forKey:CIDetectorImageOrientation];
    
    NSLog(@"Face Detector %@", [self.faceDetector description]);
    NSLog(@"converted Image %@", [convertedImage description]);
    NSArray *features = [self.faceDetector featuresInImage:convertedImage options:imageOptions];
}

- (void)addGPUImageFilter:(GPUImageFilter *)filter{
    
    [self.filterGroup addFilter:filter];
    
    GPUImageOutput<GPUImageInput> *newTerminalFilter = filter;
    
    NSInteger count = self.filterGroup.filterCount;
    
    if (count == 1)
    {
        //设置初始滤镜
        self.filterGroup.initialFilters = @[newTerminalFilter];
        //设置末尾滤镜
        self.filterGroup.terminalFilter = newTerminalFilter;
        
    } else
    {
        GPUImageOutput<GPUImageInput> *terminalFilter    = self.filterGroup.terminalFilter;
        NSArray *initialFilters                          = self.filterGroup.initialFilters;
        
        [terminalFilter addTarget:newTerminalFilter];
        
        //设置初始滤镜
        self.filterGroup.initialFilters = @[initialFilters[0]];
        //设置末尾滤镜
        self.filterGroup.terminalFilter = newTerminalFilter;
    }
}


- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    //当检测到了人脸会走这个回调
    _currentMetadata = metadataObjects;
}

void LocalTranslationWarp(cv::Mat &img, int warpX, int warpY, int warpW, int warpH, int directionX, int directionY, double warpCoef)
{
//   cv:: RestrictBounds(warpX, warpY, warpW, warpH);
    
    cv::Mat imgCopy;
    copyMakeBorder(img, imgCopy, 0, 1, 0, 1, cv::BORDER_REPLICATE);
    
    cv::Point center(warpX + (warpW>>1), warpY + (warpH>>1));
    double radius = (warpW < warpH) ? (warpW >> 1) : (warpH >> 1);
    radius = radius * radius;
    
    // 平移方向矢量/模
    double transVecX = directionX - center.x;
    double transVecY = directionY - center.y;
    double transVecModel = transVecX*transVecX + transVecY*transVecY;
    
    // 水平/垂直增量//映射后位置与原位置
    double dx = 0, dy = 0, posX = 0.0, posY = 0.0, posU = 0.0, posV = 0.0;
    // 点到圆心距离/平移比例
    double distance = 0.0, ratio = 0.0;
    // 插值位置
    int startU = 0, startV = 0;
    double alpha = 0.0, beta = 0.0;
    
    int maxRow = warpY + warpH;
    int maxCol = warpX + warpW;
    uchar* pImg = NULL;
    for (int i = warpY; i < maxRow; i++)
    {
        pImg = img.data + img.step * i;
        for (int j = warpX; j < maxCol; j++)
        {
            posX = j;
            posY = i;
            dx = posX - center.x;
            dy = posY - center.y;
            distance = dx*dx + dy*dy;
            if (distance < radius)
            {
                ratio = (radius - distance) / (radius - distance + transVecModel * warpCoef);
                posU = posX - ratio * ratio * transVecX;
                posV = posY - ratio * ratio * transVecY;
                
                startU = (int)posU;
                startV = (int)posV;
                alpha = posU - startU;
                beta  = posV - startV;
//                BilinearInter(imgCopy, startU, startV, alpha, beta, pImg[3*j], pImg[3*j + 1], pImg[3*j + 2]);
            }
        }
    }
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
