//
//  KATSocketShuttle.m
//  BoldPoker
//
//  Created by Martin Kavalar on 22.11.11.
//  Copyright (c) 2011 kater calling GmbH All rights reserved.
//

#import "KATSocketShuttle.h"
#import "Reachability.h"
#import <SocketRocket/SRWebSocket.h>

#ifdef DEBUG_SOCKET_SHUTTLE
#  define KATLogVerbose NSLog
#  define KATLogWarning NSLog
#  define KATLogError   NSLog
#  define KATLog        NSLog
#else
#  define KATLogVerbose(...)
#  define KATLogWarning(...)
#  define KATLogError(...)
#  define KATLog(...)
#endif

@interface KATSocketShuttle () <SRWebSocketDelegate> {
    SRWebSocket *_socket;
    Reachability *_reachability;
    BOOL _tryReconnectImmediatly;
    BOOL _observerWasAdded;
    id _waitForCardDealBlock;
    id _connectionTimeoutBlock;
}
@property (nonatomic, readwrite) KATSocketState socketState;
@end

@implementation KATSocketShuttle

-(id)initWithRequest:(NSURLRequest *)request delegate:(id<KATSocketShuttleDelegate>)delegate connectConditions:(KATSocketConnectCondition)connectConditions {
    if((self = [super init])) {
        _request = request;
        _delegate = delegate;
        _observerWasAdded = NO;
        _connectConditions = connectConditions;

        KATLogVerbose(@"SocketService#init");

        __weak KATSocketShuttle *weakSelf = self;
        _reachability = [Reachability reachabilityForInternetConnection];
        _reachability.unreachableBlock = ^(Reachability *reachability) {
            KATLogVerbose(@"Reachability: Network is unreachable");
            KATSocketShuttle *strongSelf = weakSelf;
            dispatch_sync(dispatch_get_main_queue(), ^{
                strongSelf.socketState = KATSocketStateOffline;
            });
        };
        
        _reachability.reachableBlock = ^(Reachability *reachability) {
            KATLogVerbose(@"Reachability: Network is reachable");
            KATSocketShuttle *strongSelf = weakSelf;
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (strongSelf.socketState == KATSocketStateOffline) {
                    strongSelf.socketState = KATSocketStateDisconnected;
                    [strongSelf reconnect];
                } else if ((strongSelf.socketState == KATSocketStateConnected || strongSelf.socketState == KATSocketStateConnecting) && ![strongSelf shouldAttemptConnectionBasedOnConnectConditions]) {
                    strongSelf.socketState = KATSocketStateDisconnected;
                    [strongSelf disconnect];
                }
            });
        };
        [_reachability startNotifier];
        _tryReconnectImmediatly = YES;
        _timeoutInterval = 30;

        self.socketState = KATSocketStateConnecting;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self connect];
        });
    }
    return self;
}

-(id)initWithRequest:(NSURLRequest *)request delegate:(id<KATSocketShuttleDelegate>)delegate {
    return [self initWithRequest:request delegate:delegate connectConditions:KATSocketConnectConditionAlways];
}

-(id)initWithServerURL:(NSURL *)serverURL delegate:(id<KATSocketShuttleDelegate>)delegate {
    return [self initWithRequest:[NSURLRequest requestWithURL:serverURL] delegate:delegate];
}

- (void)dealloc {
    if(_observerWasAdded) {
        [self removeObserver:self forKeyPath:@"self.socketState"];
    }
    [self cancelConnectingTimer];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - KATGameService

- (void)ensureConnected {
    KATLogVerbose(@"ensureConnected, _socket.readyState = %d", _socket.readyState);
    switch (_socket.readyState) {
        case SR_CLOSING:
        case SR_CLOSED:
            [self connect];
            break;
        default:
            break;
    }
}

- (void)connect {
    KATLogVerbose(@"connect");
    if(![_reachability isReachable] || ![self shouldAttemptConnectionBasedOnConnectConditions]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:KATGameServiceConnectionErrorNotification
                                                            object:self
                                                          userInfo:@{KATGameServiceConnectionErrorReasonKey: KATGameServiceConnectionErrorReasonOffline}];
        self.socketState = KATSocketStateOffline;
        return;
    }
    self.socketState = KATSocketStateConnecting;
    [self disconnect:NO];
    KATLogVerbose(@"SocketService#connect serverURL = %@", self.request);
    [self startConnectingTimer];
    _socket = [[SRWebSocket alloc] initWithURLRequest:self.request];
    if(!_observerWasAdded) {
        [self addObserver:self forKeyPath:@"self.socketState" options:0 context:NULL];
        _observerWasAdded = YES;
    }
    _socket.delegate = self;
    [_socket open];
}

- (void)disconnect {
    [self disconnect:YES];
}

