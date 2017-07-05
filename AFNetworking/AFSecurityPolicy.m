// AFSecurityPolicy.m
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

/* lzy注170705：
 1. 客户端发起HTTPS请求　　这个没什么好说的，就是用户在浏览器里输入一个https网址，然后连接到server的443端口。
 2. 服务端的配置　　采用HTTPS协议的服务器必须要有一套数字证书，可以自己制作，也可以向组织申请。区别就是自己颁发的证书需要客户端验证通过，才可以继续访问，而使用受信任的公司申请的证书则不会弹出提示页面。这套证书其实就是一对公钥和私钥。如果对公钥和私钥不太理解，可以想象成一把钥匙和一个锁头，只是全世界只有你一个人有这把钥匙，你可以把锁头给别人，别人可以用这个锁把重要的东西锁起来，然后发给你，因为只有你一个人有这把钥匙，所以只有你才能看到被这把锁锁起来的东西。
 3. 传送证书　　这个证书其实就是公钥，只是包含了很多信息，如证书的颁发机构，过期时间等等。
 4. 客户端解析证书　　这部分工作是有客户端的TLS/SSL来完成的，首先会验证公钥是否有效，比如颁发机构，过期时间等等，如果发现异常，则会弹出一个警告框，提示证书存在问题。如果证书没有问题，那么就生成一个随机值。然后用证书对该随机值进行加密。就好像上面说的，把随机值用锁头锁起来，这样除非有钥匙，不然看不到被锁住的内容。
 5. 传送加密信息　　这部分传送的是用证书加密后的随机值，目的就是让服务端得到这个随机值，以后客户端和服务端的通信就可以通过这个随机值来进行加密解密了。
 6. 服务段解密信息　　服务端用私钥解密后，得到了客户端传过来的随机值(私钥)，然后把内容通过该值进行对称加密。所谓对称加密就是，将信息和私钥通过某种算法混合在一起，这样除非知道私钥，不然无法获取内容，而正好客户端和服务端都知道这个私钥，所以只要加密算法够彪悍，私钥够复杂，数据就够安全。
 7. 传输加密后的信息　　这部分信息是服务段用私钥加密后的信息，可以在客户端被还原。
 8. 客户端解密信息　　客户端用之前生成的私钥解密服务段传过来的信息，于是获取了解加密后的内容。整个过程第三方即使监听到了数据，也束手无策。
 
 这仅仅是一个单向认证，https还会有双向认证，相对于单向认证也很简单。仅仅多了服务端验证客户端这一步。感兴趣的可以看看这篇：Https单向认证和双向认证。http://blog.csdn.net/duanbokan/article/details/50847612
 
 1. 如果你用的是付费的公信机构颁发的证书，标准的https，那么无论你用的是AF还是NSUrlSession,什么都不用做。你的网络请求就能正常完成。

 2. 如果你用的是自签名的证书:
 * 首先你需要在plist文件中，设置可以返回不安全的请求（关闭该域名的ATS）。
 * 其次，如果是NSUrlSesion，那么需要在代理方法实现如下：
 
 - (void)URLSession:(NSURLSession *)sessiondidReceiveChallenge:(NSURLAuthenticationChallenge *)challengecompletionHandler:(void(^)(NSURLSessionAuthChallengeDisposition disposition,NSURLCredential *credential))completionHandler{};
 
 如果是AF，你则需要设置policy：
 //允许自签名证书，必须的
 policy.allowInvalidCertificates = YES;
 //是否验证域名的CN字段
 //不是必须的，但是如果写YES，则必须导入证书。
 policy.validatesDomainName = NO;
 
 可以尝试导入并设置证书：
 NSString *certFilePath = [[NSBundle mainBundle] pathForResource:@"AFUse_server.cer" ofType:nil];
 NSData *certData = [NSData dataWithContentsOfFile:certFilePath];
 NSSet *certSet = [NSSet setWithObjects:certData,certData, nil];
 policy.pinnedCertificates = certSet;
 
 */

#import "AFSecurityPolicy.h"

#import <AssertMacros.h>

#if !TARGET_OS_IOS && !TARGET_OS_WATCH && !TARGET_OS_TV
static NSData * AFSecKeyGetData(SecKeyRef key) {
    CFDataRef data = NULL;
    
    __Require_noErr_Quiet(SecItemExport(key, kSecFormatUnknown, kSecItemPemArmour, NULL, &data), _out);
    
    return (__bridge_transfer NSData *)data;
    
_out:
    if (data) {
        CFRelease(data);
    }
    
    return nil;
}
#endif
//判断两个公钥是否相同
static BOOL AFSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2) {
#if TARGET_OS_IOS || TARGET_OS_WATCH || TARGET_OS_TV
    //iOS 判断二者地址
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
#else
    return [AFSecKeyGetData(key1) isEqual:AFSecKeyGetData(key2)];
#endif
}

