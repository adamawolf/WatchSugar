//
//  AppDelegate.m
//  WatchSugar
//
//  Created by Adam A. Wolf on 12/14/15.
//  Copyright © 2015 Flairify. All rights reserved.
//

#import "AppDelegate.h"

#import <AFNetworking/AFNetworking.h>

#import <MagicalRecord/MagicalRecord.h>
#import "Reading+CoreDataProperties.h"

#import <WatchConnectivity/WatchConnectivity.h>

NSString *const WSNotificationDexcomDataChanged = @"WSNotificationDexcomDataChanged";
static const NSTimeInterval kBackgroundFetchInterval = 9 * 60.0f;

static const NSTimeInterval kRefreshInterval = 120.0f; //seconds

@interface AppDelegate () <WCSessionDelegate> {
    void (^_backgroundFetchCompletionHandler)(UIBackgroundFetchResult);
}

@property (nonatomic, strong) NSTimer *fetchTimer;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    //initialize CocoaLumberjack
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    //initialize CoreData
    [MagicalRecord setupCoreDataStackWithAutoMigratingSqliteStoreNamed:@"WatchSugar"];
    
    DDLogDebug(@"%@", [MagicalRecord currentStack]);
    
    //initialize WatchConnectivity
    if ([WCSession isSupported]) {
        WCSession *session = [WCSession defaultSession];
        session.delegate = self;
        [session activateSession];
        
        DDLogDebug(@"activate session called on device");
    }
    
    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:kBackgroundFetchInterval];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    if (self.fetchTimer) {
        [self.fetchTimer invalidate];
        self.fetchTimer = nil;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if (!self.dexcomToken) {
        [self authenticateWithDexcom];
    }
    
    if (self.fetchTimer) {
        [self.fetchTimer invalidate];
        self.fetchTimer = nil;
    }
    self.fetchTimer = [NSTimer scheduledTimerWithTimeInterval:kRefreshInterval target:self selector:@selector(fetchTimerFired:) userInfo:nil repeats:YES];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:WSNotificationDexcomDataChanged object:nil userInfo:nil];
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    DDLogDebug(@"starting background fetch");
    if (_backgroundFetchCompletionHandler) {
        DDLogDebug(@"fetch handler: UIBackgroundFetchResultNoData");
        completionHandler(UIBackgroundFetchResultNoData);
        DDLogDebug(@"completing (errorneous) background fetch");
        return;
    }
    
    if (self.dexcomToken) {
        if (self.subscriptionId) {
            [self fetchLatestBloodSugar];
        }
    }
    
    _backgroundFetchCompletionHandler = [completionHandler copy];
    
    DDLogDebug(@"completing background fetch");
}

#pragma mark - Helper methods

- (void)fetchTimerFired:(NSTimer *)timer
{
    if (!self.dexcomToken) {
        [self authenticateWithDexcom];
    } else {
        if (!self.subscriptionId) {
            [self fetchSubscriptions];
        } else {
            [self fetchLatestBloodSugar];
        }
    }
}

+ (void)dexcomPOSTToURLString:(NSString *)URLString
               withParameters:(id)parameters
             withSuccessBlock:(void (^)(NSURLSessionDataTask *, id))success
             withFailureBlock:(void (^)(NSURLSessionDataTask *, NSError *))failure
{
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    
    AFJSONRequestSerializer *requestSerializer = [AFJSONRequestSerializer serializer];
    [requestSerializer setValue:@"Dexcom Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0" forHTTPHeaderField:@"User-Agent"];
    [manager setRequestSerializer:requestSerializer];
    
    AFJSONResponseSerializer *responseSerializer = [AFJSONResponseSerializer serializerWithReadingOptions:NSJSONReadingAllowFragments];
    [manager setResponseSerializer:responseSerializer];
    
    [manager POST:URLString parameters:parameters progress:NULL success:success failure:failure];
}

- (void)authenticateWithDexcom
{
    NSString *URLString = @"https://share1.dexcom.com/ShareWebServices/Services/General/LoginSubscriberAccount";
    NSDictionary *parameters = @{@"accountId": @"***REMOVED***",
                                 @"password": @"A***REMOVED***",
                                 @"applicationId": @"d89443d2-327c-4a6f-89e5-496bbb0317db"};
    
    [AppDelegate dexcomPOSTToURLString:URLString
                        withParameters:parameters
                      withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                          DDLogDebug(@"received dexcom token: %@", responseObject);
                          self.dexcomToken = responseObject;
                          
                          [[NSNotificationCenter defaultCenter] postNotificationName:WSNotificationDexcomDataChanged object:nil userInfo:nil];
                          
                          if (!self.subscriptionId) {
                              [self fetchSubscriptions];
                          }
                      }
                      withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                          DDLogDebug(@"error: %@", error);
                      }];
}