- (void)disconnect:(BOOL)updateState {
    KATLogVerbose(@"SocketService#disconnect");
    if(_socket) {
        _socket.delegate = nil;
        [_socket close];
    }
    if(updateState) {
        self.socketState = KATSocketStateDisconnected;
    }
}

- (void)reconnect {
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        [self connect];
    });
}

- (void)startConnectingTimer {
    // this will be cancelled once the connection succeeds
    [self cancelConnectingTimer];
	[self performSelector:@selector(postConnectionTimeoutNotification) withObject:nil afterDelay:_timeoutInterval];
}

- (void)postConnectionTimeoutNotification {
	[self disconnect:YES];
	[[NSNotificationCenter defaultCenter] postNotificationName:KATGameServiceConnectionErrorNotification
														object:self
													  userInfo:@{KATGameServiceConnectionErrorReasonKey: KATGameServiceConnectionErrorReasonTimeout}];
}

- (void)cancelConnectingTimer {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(postConnectionTimeoutNotification) object:nil];
}


- (NSError *)socketErrorWithCode:(NSUInteger)code reason:(NSString *)reason {
    return [NSError errorWithDomain:[[NSBundle mainBundle] infoDictionary][(NSString *)kCFBundleIdentifierKey]
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey:reason}];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Internal

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if([keyPath isEqualToString:@"self.socketState"]) {
		[self cancelConnectingTimer];
	}
}


NSString *NSStringFromSocketState(KATSocketState state) {
    switch (state) {
        case KATSocketStateOffline:
            return @"No Internet Connection";
        case KATSocketStateDisconnected:
            return @"Disconnected";
        case KATSocketStateConnecting:
            return @"Connecting…";
        case KATSocketStateConnected:
            return @"Connected";
        default:
            return @"(Invalid Socket State)";
    }
}

- (void)send:(NSString*)message {
    if (_socketState != KATSocketStateConnected) {
        KATLogWarning(@"SocketService is not sending message '%@' because it's in state: %d", message, _socketState);
        return;
    }
	[_socket send:message];
}

- (BOOL)shouldAttemptConnectionBasedOnConnectConditions {
    return _connectConditions == KATSocketConnectConditionAlways ? YES : [_reachability isReachableViaWiFi];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - SRWebSocketDelegate



- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    _tryReconnectImmediatly = YES;
    KATLogVerbose(@"socket opened: %@", webSocket);
    self.socketState = KATSocketStateConnected;

    if (self.delegate && [self.delegate respondsToSelector:@selector(socketDidOpen:)])
        [self.delegate socketDidOpen:self];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id) message {
    KATLogVerbose(@"=> %@", message);

	if(self.delegate && [self.delegate respondsToSelector:@selector(socket:didReceiveMessage:)])
		[self.delegate socket:self didReceiveMessage:message];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    KATLogWarning(@"webSocket:%@ didFailWithError:%@", webSocket, error);
    if(error.code == 57) { // socket closed, mostly when in background, try reconncet
        [self ensureConnected];
    } else if(error.code == 61) { // connection refused, looks like the server is down
        [[NSNotificationCenter defaultCenter] postNotificationName:KATGameServiceConnectionErrorNotification
                                                            object:self
                                                          userInfo:@{KATGameServiceConnectionErrorReasonKey: KATGameServiceConnectionErrorReasonServerDown, KATGameServiceSocketErrorKey: error}];
        self.socketState = KATSocketStateDisconnected;
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:KATGameServiceConnectionErrorNotification
                                                            object:self
                                                          userInfo:@{KATGameServiceConnectionErrorReasonKey: KATGameServiceConnectionErrorReasonGeneric, KATGameServiceSocketErrorKey: error}];
        self.socketState = KATSocketStateDisconnected;
    }

    if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didFailWithError:)])
        [self.delegate socket:self didFailWithError:error];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    KATLog(@"webSocket:%@ didCloseWithCode:%d reason:%@ wasClean:%d", webSocket, code, reason, wasClean);

    [self ensureConnected];

    if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didCloseWithCode:reason:wasClean:)])
        [self.delegate socket:self didCloseWithCode:code reason:reason wasClean:wasClean];
}

#pragma  mark - Getters

- (NSURL *)serverURL {
    return self.request.URL;
}

#pragma mark - Setters

- (void)setSocketState:(KATSocketState)socketState {
    if (socketState == _socketState) {
        return;
    }

    _socketState = socketState;
}

- (void)setRequest:(NSURLRequest *)request {
    if (request == self.request) {
        return;
    }

    _request = request;

    if (self.socketState == KATSocketStateConnected || self.socketState == KATSocketStateConnecting) {
        [_socket close];
    }

    _socket = nil;
    _socket = [[SRWebSocket alloc] initWithURLRequest:request];
    _socket.delegate = self;
    [self ensureConnected];
}

@end