static id AFPublicKeyForCertificate(NSData *certificate) {
    // 1、初始化一些临时变量
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecPolicyRef policy = nil;
    // 每一个 SecTrustRef 的对象都是包含多个 SecCertificateRef 和 SecPolicyRef。其中 SecCertificateRef 可以使用DER 进行表示，并且其中存储着公钥信息。
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;
    // 2、SecCertificateCreateWithData方法返回一个SecCertificateRef
    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificate);
    // 3、判断 allowedCertificate != NULL 是否成立，如果 allowedCertificate 为空就会跳到 _out 标签处继续执行
    __Require_Quiet(allowedCertificate != NULL, _out);
    // 4、创建一个默认的符合 X509 标准的 SecPolicyRef，通过默认的 SecPolicyRef 和证书创建一个 SecTrustRef 用于信任评估
    policy = SecPolicyCreateBasicX509();
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);
    // 对该对象进行信任评估，确认生成的 SecTrustRef 是值得信任的
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
    // 获取公钥
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);
    
_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }
    
    if (policy) {
        CFRelease(policy);
    }
    
    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }
    
    return allowedPublicKey;
}

//判断serverTrust是否有效
static BOOL AFServerTrustIsValid(SecTrustRef serverTrust) {
    //默认无效
    
    BOOL isValid = NO;
    //用来装验证结果，枚举
    SecTrustResultType result;
    /* errorCode为0，执行完这个宏，代码继续执行下一行；errorCode不为0，代码直接goto到exceptionLabel标记处执行
     *  __Require_noErr_Quiet(errorCode, exceptionLabel)
     *
     *  Summary:
     *    If the errorCode expression does not equal 0 (noErr),
     *    goto exceptionLabel.
     
     #ifndef __Require_noErr_Quiet
     #define __Require_noErr_Quiet(errorCode, exceptionLabel)                      \
     do                                                                          \
     {                                                                           \
     if ( __builtin_expect(0 != (errorCode), 0) )                            \
     {                                                                       \
			  goto exceptionLabel;                                                \
     }                                                                       \
     } while ( 0 )
     #endif
     
     使用do while (0) 是C语言宏定义的最佳实践做法，可见王巍在《宏定义的黑魔法》一文https://onevcat.com/2014/01/black-magic-in-macro/
     */
    

    
    /*!
     @function SecTrustEvaluate
     @abstract Evaluates a trust reference synchronously.
     @param trust A reference to the trust object to evaluate.
     @param result A pointer to a result type.
     @result A result code. See "Security Error Codes" (SecBase.h).
     @discussion This function will completely evaluate trust before returning,
     possibly including network access to fetch intermediate certificates or to
     perform revocation checking. Since this function can block during those
     operations, you should call it from within a function that is placed on a
     dispatch queue, or in a separate thread from your application's main
     run loop. Alternatively, you can use the SecTrustEvaluateAsync function.
     把验证结果返回给第二参数 result
     */
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);
    
    //评估没出错走掉这，只有两种结果能设置为有效，isValid= 1
    
    //当result为kSecTrustResultUnspecified（此标志表示serverTrust评估成功，此证书也被暗中信任了，但是用户并没有显示地决定信任该证书）。
    
    //或者当result为kSecTrustResultProceed（此标志表示评估成功，和上面不同的是该评估得到了用户认可），这两者取其一就可以认为对serverTrust评估成功
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
    //out函数块,如果为SecTrustEvaluate，返回非0，则评估出错，则isValid为NO
    _out:
    return isValid;
}

/* lzy注170703：获取证书链
 * SecTrustGetCertificateAtIndex 获取 SecTrustRef 中的证书
 * SecCertificateCopyData 从证书中或者 DER 表示的数据
 */
