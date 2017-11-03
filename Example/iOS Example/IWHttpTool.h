//
//  GMHttpTool.h
//
//  Created by 李光明 on 14-1-14.
//  Copyright   All rights reserved.
//  封装任何的http请求

#import <Foundation/Foundation.h>

/**
 *  请求成功后的回调
 *
 *  @param json 服务器返回的JSON数据
 */
typedef void (^IWHttpSuccess)(id json,NSURLResponse *res,NSURLRequest *req,NSString *resStr);
/**
 *  请求失败后的回调
 *
 *  @param error 错误信息
 */
typedef void (^IWHttpFailure)(NSError *error);




@interface IWHttpTool : NSObject

/**
 *  发送一POST请求
 *
 *  @param url    请求路径
 *  @param params 请求参数
 *  @param success 请求成功后的回调
 *  @param failure 请求失败后的回调
 */
+ (void)postWithURL:(NSString *)url params:(NSDictionary *)params success:(IWHttpSuccess)success failure:(IWHttpFailure)failure;

/**
 *  发送一GET请求
 *
 *  @param url    请求路径
 *  @param params 请求参数
 *  @param success 请求成功后的回调
 *  @param failure 请求失败后的回调
 */
+ (void)getWithURL:(NSString *)url params:(NSDictionary *)params success:(IWHttpSuccess)success failure:(IWHttpFailure)failure;



/**
 *  发送一POST请求 上传图片
 *
 *  @param url    请求路径
 *  @param params 请求参数
 *  @param success 请求成功后的回调
 *  @param failure 请求失败后的回调
 */
//
+ (void)updatePostData:(NSString *)url params:(NSDictionary *)params  imageData:(NSData *)imageData success:(IWHttpSuccess)success failure:(IWHttpFailure)failure;




@end
