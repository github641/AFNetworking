// AFImageDownloader.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV

#import "AFImageDownloader.h"
#import "AFHTTPSessionManager.h"

@interface AFImageDownloaderResponseHandler : NSObject
@property (nonatomic, strong) NSUUID *uuid;
@property (nonatomic, copy) void (^successBlock)(NSURLRequest*, NSHTTPURLResponse*, UIImage*);
@property (nonatomic, copy) void (^failureBlock)(NSURLRequest*, NSHTTPURLResponse*, NSError*);
@end

@implementation AFImageDownloaderResponseHandler

- (instancetype)initWithUUID:(NSUUID *)uuid
                     success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, UIImage *responseObject))success
                     failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    if (self = [self init]) {
        self.uuid = uuid;
        self.successBlock = success;
        self.failureBlock = failure;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat: @"<AFImageDownloaderResponseHandler>UUID: %@", [self.uuid UUIDString]];
}

@end

@interface AFImageDownloaderMergedTask : NSObject
@property (nonatomic, strong) NSString *URLIdentifier;
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableArray <AFImageDownloaderResponseHandler*> *responseHandlers;

@end

@implementation AFImageDownloaderMergedTask

- (instancetype)initWithURLIdentifier:(NSString *)URLIdentifier identifier:(NSUUID *)identifier task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.URLIdentifier = URLIdentifier;
        self.task = task;
        self.identifier = identifier;
        self.responseHandlers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)addResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers addObject:handler];
}

- (void)removeResponseHandler:(AFImageDownloaderResponseHandler*)handler {
    [self.responseHandlers removeObject:handler];
}

@end

@implementation AFImageDownloadReceipt

- (instancetype)initWithReceiptID:(NSUUID *)receiptID task:(NSURLSessionDataTask *)task {
    if (self = [self init]) {
        self.receiptID = receiptID;
        self.task = task;
    }
    return self;
}

@end

@interface AFImageDownloader ()

@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@property (nonatomic, strong) dispatch_queue_t responseQueue;

@property (nonatomic, assign) NSInteger maximumActiveDownloads;
@property (nonatomic, assign) NSInteger activeRequestCount;

@property (nonatomic, strong) NSMutableArray *queuedMergedTasks;
@property (nonatomic, strong) NSMutableDictionary *mergedTasks;

@end


@implementation AFImageDownloader

+ (NSURLCache *)defaultURLCache {
    // It's been discovered that a crash will occur on certain versions
    // of iOS if you customize the cache.
    //
    // More info can be found here: https://devforums.apple.com/message/1102182#1102182
    //
    // When iOS 7 support is dropped, this should be modified to use
    // NSProcessInfo methods instead.
    if ([[[UIDevice currentDevice] systemVersion] compare:@"8.2" options:NSNumericSearch] == NSOrderedAscending) {
        return [NSURLCache sharedURLCache];
    }
    //设置一个系统缓存，内存缓存为20M，磁盘缓存为150M，
    //这个是系统级别维护的缓存。
    return [[NSURLCache alloc] initWithMemoryCapacity:20 * 1024 * 1024
                                         diskCapacity:150 * 1024 * 1024
                                             diskPath:@"com.alamofire.imagedownloader"];
}

+ (NSURLSessionConfiguration *)defaultURLSessionConfiguration {
    // session 的 Configuration 设置了 NSURLCache来 缓存各种请求
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    //TODO set the default HTTP headers
    
    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;
    
    configuration.requestCachePolicy = NSURLRequestUseProtocolCachePolicy;
    configuration.allowsCellularAccess = YES;
    configuration.timeoutIntervalForRequest = 60.0;
    /* lzy注170706：
     * AF自己控制的图片缓存用AFAutoPurgingImageCache，而NSUrlRequest的缓存由它自己内部根据策略去控制，用的是NSURLCache，不归AF处理，只需在configuration中设置上即可。
     */
    configuration.URLCache = [AFImageDownloader defaultURLCache];
    
    return configuration;
}

- (instancetype)init {
    NSURLSessionConfiguration *defaultConfiguration = [self.class defaultURLSessionConfiguration];
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:defaultConfiguration];
    sessionManager.responseSerializer = [AFImageResponseSerializer serializer];
    
    return [self initWithSessionManager:sessionManager
                 downloadPrioritization:AFImageDownloadPrioritizationFIFO
                 maximumActiveDownloads:4
                             imageCache:[[AFAutoPurgingImageCache alloc] init]];
    /* lzy注170706：
     * AF自己控制的图片缓存用AFAutoPurgingImageCache，而NSUrlRequest的缓存由它自己内部根据策略去控制，用的是NSURLCache，不归AF处理，只需在configuration中设置上即可。
     
     * 为什么不直接用NSURLCache来缓存图片数据，还要自定义一个AFAutoPurgingImageCache呢？原来是因为NSURLCache的诸多限制，例如只支持get请求等等。而且因为是系统维护的，我们自己的可控度不强，并且如果需要做一些自定义的缓存处理，无法实现。
     */
}