static NSArray * AFCertificateTrustChainForServerTrust(SecTrustRef serverTrust) {
    //使用SecTrustGetCertificateCount函数获取到serverTrust中需要评估的证书链中的证书数目，并保存到certificateCount中
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    
    for (CFIndex i = 0; i < certificateCount; i++) {
        // 使用SecTrustGetCertificateAtIndex函数获取到证书链中的每个证书，并添加到trustChain中，最后返回trustChain
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(__bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }
    
    return [NSArray arrayWithArray:trustChain];
}
// 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
static NSArray * AFPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust) {
    
    //安全策略
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    
    // 接下来的一小段代码和上面AFCertificateTrustChainForServerTrust函数的作用基本一致，都是为了获取到serverTrust中证书链上的所有证书，并依次遍历，取出公钥。
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        
        SecCertificateRef someCertificates[] = {certificate};
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);
        
        // 根据给定的certificates和policy来生成一个trust对象
        
        //不成功跳到 _out。
        SecTrustRef trust;
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);
        
        
        // 使用SecTrustEvaluate来评估上面构建的trust
        
        //评估失败跳到 _out
        SecTrustResultType result;
        
        __Require_noErr_Quiet(SecTrustEvaluate(trust, &result), _out);
        
        // 如果该trust符合X.509证书格式，那么先使用SecTrustCopyPublicKey获取到trust的公钥，再将此公钥添加到trustChain中
        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];
        
    _out:// 释放资源
        if (trust) {
            CFRelease(trust);
        }
        
        if (certificates) {
            CFRelease(certificates);
        }
        
        continue;
    }
    CFRelease(policy);
    // 返回对应的一组公钥
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark -
/* lzy注170705：
 securityPolicy存在的作用就是，使得在系统底层自己去验证之前，AF可以先去验证服务端的证书。如果通不过，则直接越过系统的验证，取消https的网络请求。否则，继续去走系统根证书的验证。
 
 证书链由两个环节组成—信任锚（CA 证书）环节和已签名证书环节。自我签名的证书仅有一个环节的长度—信任锚环节就是已签名证书本身。
 简单来说，证书链就是就是根证书，和根据根证书签名派发得到的证书。
 */
@interface AFSecurityPolicy()
@property (readwrite, nonatomic, assign) AFSSLPinningMode SSLPinningMode;
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation AFSecurityPolicy

+ (NSSet *)certificatesInBundle:(NSBundle *)bundle {
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];
    
    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        [certificates addObject:certificateData];
    }
    
    return [NSSet setWithSet:certificates];
}

+ (NSSet *)defaultPinnedCertificates {
    static NSSet *_defaultPinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _defaultPinnedCertificates = [self certificatesInBundle:bundle];
    });
    
    return _defaultPinnedCertificates;
}

