#ifndef VTS_SOURCE_CLIENT_H
#define VTS_SOURCE_CLIENT_H

#import <Foundation/Foundation.h>

@interface VTSClient : NSObject

@property(nonatomic, readonly) BOOL connected;
@property(nonatomic, readonly) BOOL authenticated;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) NSSet<NSString *> *defaultParameterNames;

- (instancetype)initWithHost:(NSString *)host
                               port:(uint16_t)port
            includeCustomParameters:(BOOL)includeCustomParameters
                includeARKitAliases:(BOOL)includeARKitAliases
    includeACVABlendshapeParameters:(BOOL)includeACVABlendshapeParameters;

- (void)start;
- (void)stop;
- (void)injectParameterValues:(NSArray<NSDictionary *> *)parameterValues
                    faceFound:(BOOL)faceFound;
- (NSString *)statusLine;
- (NSSet<NSString *> *)defaultParameterNamesSnapshot;

@end

#endif // VTS_SOURCE_CLIENT_H
