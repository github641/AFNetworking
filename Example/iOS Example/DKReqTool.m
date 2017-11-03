//
//  DKReqTool.m
//  DKNet
//
//  Created by alldk on 2017/7/10.
//  Copyright © 2017年 alldk. All rights reserved.
//

#import "DKReqTool.h"
@import AFNetworking;

/**
 回调某个时刻
 */
typedef void (^RightTime)(void);
/**
 回调数据 e.g.1
 */
typedef void (^GetDataSuccess)(NSDictionary *dic);

/**
 回调数据 e.g.2
 */
typedef void(^SuccBlock)(id resObj);

/**
 回调数据 e.g.3

 @param error 错误信息
 */
typedef void(^ErrorBlock)(NSError *error);

@implementation DKReqTool

#pragma mark - ================== Post  get基本使用 ==================
//HTTP Request Operation Manager
//POST请求
+ (void)postWithURL:(NSString *)url params:(NSDictionary *)params success:(SuccBlock)success failure:(ErrorBlock)failure
{
    /* lzy注170622：
     一、请求url
     1、采用baseUrl + relativeURL方式。
     AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:@""]];
     外部请求都是访问一个基本域名，只是后面的拼接稍有不同。
     https://api.aidianzhuan.com/user/tokenLogin
     https://api.aidianzhuan.com/version/getSetting
     baseUrl就是https://api.aidianzhuan.com/
     relativeURL外部传入不同的:user/tokenLogin或者version/getSetting
     
     2、或者baseUrl一直变化，不采用上一种，自己灵活控制。
     AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
     每次都传完整的请求url
     二、参数配置
     1、响应序列化，默认是使用的JSON。
     响应序列化指定为其他的类型，需要初始化对应的响应序列化类。
     1）、默认返回，不做任何解析   manager.responseSerializer = [AFHTTPResponseSerializer serializer];
     2）、manager.responseSerializer = [AFJSONResponseSerializer serializer];\manager.responseSerializer = [AFXMLParserResponseSerializer serializer];
     */
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
 
    //// 2.添加统一header
    [self addAFNHeader:manager];
    
    // 超时时间
    [manager.requestSerializer setTimeoutInterval:10.0];
    
    [manager POST:url parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        
        // 通知外面的block，请求成功了
        if (success) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                success(responseObject);
            });
            
        }
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
        //       [self showError:error.localizedDescription];
        
        if (failure) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
        
    }];
    
    
}


//HTTP Request Operation Manager
//Get请求
+ (void)getWithURL:(NSString *)url params:(NSDictionary *)params success:(SuccBlock)success failure:(ErrorBlock)failure
{
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer = [[AFHTTPRequestSerializer alloc] init];
    
    [manager GET:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
        
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        
        // 通知外面的block，请求成功了
        if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                    success(responseObject);
            });
            
        }
        
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
        // 通知外面的block，失败
        if (failure) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
        
        
    }];
    
    
}

+ (void)addAFNHeader:(AFHTTPSessionManager *)manager{
    
        NSDictionary *dic = [NSDictionary new];
        [dic enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop)
         {
             [manager.requestSerializer setValue:obj forHTTPHeaderField:key];
         }];
    
}
#pragma mark - ================== 上行加密 下行解密 ==================

/* lzy171103注:
 上行加密：
 
 POST：
 
 所有的请求方法，请求参数的的配置，最终都会走到一个方法中：
 
 AFURLRequestSerialization.m 560行左右
 
 #pragma mark - AFURLRequestSerialization
 
 - (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
 withParameters:(id)parameters
 error:(NSError *__autoreleasing *)error
 
 在其中：
 if (query && ![query isEqualToString:@""]) {
 
 //  NSData *bodyData = [[XXTEA encryptStringToBase64String:query stringKey:XXTEAKEYString sign:YES] dataUsingEncoding:self.stringEncoding];
 
 NSData *bodyData= [XXTEA encryptString:query stringKey:XXTEAKEYString sign:YES];
 //            DLog(@"%@",bodyData);
 [mutableRequest setHTTPBody:bodyData];
 
 }
 
 
 下行解密：
 设置 AFHTTPSessionManager的响应序列化（ResponseSerializer）为 不做处理的形式
 manager.responseSerializer = [AFHTTPResponseSerializer serializer];
 
 返回数据完成时肯定会走AFURLSessionManger.m的方法：
 #pragma mark - NSURLSessionTaskDelegate
 - (void)URLSession:(__unused NSURLSession *)session
 task:(NSURLSessionTask *)task
 didCompleteWithError:(NSError *)error
 
 不过一般在POST、GET的成功回调处理就好了，能不改三方最好
 - (NSURLSessionDataTask *)POST:(NSString *)URLString
 parameters:(id)parameters
 progress:(void (^)(NSProgress * _Nonnull))uploadProgress
 success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
 failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure
 
 
 
 猿题库的下行解密在 NetworkAgent的进行
 - (void)handleRequestResult:(NSURLSessionTask *)task responseObject:(id)responseObject error:(NSError *)error
 
 NSData *decodeData = [XXTEA decrypt:responseObject  stringKey:XXTEAKEYString sign:YES];
 
 */

@end