+ (instancetype)defaultPolicy {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = AFSSLPinningModeNone;
    
    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode {
    return [self policyWithPinningMode:pinningMode withPinnedCertificates:[self defaultPinnedCertificates]];
}

+ (instancetype)policyWithPinningMode:(AFSSLPinningMode)pinningMode withPinnedCertificates:(NSSet *)pinnedCertificates {
    AFSecurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = pinningMode;
    /* lzy注170703：
     在调用 pinnedCertificate 的 setter 方法时，会从全部的证书中取出公钥保存到 pinnedPublicKeys 属性中。
     */
    [securityPolicy setPinnedCertificates:pinnedCertificates];
    
    return securityPolicy;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.validatesDomainName = YES;
    
    return self;
}
// 把证书中每个公钥放在了self.pinnedPublicKeys中
- (void)setPinnedCertificates:(NSSet *)pinnedCertificates {
    _pinnedCertificates = pinnedCertificates;
    
    if (self.pinnedCertificates) {
        //创建公钥集合
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        //从证书中拿到公钥。
        for (NSData *certificate in self.pinnedCertificates) {
            /* lzy注170703：
             调用AFPublicKeyForCertificate函数，返回一个公钥。
             */
            id publicKey = AFPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark -
/* lzy注170705：
 AF内部的一个https认证
 */
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain
{
    // #1: 不能隐式地信任自己签发的证书
    // domain字符串存在、允许无效的证书(BOOL default NO)、验证证书的domianName(BOOl，default YES)、//因为要验证域名，所以必须不能是后者两种：AFSSLPinningModeNone或者添加到项目里的证书为0个。
    if (domain && self.allowInvalidCertificates && self.validatesDomainName && (self.SSLPinningMode == AFSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        // https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/OverridingSSLChainValidationCorrectly.html
        //  According to the docs, you should only trust your provided certs for evaluation.
        //  Pinned certificates are added to the trust. Without pinned certificates,
        //  there is nothing to evaluate against.
        //
        //  From Apple Docs:
        //          "Do not implicitly trust self-signed certificates as anchors (kSecTrustOptionImplicitAnchors).
        //           Instead, add your own (self-signed) CA certificate to the list of trusted anchors."
        NSLog(@"In order to validate a domain name for self signed certificates, you MUST use pinning.");
        return NO;
    }
    // #2: 设置 policy * 如果要验证域名的话，就以域名为参数创建一个 SecPolicyRef，否则会创建一个符合 X509 标准的默认 SecPolicyRef 对象
    NSMutableArray *policies = [NSMutableArray array];
    if (self.validatesDomainName) {// 如果需要验证domain，那么就使用SecPolicyCreateSSL函数创建验证策略，其中第一个参数为true表示验证整个SSL证书链，第二个参数传入domain，用于判断整个证书链上叶子节点表示的那个domain是否和此处传入domain一致
        
        //添加验证策略
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        // 如果不需要验证domain，就使用默认的BasicX509验证策略。不验证域名。
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    
    // 为serverTrust设置验证策略，即告诉客户端如何验证serverTrust
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    // #3: 验证证书的有效性
    
    if (self.SSLPinningMode == AFSSLPinningModeNone) {
        
        //如果支持自签名，直接返回YES,不允许才去判断第二个条件，判断serverTrust是否有效
        return self.allowInvalidCertificates || AFServerTrustIsValid(serverTrust);
    } else if (!AFServerTrustIsValid(serverTrust) && !self.allowInvalidCertificates) {
        
        //如果验证无效AFServerTrustIsValid，而且allowInvalidCertificates不允许自签，返回NO
        return NO;
    }
    
    switch (self.SSLPinningMode) {
            // 理论上，上面那个部分已经解决了self.SSLPinningMode为AFSSLPinningModeNone等情况，所以此处再遇到，就直接返回NO
        case AFSSLPinningModeNone:
        default:
            return NO;
        case AFSSLPinningModeCertificate: {
            /* lzy注170703：
             1. 从 self.pinnedCertificates 中获取 DER 表示的数据
             2. 使用 SecTrustSetAnchorCertificates 为服务器信任设置证书
             3. 判断服务器信任的有效性
             4. 使用 AFCertificateTrustChainForServerTrust 获取服务器信任中的全部 DER 表示的证书
             5. 如果 pinnedCertificates 中有相同的证书，就会返回 YES
             */
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            
            //把证书data，用系统api转成 SecCertificateRef 类型的数据,SecCertificateCreateWithData函数对原先的pinnedCertificates做一些处理，保证返回的证书都是DER编码的X.509证书
            
            for (NSData *certificateData in self.pinnedCertificates) {
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            // 将pinnedCertificates设置成需要参与验证的Anchor Certificate（锚点证书，通过SecTrustSetAnchorCertificates设置了参与校验锚点证书之后，假如验证的数字证书是这个锚点证书的子节点，即验证的数字证书是由锚点证书对应CA或子CA签发的，或是该证书本身，则信任该证书），具体就是调用SecTrustEvaluate来验证。
            // 如果以后再次去验证serverTrust，会从锚点证书去找是否匹配。
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            
            if (!AFServerTrustIsValid(serverTrust)) {
                return NO;
            }
            
            
            //注意，这个方法和我们之前的锚点证书没关系了，是去从我们需要被验证的服务端证书，去拿证书链。
            // 服务器端的证书链，注意此处返回的证书链顺序是从叶节点到根节点
            // obtain the chain after being validated, which *should* contain the pinned certificate in the last position (if it's the Root CA)
            NSArray *serverCertificates = AFCertificateTrustChainForServerTrust(serverTrust);
            
            //reverseObjectEnumerator逆序
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                //如果我们的证书中，有一个和它证书链中的证书匹配的，就返回YES
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
            
            return NO;
        }
        case AFSSLPinningModePublicKey: {//公钥验证 AFSSLPinningModePublicKey模式同样是用证书绑定(SSL Pinning)方式验证，客户端要有服务端的证书拷贝，只是验证时只验证证书里的公钥，不验证证书的有效期等信息。只要公钥是正确的，就能保证通信不会被窃听，因为中间人没有私钥，无法解开通过公钥加密的数据。
            /* lzy注170703：
             * 这部分的实现和上面的差不多，区别有两点
             1. 会从服务器信任中获取公钥
             2. pinnedPublicKeys 中的公钥与服务器信任中的公钥相同的数量大于 0，就会返回真
             */
            NSUInteger trustedPublicKeyCount = 0;
            // 从serverTrust中取出服务器端传过来的所有可用的证书，并依次得到相应的公钥
            NSArray *publicKeys = AFPublicKeyTrustChainForServerTrust(serverTrust);
            //遍历服务端公钥
            for (id trustChainPublicKey in publicKeys) {
                //遍历本地公钥
                for (id pinnedPublicKey in self.pinnedPublicKeys) {
                    //判断如果相同 trustedPublicKeyCount+1
                    if (AFSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}

#pragma mark - NSKeyValueObserving

+ (NSSet *)keyPathsForValuesAffectingPinnedPublicKeys {
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    
    self = [self init];
    if (!self) {
        return nil;
    }
    
    self.SSLPinningMode = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCertificates = [decoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    self.validatesDomainName = [decoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [decoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(pinnedCertificates))];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [coder encodeBool:self.allowInvalidCertificates forKey:NSStringFromSelector(@selector(allowInvalidCertificates))];
    [coder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [coder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFSecurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCertificates = self.allowInvalidCertificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];
    
    return securityPolicy;
}

@end