- (instancetype)initWithSessionManager:(AFHTTPSessionManager *)sessionManager
                downloadPrioritization:(AFImageDownloadPrioritization)downloadPrioritization
                maximumActiveDownloads:(NSInteger)maximumActiveDownloads
                            imageCache:(id <AFImageRequestCache>)imageCache {
    if (self = [super init]) {
        // 持有sessionManager
        self.sessionManager = sessionManager;
        // 下载任务顺序，默认FIFO
        self.downloadPrioritizaton = downloadPrioritization;
        // 最大活跃下载任务数
        self.maximumActiveDownloads = maximumActiveDownloads;
        // 持有自定义的图片缓存
        self.imageCache = imageCache;
        // 模拟队列或者栈的数组，存放『等待』下载任务
        self.queuedMergedTasks = [[NSMutableArray alloc] init];
        // 字典，建立下载任务dataTask管理者和请求url直接的映射
        self.mergedTasks = [[NSMutableDictionary alloc] init];
        self.activeRequestCount = 0;
        
        // 拼接name，创建串行queue
        NSString *name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.synchronizationqueue-%@", [[NSUUID UUID] UUIDString]];
        self.synchronizationQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);
        // 并行queue
        name = [NSString stringWithFormat:@"com.alamofire.imagedownloader.responsequeue-%@", [[NSUUID UUID] UUIDString]];
        self.responseQueue = dispatch_queue_create([name cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);
    }
    
    return self;
}

+ (instancetype)defaultInstance {
    static AFImageDownloader *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                        success:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, UIImage * _Nonnull))success
                                                        failure:(void (^)(NSURLRequest * _Nonnull, NSHTTPURLResponse * _Nullable, NSError * _Nonnull))failure {
    return [self downloadImageForURLRequest:request withReceiptID:[NSUUID UUID] success:success failure:failure];
}

