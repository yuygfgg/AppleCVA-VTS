#import "client.h"

#import "parameters.h"

static NSString *const kVTSAPIName = @"VTubeStudioPublicAPI";
static NSString *const kVTSAPIVersion = @"1.0";
static NSString *const kVTSPluginName = @"AppleCVA Tracker";
static NSString *const kVTSPluginDeveloper = @"YUYGFGG";

typedef void (^VTSResponseHandler)(NSDictionary *response, NSError *error);
typedef void (^VTSErrorHandler)(NSError *error);

static BOOL parameterValueHasACVAPrefix(NSDictionary *parameter) {
    if (![parameter isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSString *parameterID = parameter[@"id"];
    return [parameterID isKindOfClass:NSString.class] &&
           [parameterID hasPrefix:@"ACVA"];
}

static BOOL parameterValueIDHasPrefix(NSDictionary *parameter,
                                      NSString *prefix) {
    if (![parameter isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSString *parameterID = parameter[@"id"];
    return [parameterID isKindOfClass:NSString.class] &&
           [parameterID hasPrefix:prefix];
}

static BOOL parameterValueIsSmileOutput(NSDictionary *parameter) {
    if (![parameter isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSString *parameterID = parameter[@"id"];
    return [parameterID isKindOfClass:NSString.class] &&
           ([parameterID isEqualToString:@"EyeSmileLeft"] ||
            [parameterID isEqualToString:@"EyeSmileRight"] ||
            [parameterID isEqualToString:@"BlushWhenSmiling"]);
}

@interface VTSClient ()
@property(nonatomic, readwrite) BOOL connected;
@property(nonatomic, readwrite) BOOL authenticated;
@property(nonatomic, readwrite) BOOL ready;
@property(nonatomic, readwrite) NSSet<NSString *> *defaultParameterNames;
@end

@implementation VTSClient {
    NSString *_host;
    uint16_t _port;
    BOOL _includeCustomParameters;
    BOOL _includeARKitAliases;
    BOOL _includeACVABlendshapeParameters;
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_task;
    dispatch_queue_t _queue;
    NSMutableDictionary<NSString *, VTSResponseHandler> *_pending;
    NSArray<NSDictionary *> *_customParameterDefinitions;
    NSUInteger _nextRequestID;
    NSString *_lastStatus;
    NSString *_authenticationToken;
    BOOL _injectInFlight;
    BOOL _shouldRun;
    BOOL _reconnectScheduled;
}

- (instancetype)initWithHost:(NSString *)host
                               port:(uint16_t)port
            includeCustomParameters:(BOOL)includeCustomParameters
                includeARKitAliases:(BOOL)includeARKitAliases
    includeACVABlendshapeParameters:(BOOL)includeACVABlendshapeParameters {
    self = [super init];
    if (self != nil) {
        _host = [host copy] ?: @"127.0.0.1";
        _port = port;
        _includeCustomParameters = includeCustomParameters;
        _includeARKitAliases = includeARKitAliases;
        _includeACVABlendshapeParameters = includeACVABlendshapeParameters;
        _queue = dispatch_queue_create("local.applecva.vts-client",
                                       DISPATCH_QUEUE_SERIAL);
        _pending = [NSMutableDictionary dictionary];
        _defaultParameterNames = [NSSet set];
        _lastStatus = @"vts disconnected";
    }
    return self;
}

- (void)start {
    dispatch_async(_queue, ^{
      [self startLocked];
    });
}

- (void)stop {
    dispatch_async(_queue, ^{
      [self stopLocked];
    });
}

- (void)injectParameterValues:(NSArray<NSDictionary *> *)parameterValues
                    faceFound:(BOOL)faceFound {
    if (parameterValues.count == 0) {
        return;
    }
    dispatch_async(_queue, ^{
      if (!self.ready || self->_task == nil || self->_injectInFlight) {
          return;
      }
      NSMutableArray<NSDictionary *> *coreValues = [NSMutableArray array];
      NSMutableArray<NSDictionary *> *mouthValues = [NSMutableArray array];
      NSMutableArray<NSDictionary *> *customValues = [NSMutableArray array];
      for (NSDictionary *parameter in parameterValues) {
          if (parameterValueHasACVAPrefix(parameter)) {
              [customValues addObject:parameter];
          } else if (parameterValueIDHasPrefix(parameter, @"Mouth") ||
                     parameterValueIsSmileOutput(parameter)) {
              [mouthValues addObject:parameter];
          } else {
              [coreValues addObject:parameter];
          }
      }
      NSMutableArray<NSArray<NSDictionary *> *> *groups =
          [NSMutableArray array];
      if (coreValues.count != 0) {
          [groups addObject:coreValues];
      }
      if (mouthValues.count != 0) {
          [groups addObject:mouthValues];
      }
      if (customValues.count != 0) {
          [groups addObject:customValues];
      }
      if (groups.count == 0) {
          return;
      }
      self->_injectInFlight = YES;
      __block NSUInteger completedGroupCount = 0;
      __block NSError *firstError = nil;
      const NSUInteger groupCount = groups.count;
      for (NSArray<NSDictionary *> *group in groups) {
          [self
              sendInjectParameterValuesLocked:group
                                    faceFound:faceFound
                                   completion:^(NSError *error) {
                                     ++completedGroupCount;
                                     if (firstError == nil && error != nil) {
                                         firstError = error;
                                     }
                                     if (completedGroupCount != groupCount) {
                                         return;
                                     }
                                     self->_injectInFlight = NO;
                                     if (firstError != nil) {
                                         [self
                                             setStatusLocked:
                                                 [NSString
                                                     stringWithFormat:
                                                         @"vts inject "
                                                          "failed: %@",
                                                         firstError
                                                             .localizedDescription]];
                                     }
                                   }];
      }
    });
}

- (void)sendInjectParameterValuesLocked:(NSArray<NSDictionary *> *)values
                              faceFound:(BOOL)faceFound
                             completion:(VTSErrorHandler)completion {
    NSDictionary *data = @{
        @"faceFound" : @(faceFound),
        @"mode" : @"set",
        @"parameterValues" : values,
    };
    [self sendRequestWithType:@"InjectParameterDataRequest"
                         data:data
                   completion:^(NSDictionary *response, NSError *error) {
                     (void)response;
                     if (completion != nil) {
                         completion(error);
                     }
                   }];
}

- (NSString *)statusLine {
    __block NSString *status = nil;
    dispatch_sync(_queue, ^{
      status = [self->_lastStatus copy];
    });
    return status ?: @"vts disconnected";
}

- (NSSet<NSString *> *)defaultParameterNamesSnapshot {
    __block NSSet<NSString *> *names = nil;
    dispatch_sync(_queue, ^{
      names = [self.defaultParameterNames copy];
    });
    return names ?: [NSSet set];
}

- (void)startLocked {
    _shouldRun = YES;
    if (_task != nil) {
        return;
    }

    NSString *urlString =
        [NSString stringWithFormat:@"ws://%@:%u", _host, _port];
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        [self setStatusLocked:@"vts invalid websocket URL"];
        return;
    }

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    _session = [NSURLSession sessionWithConfiguration:configuration];
    _task = [_session webSocketTaskWithURL:url];
    [_task resume];
    self.connected = YES;
    [self setStatusLocked:[NSString stringWithFormat:@"vts connecting %@:%u",
                                                     _host, _port]];
    [self receiveNextLocked];
    [self authenticateLocked];
}

- (void)stopLocked {
    _shouldRun = NO;
    _reconnectScheduled = NO;
    self.ready = NO;
    self.authenticated = NO;
    self.connected = NO;
    [_pending removeAllObjects];
    _customParameterDefinitions = nil;
    [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure
                        reason:nil];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
    _injectInFlight = NO;
    [self setStatusLocked:@"vts disconnected"];
}

- (void)authenticateLocked {
    _authenticationToken = [self loadTokenLocked];
    if (_authenticationToken.length != 0) {
        [self sendAuthenticationRequestLockedWithToken:_authenticationToken];
        return;
    }
    [self requestAuthenticationTokenLocked];
}

- (void)requestAuthenticationTokenLocked {
    [self setStatusLocked:@"vts waiting for API token approval"];
    NSDictionary *data = @{
        @"pluginName" : kVTSPluginName,
        @"pluginDeveloper" : kVTSPluginDeveloper,
    };
    [self
        sendRequestWithType:@"AuthenticationTokenRequest"
                       data:data
                 completion:^(NSDictionary *response, NSError *error) {
                   if (error != nil) {
                       [self
                           setStatusLocked:[NSString
                                               stringWithFormat:
                                                   @"vts token denied: %@",
                                                   error.localizedDescription]];
                       return;
                   }
                   NSString *token = response[@"data"][@"authenticationToken"];
                   if (![token isKindOfClass:NSString.class] ||
                       token.length == 0) {
                       [self
                           setStatusLocked:@"vts token response missing token"];
                       return;
                   }
                   self->_authenticationToken = token;
                   [self saveTokenLocked:token];
                   [self sendAuthenticationRequestLockedWithToken:token];
                 }];
}

- (void)sendAuthenticationRequestLockedWithToken:(NSString *)token {
    [self setStatusLocked:@"vts authenticating"];
    NSDictionary *data = @{
        @"pluginName" : kVTSPluginName,
        @"pluginDeveloper" : kVTSPluginDeveloper,
        @"authenticationToken" : token,
    };
    [self
        sendRequestWithType:@"AuthenticationRequest"
                       data:data
                 completion:^(NSDictionary *response, NSError *error) {
                   if (error != nil) {
                       [self deleteTokenLocked];
                       self->_authenticationToken = nil;
                       [self
                           setStatusLocked:[NSString
                                               stringWithFormat:
                                                   @"vts auth failed: %@",
                                                   error.localizedDescription]];
                       [self requestAuthenticationTokenLocked];
                       return;
                   }
                   NSNumber *authenticated =
                       response[@"data"][@"authenticated"];
                   if (![authenticated boolValue]) {
                       [self deleteTokenLocked];
                       self->_authenticationToken = nil;
                       [self requestAuthenticationTokenLocked];
                       return;
                   }
                   self.authenticated = YES;
                   [self setStatusLocked:@"vts authenticated"];
                   [self refreshParametersLocked];
                 }];
}

- (void)refreshParametersLocked {
    [self
        sendRequestWithType:@"InputParameterListRequest"
                       data:@{}
                 completion:^(NSDictionary *response, NSError *error) {
                   if (error != nil) {
                       [self setStatusLocked:
                                 [NSString stringWithFormat:
                                               @"vts parameter list failed: %@",
                                               error.localizedDescription]];
                       return;
                   }
                   [self updateDefaultParametersFromResponseLocked:response];
                   [self deleteDeprecatedCustomParametersLockedWithCompletion:^{
                     if (!self->_includeCustomParameters) {
                         self.ready = YES;
                         [self
                             setStatusLocked:
                                 [NSString
                                     stringWithFormat:@"vts ready defaults=%lu",
                                                      (unsigned long)self
                                                          .defaultParameterNames
                                                          .count]];
                         return;
                     }
                     self->_customParameterDefinitions =
                         VTSAppleCVACustomParameterDefinitions(
                             self->_includeARKitAliases,
                             self->_includeACVABlendshapeParameters,
                             self.defaultParameterNames);
                     [self createCustomParametersLockedAtIndex:0];
                   }];
                 }];
}

- (void)updateDefaultParametersFromResponseLocked:(NSDictionary *)response {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSArray *defaultParameters = response[@"data"][@"defaultParameters"];
    if ([defaultParameters isKindOfClass:NSArray.class]) {
        for (NSDictionary *parameter in defaultParameters) {
            if (![parameter isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSString *name = parameter[@"name"];
            if (![name isKindOfClass:NSString.class]) {
                name = parameter[@"parameterName"];
            }
            if ([name isKindOfClass:NSString.class] && name.length != 0) {
                [names addObject:name];
            }
        }
    }
    self.defaultParameterNames = names;
    NSArray<NSString *> *sortedNames =
        [names.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSLog(@"vts default parameters: %@",
          [sortedNames componentsJoinedByString:@", "]);
}

- (void)deleteDeprecatedCustomParametersLockedWithCompletion:
    (dispatch_block_t)completion {
    NSDictionary *data = @{@"parameterName" : @"ACVAMouthOpen"};
    [self sendRequestWithType:@"ParameterDeletionRequest"
                         data:data
                   completion:^(NSDictionary *response, NSError *error) {
                     (void)response;
                     if (error != nil) {
                         NSLog(@"vts deprecated param deletion skipped: %@",
                               error.localizedDescription);
                     }
                     if (completion != nil) {
                         completion();
                     }
                   }];
}

- (void)createCustomParametersLockedAtIndex:(NSUInteger)index {
    NSArray<NSDictionary *> *definitions = _customParameterDefinitions;
    if (index >= definitions.count) {
        self.ready = YES;
        [self
            setStatusLocked:
                [NSString stringWithFormat:@"vts ready defaults=%lu custom=%lu",
                                           (unsigned long)
                                               self.defaultParameterNames.count,
                                           (unsigned long)definitions.count]];
        return;
    }

    [self
        sendRequestWithType:@"ParameterCreationRequest"
                       data:definitions[index]
                 completion:^(NSDictionary *response, NSError *error) {
                   (void)response;
                   if (error != nil) {
                       [self setStatusLocked:
                                 [NSString stringWithFormat:
                                               @"vts custom param skipped: %@",
                                               error.localizedDescription]];
                   }
                   [self createCustomParametersLockedAtIndex:index + 1];
                 }];
}

- (void)sendRequestWithType:(NSString *)messageType
                       data:(NSDictionary *)data
                 completion:(VTSResponseHandler)completion {
    if (_task == nil) {
        if (completion != nil) {
            completion(nil,
                       [self errorWithDescription:@"websocket not connected"]);
        }
        return;
    }

    NSString *requestID = [NSString
        stringWithFormat:@"applecva-%lu", (unsigned long)(++_nextRequestID)];
    NSMutableDictionary *request = [@{
        @"apiName" : kVTSAPIName,
        @"apiVersion" : kVTSAPIVersion,
        @"requestID" : requestID,
        @"messageType" : messageType,
    } mutableCopy];
    if (data != nil) {
        request[@"data"] = data;
    }

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:request
                                                       options:0
                                                         error:&jsonError];
    if (jsonData == nil) {
        if (completion != nil) {
            completion(nil, jsonError);
        }
        return;
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData
                                                 encoding:NSUTF8StringEncoding];
    if (completion != nil) {
        _pending[requestID] = [completion copy];
    }

    NSURLSessionWebSocketMessage *message =
        [[NSURLSessionWebSocketMessage alloc] initWithString:jsonString];
    [_task sendMessage:message
        completionHandler:^(NSError *error) {
          if (error == nil) {
              return;
          }
          dispatch_async(self->_queue, ^{
            VTSResponseHandler handler = self->_pending[requestID];
            if (handler != nil) {
                [self->_pending removeObjectForKey:requestID];
                handler(nil, error);
            }
            [self handleConnectionErrorLocked:error];
          });
        }];
}

- (void)receiveNextLocked {
    [_task receiveMessageWithCompletionHandler:^(
               NSURLSessionWebSocketMessage *message, NSError *error) {
      dispatch_async(self->_queue, ^{
        if (error != nil) {
            [self handleConnectionErrorLocked:error];
            return;
        }
        [self handleMessageLocked:message];
        if (self->_task != nil) {
            [self receiveNextLocked];
        }
      });
    }];
}

- (void)handleMessageLocked:(NSURLSessionWebSocketMessage *)message {
    NSData *data = nil;
    if (message.type == NSURLSessionWebSocketMessageTypeString) {
        data = [message.string dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        data = message.data;
    }
    if (data.length == 0) {
        return;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:&jsonError];
    if (![object isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSDictionary *response = (NSDictionary *)object;
    NSString *requestID = response[@"requestID"];
    VTSResponseHandler handler = nil;
    if ([requestID isKindOfClass:NSString.class]) {
        handler = _pending[requestID];
        if (handler != nil) {
            [_pending removeObjectForKey:requestID];
        }
    }

    NSString *messageType = response[@"messageType"];
    if ([messageType isEqualToString:@"APIError"]) {
        NSDictionary *errorData = response[@"data"];
        NSString *messageText =
            [errorData[@"message"] isKindOfClass:NSString.class]
                ? errorData[@"message"]
                : @"VTS API error";
        NSError *error = [self errorWithDescription:messageText];
        if (handler != nil) {
            handler(response, error);
        }
        return;
    }

    if (handler != nil) {
        handler(response, nil);
    }
}

- (void)handleConnectionErrorLocked:(NSError *)error {
    [self
        setStatusLocked:[NSString stringWithFormat:@"vts disconnected: %@",
                                                   error.localizedDescription]];
    self.connected = NO;
    self.authenticated = NO;
    self.ready = NO;
    _injectInFlight = NO;
    [_pending removeAllObjects];
    [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeAbnormalClosure
                        reason:nil];
    _task = nil;
    [_session invalidateAndCancel];
    _session = nil;
    [self scheduleReconnectLocked];
}

- (void)scheduleReconnectLocked {
    if (!_shouldRun || _reconnectScheduled) {
        return;
    }
    _reconnectScheduled = YES;
    [self setStatusLocked:@"vts reconnecting"];
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), _queue,
        ^{
          self->_reconnectScheduled = NO;
          if (!self->_shouldRun || self->_task != nil) {
              return;
          }
          [self startLocked];
        });
}

- (NSError *)errorWithDescription:(NSString *)description {
    return [NSError
        errorWithDomain:@"local.applecva.vts"
                   code:1
               userInfo:@{
                   NSLocalizedDescriptionKey : description ?: @"VTS API error",
               }];
}

- (void)setStatusLocked:(NSString *)status {
    _lastStatus = [status copy] ?: @"vts status unavailable";
    NSLog(@"%@", _lastStatus);
}

- (NSString *)tokenFilePathLocked {
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask];
    NSURL *base = urls.firstObject;
    if (base == nil) {
        return nil;
    }
    NSURL *directory = [base URLByAppendingPathComponent:@"AppleCVA"
                                             isDirectory:YES];
    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&error];
    if (error != nil) {
        NSLog(@"Failed to create token directory: %@",
              error.localizedDescription);
        return nil;
    }
    return [directory URLByAppendingPathComponent:@"vts-token.json"].path;
}

- (NSString *)loadTokenLocked {
    NSString *path = [self tokenFilePathLocked];
    if (path.length == 0) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:nil];
    NSString *token = json[@"authenticationToken"];
    return [token isKindOfClass:NSString.class] ? token : nil;
}

- (void)saveTokenLocked:(NSString *)token {
    NSString *path = [self tokenFilePathLocked];
    if (path.length == 0 || token.length == 0) {
        return;
    }
    NSDictionary *json = @{@"authenticationToken" : token};
    NSData *data =
        [NSJSONSerialization dataWithJSONObject:json
                                        options:NSJSONWritingPrettyPrinted
                                          error:nil];
    [data writeToFile:path atomically:YES];
}

- (void)deleteTokenLocked {
    NSString *path = [self tokenFilePathLocked];
    if (path.length != 0) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

@end
