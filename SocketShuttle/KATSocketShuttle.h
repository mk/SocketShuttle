//
//  KATSocketShuttle.h
//  BoldPoker
//
//  Created by Martin Kavalar on 22.11.11.
//  Copyright (c) 2011-2013 kater calling GmbH All rights reserved.
//

#import <SystemConfiguration/CaptiveNetwork.h>
#import <SocketRocket/SRWebSocket.h>

typedef enum {
    KATSocketStateOffline,       // no network, set via reachability callbacks
    KATSocketStateConnecting,
    KATSocketStateConnected,
    KATSocketStateDisconnected
} KATSocketState;


NSString *NSStringFromSocketState(KATSocketState state);

static  NSString    *const     KATGameServiceConnectionErrorNotification  =   @"KATGameServiceConnectionErrorNotification";

static  NSString    *const     KATGameServiceConnectionErrorReasonKey         =   @"KATGameServiceConnectionErrorReasonKey";
static  NSString    *const     KATGameServiceConnectionErrorReasonOffline     =   @"KATGameServiceConnectionErrorReasonOffline";
static  NSString    *const     KATGameServiceConnectionErrorReasonServerDown  =   @"KATGameServiceConnectionErrorReasonServerDown";
static  NSString    *const     KATGameServiceConnectionErrorReasonTimeout     =   @"KATGameServiceConnectionErrorReasonTimeout";
static  NSString    *const     KATGameServiceConnectionErrorReasonGeneric     =   @"KATGameServiceConnectionErrorReasonGeneric";

static  NSString    *const     KATGameServiceSocketErrorKey                   =   @"KATGameServiceSocketErrorKey";

@protocol KATSocketShuttleDelegate;


@interface KATSocketShuttle : NSObject

-(id)initWithServerURL:(NSURL *)serverURL delegate:(id<KATSocketShuttleDelegate>) delegate;

-(void)send:(NSString *)message;
-(void)disconnect;
-(void)ensureConnected;


@property (nonatomic, readonly) KATSocketState socketState;
@property (nonatomic, assign) id <KATSocketShuttleDelegate> delegate;
@property (nonatomic)   NSTimeInterval  timeoutInterval; // defaults to 30 seconds
@property (nonatomic, readonly) NSURL *serverURL;

@end


@protocol KATSocketShuttleDelegate <NSObject>

// message will either be an NSString if the server is using text
// or NSData if the server is using binary
- (void)socket:(KATSocketShuttle *)socket didReceiveMessage:(id)message;

@end