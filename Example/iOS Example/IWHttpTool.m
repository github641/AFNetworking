//
//  IWHttpTool.m
//  01-ItcastWeibo
//
//  Created by apple on 14-1-14.
//  Copyright (c) 2014年 itcast. All rights reserved.
//

#import "IWHttpTool.h"
@import AFNetworking;



#define app_bundle_name ([NSBundle mainBundle].infoDictionary[@"CFBundleIdentifier"])
#define app_short_version ([NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"])

//------------------------------------------AFN框架------------------------------------------------

@implementation IWHttpTool

//HTTP Request Operation Manager
//POST请求
+ (void)postWithURL:(NSString *)url params:(NSDictionary *)params success:(IWHttpSuccess)success failure:(IWHttpFailure)failure
{
//    [self starInfocatorVisible];
    
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:@"baseUrl"]];
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    //// 2.添加统一header
    [self addAFNHeaderWith:manager];

    [manager.requestSerializer setTimeoutInterval:15.0];
    [manager POST:url parameters:params progress:^(NSProgress * _Nonnull uploadProgress) {
        
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
//        [self stopIndicatorVisible];
        // 通知外面的block，请求成功了
        if (success) {

        }
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//        [self stopIndicatorVisible];
        //       [self showError:error.localizedDescription];
        failure(error);
        
    }];
    
    
}

//+ (void)monitorNetwork{
//
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        //对网络状态进行监控
//        AFNetworkReachabilityManager *mgr = [AFNetworkReachabilityManager sharedManager];
//        [mgr setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
//            // 当网络状态发生改变的时候调用这个block
//            switch (status) {
//                case AFNetworkReachabilityStatusReachableViaWiFi:
//                    DLog(@"WIFI");
//                    [[NSNotificationCenter defaultCenter]postNotificationName:@"internet" object:nil];
//                    break;
//                case AFNetworkReachabilityStatusReachableViaWWAN:
//                    [[NSNotificationCenter defaultCenter ]postNotificationName:@"internet" object:nil];
//                    DLog(@"自带网络");
//                    break;
//
//                case AFNetworkReachabilityStatusNotReachable:
//                    DLog(@"没有网络");
//                    [SVProgressHUD showInfoWithStatus:@"似乎与互联网断开了连接！"];
//                    [[NSNotificationCenter defaultCenter ]postNotificationName:@"internetNO" object:nil];
//                    break;
//
//                case AFNetworkReachabilityStatusUnknown:
//                    NSLog(@"未知网络");
//                    [[NSNotificationCenter defaultCenter ]postNotificationName:@"internet" object:nil];
//                    break;
//                default:
//                    break;
//            }
//        }];
//        // 开始监控
//        [mgr startMonitoring];
//    });
//
//
//
//}




//HTTP Request Operation Manager
//Get请求
+ (void)getWithURL:(NSString *)url params:(NSDictionary *)params success:(IWHttpSuccess)success failure:(IWHttpFailure)failure
{
//    [self starInfocatorVisible];
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:@"baseUrl"]];
    manager.requestSerializer=[[AFHTTPRequestSerializer alloc]init];

    [manager GET:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
        
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
//        [self stopIndicatorVisible];
        
        // 通知外面的block，请求成功了
        if (success) {
            NSURLResponse *res=[task response];
            NSURLRequest *req=[task originalRequest];
            id json = [NSJSONSerialization JSONObjectWithData:responseObject options:NSJSONReadingMutableLeaves error:nil];
            success(json,res,req,@"");
        }
        
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        //        [self showError:error.localizedDescription];
//        [self stopIndicatorVisible];
        
        // 通知外面的block，失败
        if (failure) {
            failure(error);
        }
        
        
    }];
    
    
    
    
}






+ (void)updatePostData:(NSString *)url params:(NSDictionary *)params  imageData:(NSData *)imageData success:(IWHttpSuccess)success failure:(IWHttpFailure)failure{
//    [self starInfocatorVisible];
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:@"baseUrl"]];
    manager.requestSerializer=[[AFHTTPRequestSerializer alloc]init];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    // 2.添加统一header
    
    [manager.requestSerializer setTimeoutInterval:20.0];
    
    [manager POST:url parameters:params constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        //现在时间
        NSDate *nowDate = [NSDate date];
        NSDateFormatter *df = [[NSDateFormatter alloc]init];
        [df setTimeZone:[NSTimeZone localTimeZone]];
        [df setDateFormat:@"yyyyMMddHHmmss"];
        NSString *strNow = [df stringFromDate:nowDate];
        [formData appendPartWithFileData:imageData name:@"icon" fileName:[NSString stringWithFormat:@"icon_%@.png",strNow] mimeType:@"image/png"];
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        //计算文件的上传进度
//        DLog(@"%f",1.0 * uploadProgress.completedUnitCount / uploadProgress.totalUnitCount);
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
//        [self stopIndicatorVisible];
        NSURLResponse *res=[task response];
        NSURLRequest *req=[task originalRequest];
        
        //原始的URL
//        NSString * strdata =   [[NSString alloc] initWithData:decodeData encoding:NSUTF8StringEncoding];
        //转码
//        NSString *mycontent=[self jsonFromStr:strdata];
//
//        success(mycontent,res,req,strdata);
        
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        //        [self showError:error.localizedDescription];
    }];
    
    
}