- (nullable AFImageDownloadReceipt *)downloadImageForURLRequest:(NSURLRequest *)request
                                                  withReceiptID:(nonnull NSUUID *)receiptID
                                                        success:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse  * _Nullable response, UIImage *responseObject))success
                                                        failure:(nullable void (^)(NSURLRequest *request, NSHTTPURLResponse * _Nullable response, NSError *error))failure {
    // 同步、串行情况下，去做下载的事情，所以不用担心线程安全问题
    // 创建局部变量NSURLSessionDataTask类型
    __block NSURLSessionDataTask *task = nil;
    
    dispatch_sync(self.synchronizationQueue, ^{
        
        // url不存在，直接报error并return
        NSString *URLIdentifier = request.URL.absoluteString;
        if (URLIdentifier == nil) {
            if (failure) {
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(request, nil, error);
                });
            }
            return;
        }
        
        // 从字典中取下，是否有该请求地址对应的下载任务管理者
        // 1) Append the success and failure blocks to a pre-existing request if it already exists
        AFImageDownloaderMergedTask *existingMergedTask = self.mergedTasks[URLIdentifier];
        if (existingMergedTask != nil) {
            AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID success:success failure:failure];
            // 存在该请求的任务管理者，管理者多添加一个响应处理，在任务完成后，将回调所有需要通知的handler
            [existingMergedTask addResponseHandler:handler];
            task = existingMergedTask.task;
            return;
        }
        
        // 看下request的缓存策略是否允许从缓存中获取图片数据。
        // 2) Attempt to load the image from the image cache if the cache policy allows it
        switch (request.cachePolicy) {
            case NSURLRequestUseProtocolCachePolicy:
            case NSURLRequestReturnCacheDataElseLoad:
            case NSURLRequestReturnCacheDataDontLoad: {
                UIImage *cachedImage = [self.imageCache imageforRequest:request withAdditionalIdentifier:nil];
                if (cachedImage != nil) {
                    // 允许&&能取到缓存，回调该缓存，return
                    if (success) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success(request, nil, cachedImage);
                        });
                    }
                    return;
                }
                break;
            }
            default:
                break;
        }
        
        // 执行到此处，说明 没有对该url的request在请求中、也没有对应的缓存，则开启一个下载任务
        // 3) Create the request and set up authentication, validation and response serialization
        NSUUID *mergedTaskIdentifier = [NSUUID UUID];
        
        NSURLSessionDataTask *createdTask;
        
        __weak __typeof__(self) weakSelf = self;
        
        //用sessionManager的去请求，注意，只是创建task,还是挂起状态
        createdTask = [self.sessionManager
                       dataTaskWithRequest:request
                       uploadProgress:nil
                       downloadProgress:nil
                       completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
                           
                           /* lzy注170706：
                            注意，大括号内是回调block，执行顺序是靠后的，只有网络请求完成才会回调
                            */
                           // 在responseQueue中回调，这是一个并发队列
                           dispatch_async(self.responseQueue, ^{
                               __strong __typeof__(weakSelf) strongSelf = weakSelf;
                               // 不同与上1），从字典取出AFImageDownloaderMergedTask，是一定能取出的。因为执行此block之前，创建了任务管理者，并关联了url并存在字典中
                               AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
                               if ([mergedTask.identifier isEqual:mergedTaskIdentifier]) {
                                   // 找到任务，任务完成，从字典中移除这组映射
                                   mergedTask = [strongSelf safelyRemoveMergedTaskWithURLIdentifier:URLIdentifier];
                                   
                                   // 出现错误，任务管理者，通知自己持有的所有handler中的failureBlock
                                   if (error) {
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           if (handler.failureBlock) {
                                               // 在主线程回调
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.failureBlock(request, (NSHTTPURLResponse*)response, error);
                                               });
                                           }
                                       }
                                   } else {
                                       [strongSelf.imageCache addImage:responseObject forRequest:request withAdditionalIdentifier:nil];
                                       // 任务成功，任务管理者，通知自己持有的所有handler中的successBlock
                                       for (AFImageDownloaderResponseHandler *handler in mergedTask.responseHandlers) {
                                           if (handler.successBlock) {
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   handler.successBlock(request, (NSHTTPURLResponse*)response, responseObject);
                                               });
                                           }
                                       }
                                       
                                   }
                               }
                               [strongSelf safelyDecrementActiveTaskCount];
                               [strongSelf safelyStartNextTaskIfNecessary];
                           });
                       }];
        
        //创建该任务的『回调管理者』，回调管理者持有了 外部传入的『成功回调』、『失败回调』、任务标识收据id
        // 4) Store the response handler for use when the request completes
        AFImageDownloaderResponseHandler *handler = [[AFImageDownloaderResponseHandler alloc] initWithUUID:receiptID
                                                                                                   success:success
                                                                                                   failure:failure];
        // 创建这个task的管理者，并附件关联的url和任务uuid标识。并把上面创建的『回调管理者』加到任务管理者的回调数组中
        AFImageDownloaderMergedTask *mergedTask = [[AFImageDownloaderMergedTask alloc]
                                                   initWithURLIdentifier:URLIdentifier
                                                   identifier:mergedTaskIdentifier
                                                   task:createdTask];
        [mergedTask addResponseHandler:handler];
        // 把任务管理者和url关联起来，放到字典中
        self.mergedTasks[URLIdentifier] = mergedTask;
        
        // 已经达到最大并发数，就入队等待，未达到最大请求并发数，则立即开始任务
        // 5) Either start the request or enqueue it depending on the current active request count
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            [self startMergedTask:mergedTask];
        } else {
            // 执行中的任务是使用NSMutableDictionary *mergedTasks管理的。
            // 等待执行的任务，是调用下面的方法管理的。具体是NSMutableArray *queuedMergedTasks管理的。
            [self enqueueMergedTask:mergedTask];
        }
        
        task = mergedTask.task;
    });
    
    // task创建完成，创建并回调下载收据类，下载收据对象，持有唯一标识、task
    if (task) {
        return [[AFImageDownloadReceipt alloc] initWithReceiptID:receiptID task:task];
    } else {
        return nil;
    }
}