- (void)fetchSubscriptions
{
    NSString *URLString = [NSString stringWithFormat:@"https://share1.dexcom.com/ShareWebServices/Services/Subscriber/ListSubscriberAccountSubscriptions?sessionId=%@", self.dexcomToken];
    NSString *parameters = nil;
    
    [AppDelegate dexcomPOSTToURLString:URLString
                        withParameters:parameters
                      withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                          DDLogDebug(@"received subscription list: %@", responseObject);
                          self.subscriptionId = responseObject[0][@"SubscriptionId"];
                          
                          [[NSNotificationCenter defaultCenter] postNotificationName:WSNotificationDexcomDataChanged object:nil userInfo:nil];
                          
                          if (!self.latestBloodSugarData) {
                              [self fetchLatestBloodSugar];
                          }
                      }
                      withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                          DDLogDebug(@"error: %@", error);
                      }];
}

- (void)fetchLatestBloodSugar
{
    NSString *URLString = [NSString stringWithFormat:@"https://share1.dexcom.com/ShareWebServices/Services/Subscriber/ReadLastGlucoseFromSubscriptions?sessionId=%@", self.dexcomToken];
    NSArray *parameters = @[self.subscriptionId];
    
    [AppDelegate dexcomPOSTToURLString:URLString
                        withParameters:parameters
                      withSuccessBlock:^(NSURLSessionDataTask * task, id responseObject) {
                          DDLogDebug(@"received blood sugar data: %@", responseObject);
                          self.latestBloodSugarData = responseObject[0][@"Egv"];
                      }
                      withFailureBlock:^(NSURLSessionDataTask * task, NSError * error) {
                          DDLogDebug(@"error: %@", error);
                          NSDictionary *jsonError = [NSJSONSerialization JSONObjectWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] options:0 error:NULL];
                          DDLogDebug(@"error response: %@", jsonError);
                          
                          if ([jsonError[@"Code"] isEqualToString:@"SessionNotValid"]) {
                              self.dexcomToken = nil;
                              self.subscriptionId = nil;
                              self.latestBloodSugarData = nil;
                              
                              [self fetchTimerFired:nil];
                          }
                          
                          if (_backgroundFetchCompletionHandler) {
                              DDLogDebug(@"fetch handler: UIBackgroundFetchResultFailed");
                              _backgroundFetchCompletionHandler(UIBackgroundFetchResultFailed);
                              _backgroundFetchCompletionHandler = NULL;
                          }
                      }];
}

- (void)sendAllBloodSugarReadingsFromPastDay
{
    int64_t hourAgoEpochMilliseconds = (int64_t)([[NSDate date] timeIntervalSince1970] - (24 * 60)) * 1000;
    NSArray *readingsPastHour = [Reading MR_findAllSortedBy:@"timestamp" ascending:NO withPredicate:[NSPredicate predicateWithFormat:@"timestamp > %ld", hourAgoEpochMilliseconds]];
    
    NSMutableArray *readingDictionaries = [NSMutableArray new];
    [readingsPastHour enumerateObjectsUsingBlock:^(Reading *obj, NSUInteger idx, BOOL *stop) {
        [readingDictionaries addObject:@{
                                         @"timestamp": obj.timestamp,
                                         @"value": obj.value,
                                         @"trend": obj.trend,
                                         }];
    }];
    
    [[WCSession defaultSession] transferCurrentComplicationUserInfo:@{@"readings": readingDictionaries}];
}

#pragma mark - Custom setter methods

-(void)setLatestBloodSugarData:(NSDictionary *)latestBloodSugarData
{
    _latestBloodSugarData = latestBloodSugarData;
    
    if (_latestBloodSugarData) {
        
        Reading * latestReading = [Reading MR_findFirstOrderedByAttribute:@"timestamp" ascending:NO];
        NSString *STDate = [_latestBloodSugarData[@"ST"] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()"]][1];
        int64_t epochMilliseconds = [STDate longLongValue];
        if ([latestReading.timestamp longLongValue] != epochMilliseconds)
        {
            [MagicalRecord saveWithBlock:^(NSManagedObjectContext *localContext) {
                Reading *newReading = [Reading MR_createEntityInContext:localContext];
                newReading.timestamp = @(epochMilliseconds);
                newReading.trend = _latestBloodSugarData[@"Trend"];
                newReading.value = _latestBloodSugarData[@"Value"];
            } completion:^(BOOL contextDidSave, NSError *error) {
                [self sendAllBloodSugarReadingsFromPastDay];
                if (_backgroundFetchCompletionHandler) {
                    DDLogDebug(@"fetch handler: UIBackgroundFetchResultNewData");
                    _backgroundFetchCompletionHandler(UIBackgroundFetchResultNewData);
                    _backgroundFetchCompletionHandler = NULL;
                }
            }];
        } else {
            if (_backgroundFetchCompletionHandler) {
                DDLogDebug(@"fetch handler: UIBackgroundFetchResultNoData");
                _backgroundFetchCompletionHandler(UIBackgroundFetchResultNoData);
                _backgroundFetchCompletionHandler = NULL;
            }
            DDLogDebug(@"Latest Egv value has already been saved to Core Data. Skipping.");
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:WSNotificationDexcomDataChanged object:nil userInfo:nil];
    }
}

#pragma mark - WCSessionDelegate methods

- (void)session:(WCSession *)session didReceiveMessage:(NSDictionary<NSString *, id> *)message
{
    if ([message[@"watchIsRequestingUpdate"] boolValue]) {
        [self sendAllBloodSugarReadingsFromPastDay];
    }
}

@end