/**
 * AFN 通过文件流图片上传
 *  @param url    请求路径
 *  @param params 请求参数
 *  @param success 请求成功后的回调
 *  @param failure 请求失败后的回调
 */

//#pragma mark - 通过二进制流上传 NDdata
//- (void)UploadImageForData:(UIImage *)img{
//
//    //图片转换成data  0.7是压缩范围
//    NSData *imgdata = UIImageJPEGRepresentation(img, 0.7);
//    //上传地址
//    NSURL *URL = [NSURL URLWithString:@"http://example.com/upload"];
//    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
//    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
//    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
//
//    NSURLSessionUploadTask *uploadTask = [manager uploadTaskWithRequest:request fromData:imgdata   progress:nil completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
//        if (error) {
//            DLog(@"Error: %@", error);
//        } else {
//            DLog(@"Success: %@ %@", response, responseObject);
//        }
//    }];
////    NSURL *filePath = [NSURL fileURLWithPath:@"file://path/to/image.png"];
////    NSURLSessionUploadTask *uploadTask = [manager uploadTaskWithRequest:request fromFile:filePath progress:nil completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
////        if (error) {
////            DLog(@"Error: %@", error);
////        } else {
////            DLog(@"Success: %@ %@", response, responseObject);
////        }
////    }];
////
//
//    [uploadTask resume];
//}






//xxtea 解密方法
+(NSString *)xxteaToString:(NSData *) xxteaData{
    
//    NSString *decStr=[XXTEA  decryptToString:xxteaData stringKey:XXTEAKEYString sign:YES];
    
    return [[NSString alloc] initWithData:xxteaData encoding:NSUTF8StringEncoding];
    
}

+(id)jsonFromStr:(NSString *)str{
    
    /* lzy注170620：
     anf对空值有过滤操作。不调用这个。
     */
    //对json格式null进行过滤
    //    NSString * mycontent = [str  stringByReplacingOccurrencesOfString:@":null" withString:@":\" \""];
    NSData *jsonData = [str dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                         options:NSJSONReadingMutableContainers
                                                           error:&err];
    return dict;
    
    
}

/**
 添加自定义的http请求header
 
 1、设备参数
 2、xxtea加密
 3、base64
 4、设置到header中
 */
+ (void)addAFNHeaderWith:(AFHTTPSessionManager *)manager{
    
    //    NSDictionary *IPInfo=[[NSUserDefaults standardUserDefaults]objectForKey:@"IPInfo"];
    
    NSString *keystr=[NSString stringWithFormat:@""];
    
    
    //    //XXET加密Header参数
//    NSData *encryptData=[XXTEA  encryptString:keystr stringKey:XXTEAKEYString sign:YES];
//    NSString *kstr= [Utility base64Encode:encryptData];
    
//    NSDictionary *d=[[NSDictionary alloc]initWithObjectsAndKeys:kstr, @"dianzhuan-agent", nil];
//    [d enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
//     {
//         [manager.requestSerializer setValue:obj forHTTPHeaderField:key];
//     }];
    
    //        ULog(@"idfa：%@ idfa_s:%@ uuid_k:%@ uuid_o:%@ ", [DzhbDeviceInfo idfa], [DzhbDeviceInfo simulateIDFA], [DzhbDeviceInfo uuidKeychain], [DzhbDeviceInfo openUUID]);
    
    
}


#pragma mark - 网络加载 指示器相关

//+ (void)starInfocatorVisible {
//
//
//    [SVProgressHUD setRingThickness:2];
//    [SVProgressHUD setRingRadius:2];
//    [SVProgressHUD setRingNoTextRadius:2];
//    //    [SVProgressHUD setCornerRadius:2];
//    [SVProgressHUD setDefaultStyle:SVProgressHUDStyleLight];
//
//    [SVProgressHUD setDefaultAnimationType:SVProgressHUDAnimationTypeNative];
//
//    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeClear];
//
//    [SVProgressHUD show];
//}
//
//
//+ (void)stopIndicatorVisible {
//
//
//    [SVProgressHUD dismissWithDelay:0.15];
//
//
//}
//
//+ (void)showError:(NSString *)errorString {
//
//
//    [SVProgressHUD showWithStatus:errorString];
//
//    [SVProgressHUD setDefaultStyle:SVProgressHUDStyleLight ];
//
//    [SVProgressHUD setDefaultAnimationType:SVProgressHUDAnimationTypeNative];
//
//    [SVProgressHUD setDefaultMaskType:SVProgressHUDMaskTypeClear ];
//
//
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//
//        [SVProgressHUD  dismiss];
//
//    });
//
//}



@end