- (void)cancelTaskForImageDownloadReceipt:(AFImageDownloadReceipt *)imageDownloadReceipt {
    // 在同步、串行队列中执行
    dispatch_sync(self.synchronizationQueue, ^{
        // 拿出url标识
        NSString *URLIdentifier = imageDownloadReceipt.task.originalRequest.URL.absoluteString;
        // 根据标识，拿出任务管理者
        AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
        //indexOfObjectPassingTest是系统方法。拿到，要取消的下载任务对应的『回调管理者』，在『任务管理者』持有的『回调数组』中的索引
        NSUInteger index = [mergedTask.responseHandlers indexOfObjectPassingTest:^BOOL(AFImageDownloaderResponseHandler * _Nonnull handler, __unused NSUInteger idx, __unused BOOL * _Nonnull stop) {
            return handler.uuid == imageDownloadReceipt.receiptID;
        }];
        
        if (index != NSNotFound) {
            // 在『任务管理者』持有的『回调数组』中 删除该receipt对于的回调管理者，即把要取消的任务和任务回调关联关系取消了。请求结果无论如何，不会再回调了该receipt标识的那个请求的，其他请求不受影响，就算是请求同一个url的图片，只要是不同的receipt就OK。
            AFImageDownloaderResponseHandler *handler = mergedTask.responseHandlers[index];
            [mergedTask removeResponseHandler:handler];
            
            NSString *failureReason = [NSString stringWithFormat:@"ImageDownloader cancelled URL request: %@",imageDownloadReceipt.task.originalRequest.URL.absoluteString];
            NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey:failureReason};
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
            
            if (handler.failureBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler.failureBlock(imageDownloadReceipt.task.originalRequest, nil, error);
                });
            }
        }
        // 判断『任务管理者』的『回调数组』中元素为0，且task的状态是挂起，直接cancel这个task。并从全局字典中移除键值对。
        //其他情况举例如，state == running或Canceling或completed。结果不管如何，不会回调receipt标识的那个请求；
        // 『任务管理者』的『回调数组』只要不是0，说明有需要回调，这个task就不会被cancel。

        if (mergedTask.responseHandlers.count == 0 && mergedTask.task.state == NSURLSessionTaskStateSuspended) {
            [mergedTask.task cancel];
            [self removeMergedTaskWithURLIdentifier:URLIdentifier];
        }
    });
}

//在同步、串行的队列中执行的。防止移除中出现重复移除一系列问题。

- (AFImageDownloaderMergedTask*)safelyRemoveMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    __block AFImageDownloaderMergedTask *mergedTask = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        mergedTask = [self removeMergedTaskWithURLIdentifier:URLIdentifier];
    });
    return mergedTask;
}

//This method should only be called from safely within the synchronizationQueue
- (AFImageDownloaderMergedTask *)removeMergedTaskWithURLIdentifier:(NSString *)URLIdentifier {
    AFImageDownloaderMergedTask *mergedTask = self.mergedTasks[URLIdentifier];
    [self.mergedTasks removeObjectForKey:URLIdentifier];
    return mergedTask;
}

/* lzy注170706：
 下面两个方法，之所以说是safely。内部是在同步、串行的队列中执行的。
 */

- (void)safelyDecrementActiveTaskCount {
    dispatch_sync(self.synchronizationQueue, ^{
        if (self.activeRequestCount > 0) {
            self.activeRequestCount -= 1;
        }
    });
}

- (void)safelyStartNextTaskIfNecessary {
    dispatch_sync(self.synchronizationQueue, ^{
        if ([self isActiveRequestCountBelowMaximumLimit]) {
            while (self.queuedMergedTasks.count > 0) {
                // [self dequeueMergedTask];的作用，返回AFImageDownloaderMergedTask任务管理者，并从等待队列移除
                AFImageDownloaderMergedTask *mergedTask = [self dequeueMergedTask];
                
                if (mergedTask.task.state == NSURLSessionTaskStateSuspended) {
                    // 从等待数组中取出的任务管理者，所管理的task是处于挂起状态，那么开始它
                    [self startMergedTask:mergedTask];
                    break;
                }
            }
        }
    });
}

- (void)startMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    [mergedTask.task resume];
    ++self.activeRequestCount;
}

- (void)enqueueMergedTask:(AFImageDownloaderMergedTask *)mergedTask {
    switch (self.downloadPrioritizaton) {
        case AFImageDownloadPrioritizationFIFO:
            [self.queuedMergedTasks addObject:mergedTask];
            break;
        case AFImageDownloadPrioritizationLIFO:
            [self.queuedMergedTasks insertObject:mergedTask atIndex:0];
            break;
    }
}

- (AFImageDownloaderMergedTask *)dequeueMergedTask {
    AFImageDownloaderMergedTask *mergedTask = nil;
    mergedTask = [self.queuedMergedTasks firstObject];
    [self.queuedMergedTasks removeObject:mergedTask];
    return mergedTask;
}

- (BOOL)isActiveRequestCountBelowMaximumLimit {
    return self.activeRequestCount < self.maximumActiveDownloads;
}

@end

#endif
