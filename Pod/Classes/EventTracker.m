//
//  EventTracker.m
//  EventTracker
//
//  Copyright MBSJ LLC
//

// builds the docs
// run from the project directory
// appledoc --project-name "arclight-event-tracker" --project-company "com.test" --output "Docs" --keep-intermediate-files --ignore .m --ignore Reachability.h Engagement

#import "EventTracker.h"
#import <sqlite3.h>
#import <CoreLocation/CoreLocation.h>
#import "JFMReachability.h"
#import <sys/utsname.h>

// Constants
// production


NSString * const kShareMethodTwitter = @"Twitter";
NSString * const kShareMethodEmail = @"Email";
NSString * const kShareMethodFacebook = @"Facebook";
NSString * const kShareMethodBlueTooth3GP = @"Bluetooth 3GP";
NSString * const kShareMethodEmbedURL = @"Embed URL Copy";


#ifdef DEBUG
static NSString * const kApiBaseUrl = @"http://staging-analytics.arclight.org";
#else
static NSString * const kApiBaseUrl = @"https://analytics.arclight.org";
#endif

static NSString * const kApiPlayEndpoint = @"/VideoPlayEvent/";
static NSString * const kApiShareEndpoint = @"/ShareEvent/";


static NSString * const kReachabilityHostName = @"analytics.arclight.org";
static NSString * const kType = @"mobile";
static NSString * const kDeviceFamily = @"Apple";
// User Defaults
static NSString * const kUserDefaultLastKnownLatitude = @"kUserDefaultLastKnownLatitude";
static NSString * const kUserDefaultLastKnownLongitude = @"kUserDefaultLastKnownLongitude";

#pragma mark - private class declarations
/**
 * Defines our Event class to hold the event data.
 */
@interface JFMEvent : NSObject
@property(nonatomic) NSInteger event_id;
@property(nonatomic) long timestamp;
@property(nonatomic) BOOL hasLocationData;
@property(nonatomic, strong) NSMutableDictionary *request;
@end

@implementation JFMEvent
@end

#pragma mark - Event Tracker

@interface EventTracker() <CLLocationManagerDelegate>
@property(nonatomic, strong) NSString *apiKey;
@property(nonatomic, strong) NSString *appDomain;
@property(nonatomic, strong) NSString *appName;
@property(nonatomic, strong) NSString *appVersion;
@property(nonatomic, strong) CLLocationManager *locationManager;
@property(nonatomic) sqlite3 *database;
@property(nonatomic) float latitude;
@property(nonatomic) float longitude;
@property(assign) BOOL syncing;
@property(assign) BOOL webServicesAvailable;
@property(assign) BOOL loggingEnabled;
@property(nonatomic, strong) JFMReachability *hostReachability;
@property(nonatomic, assign) UIBackgroundTaskIdentifier syncTaskID;
@property(nonatomic, strong) NSString *baseUrl;
@end

@implementation EventTracker

+ (instancetype) sharedInstance
{
    static EventTracker *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id) init
{
    if(self = [super init])
    {
        [self createDB];

        self.syncTaskID = UIBackgroundTaskInvalid;
        
        /*
         Observe the kNetworkReachabilityChangedNotification. When that notification is posted, the method reachabilityChanged will be called.
         */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kJFMReachabilityChangedNotification object:nil];
        
        // Determine current reachability status
        self.hostReachability = [JFMReachability reachabilityWithHostName:kReachabilityHostName];
        // Monitor reachability events
        [self.hostReachability startNotifier];
        [self updateInterfaceWithReachability:self.hostReachability];
    }
    return self;
}

#pragma mark - Public methods
+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion
{
  [self initializeWithApiKey:apiKey appDomain:appDomain appName:appName appVersion:appVersion isProduction:true];
}

+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion isProduction:(BOOL) isProd {
  [[EventTracker sharedInstance] setApiKey:apiKey];
  [[EventTracker sharedInstance] setAppDomain:appDomain];
  [[EventTracker sharedInstance] setAppName:appName];
  [[EventTracker sharedInstance] setAppVersion:appVersion];
  if (isProd) {
    [[EventTracker sharedInstance] setBaseUrl:@"https://analytics.arclight.org"];
  } else {
    [[EventTracker sharedInstance] setBaseUrl:@"http://staging-analytics.arclight.org"];
  }
  [[EventTracker sharedInstance] initLocationManager];
}

+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion isProduction:(BOOL) isProd trackLocation:(BOOL) trackLocation {
  if (!trackLocation) {
    [[EventTracker sharedInstance] setApiKey:apiKey];
    [[EventTracker sharedInstance] setAppDomain:appDomain];
    [[EventTracker sharedInstance] setAppName:appName];
    [[EventTracker sharedInstance] setAppVersion:appVersion];
    if (isProd) {
      [[EventTracker sharedInstance] setBaseUrl:@"https://analytics.arclight.org"];
    } else {
      [[EventTracker sharedInstance] setBaseUrl:@"http://staging-analytics.arclight.org"];
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    float lastLat = ([defaults floatForKey:kUserDefaultLastKnownLatitude]) ? [defaults floatForKey:kUserDefaultLastKnownLatitude] : 0;
    float lastLong = ([defaults floatForKey:kUserDefaultLastKnownLongitude]) ? [defaults floatForKey:kUserDefaultLastKnownLongitude] : 0;
    [self setLatitude:lastLat longitude: lastLong];
  } else {
    [self initializeWithApiKey:apiKey appDomain:appDomain appName:appName appVersion:appVersion isProduction:isProd];
  }
}

+ (void) applicationDidBecomeActive
{
    [[[EventTracker sharedInstance] locationManager] startUpdatingLocation];
    // Sync when the app becomes active
    [[EventTracker sharedInstance] syncEvents];
}

+ (void) setLoggingEnabled: (BOOL)loggingEnabled
{
    [EventTracker sharedInstance].loggingEnabled = loggingEnabled;
}

+ (void) setLatitude:(float)latitude longitude:(float)longitude
{
  [EventTracker sharedInstance].latitude = latitude;
  [EventTracker sharedInstance].longitude = longitude;
  
  // update the last known location
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setFloat:latitude forKey:kUserDefaultLastKnownLatitude];
  [defaults setFloat:longitude forKey:kUserDefaultLastKnownLongitude];
  [defaults synchronize];
  
  // Update any events with the new location in case they were recorded while offline
  [[EventTracker sharedInstance] updateLocationForEvents];
}

+ (void) trackPlayEventWithRefID:(NSString *) refID apiSessionID:(NSString *) apiSessionID streaming:(BOOL) streaming mediaViewTimeInSeconds:(float) seconds mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent
{
    [self trackPlayEventWithRefID:refID apiSessionID:apiSessionID streaming:streaming mediaViewTimeInSeconds:seconds mediaEngagementOver75Percent:mediaEngagementOver75Percent extraParams:nil];
}

+ (void) trackPlayEventWithRefID:(NSString *) refID
                    apiSessionID:(NSString *) apiSessionID
                       streaming:(BOOL) streaming
          mediaViewTimeInSeconds:(float) seconds
    mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent
                     extraParams:(NSDictionary *)extraParams
{
    
    [self trackPlayEventWithRefID:refID apiSessionID:apiSessionID streaming:streaming mediaViewTimeInSeconds:seconds mediaEngagementOver75Percent:mediaEngagementOver75Percent extraParams:extraParams customParams:nil];
}

+ (void) trackPlayEventWithRefID:(NSString *) refID apiSessionID:(NSString *) apiSessionID streaming:(BOOL) streaming mediaViewTimeInSeconds:(float) seconds mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent extraParams:(NSDictionary *)extraParams customParams:(NSDictionary *)customParams {
    
    if(![[EventTracker sharedInstance] apiKey])
    {
        [[EventTracker sharedInstance] logMessage: @"Error: Event tracker API key not set. Tracking events will not be logged."];
        return;
    }
    
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    
    // per arclight - they want deviceId & each eventID
    NSString *eventUUID = [[NSUUID UUID] UUIDString];
    
    NSString *type = kType;
    float latitude = [[EventTracker sharedInstance] latitude];
    float longitude = [[EventTracker sharedInstance] longitude];
    BOOL hasLocationData = latitude > 0 || longitude > 0;
    
    NSString *deviceFamily = kDeviceFamily;
    NSString *deviceName = [[EventTracker sharedInstance] getDeviceType];
    
    NSString *deviceOS = [NSString stringWithFormat:@"%@ %@",@"iOS",
                          [[UIDevice currentDevice] systemVersion]];
    NSString *domain = [[EventTracker sharedInstance] appDomain];
    NSString *appName = [[EventTracker sharedInstance] appName];
    NSString *appVersion = [[EventTracker sharedInstance] appVersion];
    
    NSString *deviceType =  UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? @"tablet" : @"handheld";
    
    NSMutableDictionary *eventDictionary = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                           @"timestamp" : [NSNumber numberWithLongLong:timestamp],
                                                                                           @"uuid" : eventUUID,
                                                                                           @"type" : type,
                                                                                           @"latitude" : [NSNumber numberWithFloat:latitude],
                                                                                           @"longitude" : [NSNumber numberWithFloat:longitude],
                                                                                           @"apiSessionId" : apiSessionID ? apiSessionID : @"N/A",
                                                                                           @"deviceFamily" : deviceFamily,
                                                                                           @"deviceName" : deviceName,
                                                                                           @"deviceOs" : deviceOS,
                                                                                           @"domain" : domain,
                                                                                           @"appName" : appName,
                                                                                           @"appVersion" : appVersion,
                                                                                           @"isStreaming" : streaming ? @"true" : @"false",
                                                                                           @"mediaViewTimeInSeconds" : [NSString stringWithFormat:@"%f",seconds],
                                                                                           @"mediaEngagementOver75Percent" : mediaEngagementOver75Percent ? @"true" : @"false",
                                                                                           @"deviceType" : deviceType
                                                                                           }];
    
    NSString *mediaComponentId;
    NSString *languageId;
    if (extraParams)
    {
        if (extraParams[@"appScreen"])
        {
            [eventDictionary setObject:extraParams[@"appScreen"] forKey:@"appScreen"];
        }
        
        if (extraParams[@"subtitleLanguageId"])
        {
            [eventDictionary setObject:extraParams[@"subtitleLanguageId"] forKey:@"subtitleLanguageId"];
        }
        
        if (extraParams[@"mediaComponentId"] && extraParams[@"languageId"])
        {
            mediaComponentId = extraParams[@"mediaComponentId"];
            languageId = extraParams[@"languageId"];
        }
    }
    
    if (refID)
    {
        [eventDictionary setObject:refID forKey:@"refId"];
    }
    else if (mediaComponentId && languageId)
    {
        [eventDictionary setObject:mediaComponentId forKey:@"mediaComponentId"];
        [eventDictionary setObject:languageId forKey:@"languageId"];
    }
    else
    {
        [[EventTracker sharedInstance] logMessage: @"Error: Event tracker refId or mediaComponentId and languageId not set. Tracking events will not be logged."];
        return;
    }
    
    if (customParams) {
        eventDictionary[@"custom"] = customParams;
    }
    
    JFMEvent *event = [JFMEvent new];
    event.hasLocationData = hasLocationData;
    event.event_id = 0;
    event.request = [eventDictionary mutableCopy];
    event.timestamp = timestamp;
    
    if([[EventTracker sharedInstance] insertEvent:event])
    {
        [[EventTracker sharedInstance] logMessage: [NSString stringWithFormat: @"successfully added event with dict: %@", eventDictionary]];
    }
    
    // Attempt a sync on event insert
    [[EventTracker sharedInstance] syncEvents];
}

+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod
                                  refID:(NSString *) refID
                           apiSessionID:(NSString *) apiSessionID
{
    [self trackShareEventFromShareMethod:shareMethod refID:refID apiSessionID:apiSessionID extraParams:nil];
}

+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod
                                  refID:(NSString *) refID
                           apiSessionID:(NSString *) apiSessionID
                            extraParams:(NSDictionary *)extraParams
{
    [self trackShareEventFromShareMethod:shareMethod refID:refID apiSessionID:apiSessionID extraParams:extraParams customParams:nil];
}

+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod
                                  refID:(NSString *) refID
                           apiSessionID:(NSString *) apiSessionID
                            extraParams:(NSDictionary *)extraParams customParams: (NSDictionary*)customParams
{
    if(![[EventTracker sharedInstance] apiKey])
    {
        [[EventTracker sharedInstance] logMessage: @"Error: Event tracker API key not set. Tracking events will not be logged."];
        return;
    }
    
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    
    // per arclight - they want deviceId & each eventID
    NSString *eventUUID = [[NSUUID UUID] UUIDString];
    
    NSString *type = kType;
    float latitude = [[EventTracker sharedInstance] latitude];
    float longitude = [[EventTracker sharedInstance] longitude];
    
    NSString *deviceFamily = kDeviceFamily;
    NSString *deviceName = [[EventTracker sharedInstance] getDeviceType];
    NSString *deviceOS = [NSString stringWithFormat:@"%@ %@",@"iOS",
                          [[UIDevice currentDevice] systemVersion]];
    NSString *appName = [[EventTracker sharedInstance] appName];
    NSString *appVersion = [[EventTracker sharedInstance] appVersion];
    
    NSString *deviceType =  UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? @"tablet" : @"handheld";
    
    NSMutableDictionary *eventDictionary = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                           @"timestamp" : [NSNumber numberWithLongLong:timestamp],
                                                                                           @"uuid" : eventUUID,
                                                                                           @"type" : type,
                                                                                           @"latitude" : [NSNumber numberWithFloat:latitude],
                                                                                           @"longitude" : [NSNumber numberWithFloat:longitude],
                                                                                           @"apiSessionId" : apiSessionID ? apiSessionID : @"N/A",
                                                                                           @"deviceFamily" : deviceFamily,
                                                                                           @"deviceName" : deviceName,
                                                                                           @"deviceOs" : deviceOS,
                                                                                           @"appName" : appName,
                                                                                           @"appVersion" : appVersion,
                                                                                           @"shareMethod" : shareMethod,
                                                                                           @"deviceType" : deviceType
                                                                                           }];
    NSString *mediaComponentId;
    NSString *languageId;
    if (extraParams)
    {
        if (extraParams[@"mediaComponentId"] && extraParams[@"languageId"])
        {
            mediaComponentId = extraParams[@"mediaComponentId"];
            languageId = extraParams[@"languageId"];
        }
    }
    
    if (refID)
    {
        [eventDictionary setObject:refID forKey:@"refId"];
    }
    else if (mediaComponentId && languageId)
    {
        [eventDictionary setObject:mediaComponentId forKey:@"mediaComponentId"];
        [eventDictionary setObject:languageId forKey:@"languageId"];
    }
    else
    {
        [[EventTracker sharedInstance] logMessage: @"Error: Event tracker refId or mediaComponentId and languageId not set. Tracking events will not be logged."];
        return;
    }
    
    if (customParams) {
        eventDictionary[@"custom"] = customParams;
    }
    
    
    [[EventTracker sharedInstance] postSharedEvent:eventDictionary];
}

#pragma mark - Reachability setup

/*
 * Called by Reachability whenever status changes.
 */
- (void) reachabilityChanged:(NSNotification *)note
{
    JFMReachability* curReach = [note object];
    NSParameterAssert([curReach isKindOfClass:[JFMReachability class]]);
    [self updateInterfaceWithReachability:curReach];
}

- (void) updateInterfaceWithReachability:(JFMReachability *)reachability
{
    if (reachability == self.hostReachability)
    {
        NetworkStatus netStatus = [reachability currentReachabilityStatus];
        self.webServicesAvailable = (netStatus != NotReachable);
        [self syncEvents];
    }
}

#pragma mark - Helpers

- (void) logMessage:(NSString *)message
{
    if (!self.loggingEnabled) {
        return;
    }
    
    NSLog(@"%@: %@", NSStringFromClass([self class]), message);
}

#pragma mark - sqlite

/**
 * Fetches the path to the databse. The database is sqlite and lives in the caches directory of the application
 *
 * @return string representing the path to the cache database
 */
- (NSString *) databasePath
{
    NSArray *dirPaths = NSSearchPathForDirectoriesInDomains
    (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = dirPaths[0];
    // Build the path to the database file
    NSString *databasePath = [[NSString alloc] initWithString:
                              [cachesDir stringByAppendingPathComponent: @"event_tracker.sqlite"]];
    return databasePath;
}

- (BOOL) databaseExists
{
    return [[NSFileManager defaultManager] fileExistsAtPath: [self databasePath]];
}

/**
 * Creates the sqlite database if it doesn't already exist. If the database exists, this method fails silently.
 *
 * @return a boolean as to whether the db was created correctly
 */
- (BOOL) createDB
{
    if ([self databaseExists]) {
        return YES;
    }
    
    const char *dbpath = [[self databasePath] UTF8String];
    if (sqlite3_open(dbpath, &_database) != SQLITE_OK)
    {
        [self logMessage: @"Failed to open/create database"];
        return NO;
    }
    
    char *errMsg;
    const char *sql_stmt =
    "create table if not exists events (id integer primary key autoincrement, timestamp long, has_location_data integer, request text)";
    BOOL success = sqlite3_exec(self.database, sql_stmt, NULL, NULL, &errMsg) != SQLITE_OK;
    if (!success) {
        [self logMessage: @"Failed to create database table"];
    }
    
    sqlite3_close(self.database);
    return success;
}

#pragma mark - Database

/**
 * Performs a query on the sqlite database.
 *
 * @params sql  the statement in which to perform
 * @return a boolean value set to true if the execution was successful
 *
 */
- (BOOL) queryDatabase:(NSString *) sql
{
    if (![self databaseExists]) {
        [self logMessage: @"Error inserting event. Database doesn't exit."];
        return NO;
    }
    
    const char *dbpath = [[self databasePath] UTF8String];
    if (sqlite3_open(dbpath, &_database) != SQLITE_OK)
    {
        [self logMessage: @"Error opening database"];
        return NO;
    }
    
    const char *stmt = [sql UTF8String];
    sqlite3_stmt *statement = nil;
    sqlite3_prepare_v2(self.database, stmt, -1, &statement, NULL);
    
    BOOL success = sqlite3_step(statement) == SQLITE_DONE;
    if (!success) {
        [self logMessage: [NSString stringWithFormat: @"Error %s while preparing statement", sqlite3_errmsg(self.database)]];
    }
    sqlite3_reset(statement);
    sqlite3_close(self.database);
    
    return success;
}

/**
 * Inserts a new event into the database
 *
 * @param event the event object to be inserted
 * @return boolean as to whether or not the request completed
 */
- (BOOL) insertEvent:(JFMEvent *) event
{
    // Convert the dictionary to a JSON string
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:event.request
                                                       options:0
                                                         error:nil];
    NSString *requestString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    requestString = [requestString stringByReplacingOccurrencesOfString:@"'" withString:@""];
    
    NSString *sql = [NSString stringWithFormat:@"insert into events (timestamp, has_location_data, request) values (%ld, %d, '%@')",event.timestamp, event.hasLocationData, requestString];
    return [self queryDatabase:sql];
}

/**
 * Updates an event in the database. Used mainly when the location has been found.
 *
 * @params event the event object ot be updated
 * @return boolean as to whether or not the request completed
 */
- (BOOL) updateEvent:(JFMEvent *) event
{
    // Convert the dictionary to a JSON string
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:event.request
                                                       options:0
                                                         error:nil];
    NSString *requestString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *sql = [NSString stringWithFormat:@"update events set timestamp = %ld, has_location_data = %d, request = '%@' where id = %d ",event.timestamp, event.hasLocationData, requestString, (int)event.event_id];
    return [self queryDatabase:sql];
}

/**
 * Removes a successfully sync'ed event from database
 *
 */
- (BOOL) removeEvent:(JFMEvent *)event
{
    NSString *sql = [NSString stringWithFormat:@"delete from events where id = %d ",(int)event.event_id];
    return [self queryDatabase:sql];
}

/**
 * Updates the location for all events that are missing a location.
 */
- (void) updateLocationForEvents
{
    for (JFMEvent *event in [self eventsIncludingWithLocationData: NO])
    {
        NSMutableDictionary *request = event.request;
        request[@"latitude"] = [NSNumber numberWithFloat:self.latitude];
        request[@"longitude"] = [NSNumber numberWithFloat:self.longitude];
        event.request = request;
        event.hasLocationData = YES;
        [self updateEvent:event];
    }
}

/**
 * Fetches all events from the database.
 *
 * @params withLocationData a boolean determining if we only want events with no location data
 * @return an array of event objects
 **/
- (NSArray *) eventsIncludingWithLocationData: (BOOL)withLocationData
{
    NSMutableArray *events = [NSMutableArray new];
    NSString *databasePath = [self databasePath];
    const char *dbpath = [databasePath UTF8String];
    NSString *query = @"SELECT * from events";
    if (!withLocationData) {
        query = [query stringByAppendingString: @" where has_location_data = 0"];
    }
    
    sqlite3_stmt *statement;
    if (sqlite3_open(dbpath, &_database) != SQLITE_OK)
    {
        [self logMessage: @"Error opening database"];
        return events;
    }
    
    if (sqlite3_prepare_v2(_database, [query UTF8String], -1, &statement, nil) != SQLITE_OK)
    {
        [self logMessage: @"Error preparing database"];
        return events;
    }
    
    while (sqlite3_step(statement) == SQLITE_ROW)
    {
        int uniqueId = sqlite3_column_int(statement, 0);
        long timestamp = (long)sqlite3_column_int(statement, 1);
        int has_location_data = sqlite3_column_int(statement, 2);
        char *request_char = (char *) sqlite3_column_text(statement, 3);
        NSString *request = [[NSString alloc] initWithUTF8String:request_char];
        
        JFMEvent *event = [[JFMEvent alloc] init];
        event.event_id = uniqueId;
        event.timestamp = timestamp;
        event.hasLocationData = has_location_data;
        NSData *jsonData = [request dataUsingEncoding:NSUTF8StringEncoding];
        event.request = [[NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil] mutableCopy];
        [events addObject:event];
    }
    sqlite3_finalize(statement);
    
    return events;
}

#pragma mark - Location

/**
 * Initializes the location manager used to track the user's location.  The idea is to grab their
 * coordinates and then power down the GPS antenna to save battery.  This is because the user isn't
 * likely to move far.
 *
 */
- (void) initLocationManager
{
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    if (@available(iOS 14.0, *)) {
      self.locationManager.desiredAccuracy = kCLLocationAccuracyReduced;
    } else {
      self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    }
    [self.locationManager startUpdatingLocation];
}

/**
 * Delegate method for CLLocationManager fired when the user's location has been found. At this point,
 * we need to power down the GPS and store the location.
 */
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  if (locations.lastObject) {
    CLLocation *newLocation = locations.lastObject;
    self.latitude = newLocation.coordinate.latitude;
    self.longitude = newLocation.coordinate.longitude;
    [self.locationManager stopUpdatingLocation];
    
    // update the last known location
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:self.latitude forKey:kUserDefaultLastKnownLatitude];
    [defaults setFloat:self.longitude forKey:kUserDefaultLastKnownLongitude];
    [defaults synchronize];
    
    // Update any events with the new location in case they were recorded while offline
    [self updateLocationForEvents];
  }
}

/*
 * Called when location manager fails. If this is the case, the device is probably offline.  So, we look up
 * the last known location and use that instead.
 */
- (void) locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.latitude = [defaults floatForKey:kUserDefaultLastKnownLatitude];
    self.longitude = [defaults floatForKey:kUserDefaultLastKnownLongitude];
    [self.locationManager stopUpdatingLocation];
    
    // Update any events with the new location in case they were recorded while offline
    [self updateLocationForEvents];
}

#pragma mark - Web Interface

- (void) syncEvents
{
    if (self.syncing) {
        // a sync operation is already in progress
        return;
    }
    
    NSArray *events = [self eventsIncludingWithLocationData: YES];
    if(![events count]) {
        return;
    }
    
    self.syncing = YES;
    
    self.syncTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
        [[UIApplication sharedApplication] endBackgroundTask:self.syncTaskID];
        self.syncTaskID = UIBackgroundTaskInvalid;
    }];
    
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        __block NSError *webError;
        __block BOOL recoverable = NO;
        
        for(JFMEvent *event in events)
        {
            NSDictionary *eventData = [NSDictionary dictionaryWithDictionary:event.request];
            NSArray *events = @[eventData];
            NSDictionary *body = @{@"events": events};
            
            NSError *jsonError;
            NSData *postData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
            if (jsonError)
            {
                webError = jsonError;
                [self logMessage: [NSString stringWithFormat: @"Error parsing JSON while trying to post event: %@", [jsonError localizedDescription]]];
                continue;
            }
            
            NSString *jsonString = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
            NSData *jsonStringData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
            
            [self logMessage: [NSString stringWithFormat: @"postData.body(JSON) == %@", jsonString]];
          
            NSString *bUrl = ([[EventTracker sharedInstance] baseUrl] != 0) ? [[EventTracker sharedInstance] baseUrl] : kApiBaseUrl;
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@?apiKey=%@", bUrl, kApiPlayEndpoint,[[EventTracker sharedInstance] apiKey]]];
            
            [self logMessage: [NSString stringWithFormat: @"using url %@", url]];
            
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0f];
            
            [request setHTTPMethod:@"POST"];
            [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
            [request setHTTPBody:jsonStringData];
            
            // Check success from the server
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);  // semaphore makes the asynchronous NSURLSession method synchronous
            
            [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                 NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
                                                 
                                                 [self logMessage: [NSString stringWithFormat: @"response code: %d", (int)httpResp.statusCode]];
                                                 [self logMessage: [NSString stringWithFormat: @"raw response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]];
                                                 
                                                 if (httpResp.statusCode == 200)
                                                 {
                                                     NSError *jsonResponseError = nil;
                                                     NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonResponseError];
                                                     [self logMessage: [NSString stringWithFormat: @"response dict: %@", json]];
                                                     if(jsonResponseError)
                                                     {
                                                         webError = jsonResponseError;
                                                     }
                                                     else
                                                     {
                                                         // Check the JSON response
                                                         NSString *type = [json valueForKeyPath: @"Result.Type"];
                                                         if(![type isEqualToString:@"Success"])
                                                         {
                                                             webError = [NSError errorWithDomain:@"com.arclight.response" code:(long)httpResp.statusCode userInfo:@{}];
                                                         }
                                                     }
                                                     
                                                 }
                                                 // TODO: Check valid failures
                                                 else
                                                 {
                                                     // Recoverable errors
                                                     if(httpResp.statusCode == 502 ||
                                                        httpResp.statusCode == 503 ||
                                                        httpResp.statusCode == 504 ||
                                                        httpResp.statusCode == 507 ||
                                                        httpResp.statusCode == 509 ||
                                                        httpResp.statusCode == 511 ||
                                                        httpResp.statusCode == 598 ||
                                                        httpResp.statusCode == 599)
                                                     {
                                                       recoverable = YES;
                                                     } else if (httpResp == nil) {
                                                       recoverable = YES;
                                                     }
                                                     
                                                     webError = [NSError errorWithDomain:@"com.arclight" code:(long)httpResp.statusCode userInfo:@{}];
                                                 }
                                                 
                                                 dispatch_semaphore_signal(semaphore);
                                             }] resume];
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        }
        
        if(!webError)
        {
            [self logMessage: [NSString stringWithFormat: @"deleting synced events %@", events]];
            // Delete this group of events
            for (JFMEvent *event in events)
            {
                [weakSelf removeEvent:event];
            }
        }
        else
        {
            if(events.count && !recoverable) // Unrecoverable error
            {
                for (JFMEvent *event in events)
                {
                    [weakSelf removeEvent:event];
                }
            }
            else
            {
                // Do nothing and ignore
                [self logMessage: [NSString stringWithFormat: @"A recoverable error occurred %@", webError]];
            }
        }
        
        self.syncing = NO;
        
        [[UIApplication sharedApplication] endBackgroundTask:self.syncTaskID];
        self.syncTaskID = UIBackgroundTaskInvalid;
    });
}

- (void) postSharedEvent:(NSDictionary*)sharedEventData
{
    __block NSError *webError;

    NSDictionary *eventData = [NSDictionary dictionaryWithDictionary:sharedEventData];
    NSArray *events = @[eventData];
    NSDictionary *body = @{@"events": events};
    
    NSError *jsonError;
    NSData *postData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError)
    {
        webError = jsonError;
        [self logMessage: [NSString stringWithFormat: @"Error parsing JSON while trying to post event: %@", [jsonError localizedDescription]]];
    }
    
    NSString *jsonString = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
    NSData *jsonStringData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    [self logMessage: [NSString stringWithFormat: @"postData.body(JSON) == %@", jsonString]];
  
    NSString *bUrl = ([[EventTracker sharedInstance] baseUrl] != 0) ? [[EventTracker sharedInstance] baseUrl] : kApiBaseUrl;
  
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@?apiKey=%@", bUrl, kApiShareEndpoint,[[EventTracker sharedInstance] apiKey]]];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0f];
    
    [request setHTTPMethod:@"POST"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:jsonStringData];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
         completionHandler:^(NSData * _Nullable data,
                             NSURLResponse * _Nullable response,
                             NSError * _Nullable error)
    {
         NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
         
         [self logMessage: [NSString stringWithFormat: @"response code: %d", (int)httpResp.statusCode]];
         [self logMessage: [NSString stringWithFormat: @"raw response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]]];
         
         if (httpResp.statusCode == 200)
         {
             NSError *jsonResponseError = nil;
             NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonResponseError];
             [self logMessage: [NSString stringWithFormat: @"response dict: %@", json]];
             if(jsonResponseError)
             {
                 webError = jsonResponseError;
             }
             else
             {
                 // Check the JSON response
                 NSString *type = [json valueForKeyPath: @"Result.Type"];
                 if(![type isEqualToString:@"Success"])
                 {
                     webError = [NSError errorWithDomain:@"com.arclight.response" code:(long)httpResp.statusCode userInfo:@{}];
                 }
             }
         } else {
             [self logMessage:@"non 200 from sharing event"];
         }
    }] resume];
}

NSString* machineName()
{
    struct utsname systemInfo;
    uname(&systemInfo);
    
    return [NSString stringWithCString:systemInfo.machine
                              encoding:NSUTF8StringEncoding];
}

- (NSString *) getDeviceType
{
    NSString *platform = machineName();
    
    if ([platform isEqualToString:@"iPhone1,1"])    return @"iPhone 1G";
    if ([platform isEqualToString:@"iPhone1,2"])    return @"iPhone 3G";
    if ([platform isEqualToString:@"iPhone2,1"])    return @"iPhone 3GS";
    if ([platform isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
    if ([platform isEqualToString:@"iPhone3,3"])    return @"iPhone 4"; //@"Verizon iPhone 4";
    if ([platform isEqualToString:@"iPhone4,1"])    return @"iPhone 4S";
    if ([platform isEqualToString:@"iPhone5,1"])    return @"iPhone 5"; //@"iPhone 5 (GSM)";
    if ([platform isEqualToString:@"iPhone5,2"])    return @"iPhone 5"; //@"iPhone 5 (GSM+CDMA)";
    if ([platform isEqualToString:@"iPhone5,3"])    return @"iPhone 5c"; //@"iPhone 5c (GSM)";
    if ([platform isEqualToString:@"iPhone5,4"])    return @"iPhone 5c"; //@"iPhone 5c (GSM+CDMA)";
    if ([platform isEqualToString:@"iPhone6,1"])    return @"iPhone 5s"; //@"iPhone 5s (GSM)";
    if ([platform isEqualToString:@"iPhone6,2"])    return @"iPhone 5s"; //@"iPhone 5s (GSM+CDMA)";
    if ([platform isEqualToString:@"iPhone7,2"])    return @"iPhone 6";
    if ([platform isEqualToString:@"iPhone7,1"])    return @"iPhone 6 Plus";
    if ([platform isEqualToString:@"iPhone8,1"])    return @"iPhone 6s";
    if ([platform isEqualToString:@"iPhone8,2"])    return @"iPhone 6s Plus";
    if ([platform isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
    if ([platform isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
    if ([platform isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
    if ([platform isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
    if ([platform isEqualToString:@"iPod5,1"])      return @"iPod Touch 5G";
    if ([platform isEqualToString:@"iPad1,1"])      return @"iPad";
    if ([platform isEqualToString:@"iPad2,1"])      return @"iPad 2"; //@"iPad 2 (WiFi)";
    if ([platform isEqualToString:@"iPad2,2"])      return @"iPad 2"; //@"iPad 2 (GSM)";
    if ([platform isEqualToString:@"iPad2,3"])      return @"iPad 2"; //@"iPad 2 (CDMA)";
    if ([platform isEqualToString:@"iPad2,4"])      return @"iPad 2"; //@"iPad 2 (WiFi)";
    if ([platform isEqualToString:@"iPad2,5"])      return @"iPad Mini"; //@"iPad Mini (WiFi)";
    if ([platform isEqualToString:@"iPad2,6"])      return @"iPad Mini"; //@"iPad Mini (GSM)";
    if ([platform isEqualToString:@"iPad2,7"])      return @"iPad Mini"; //@"iPad Mini (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad3,1"])      return @"iPad 3"; //@"iPad 3 (WiFi)";
    if ([platform isEqualToString:@"iPad3,2"])      return @"iPad 3"; //@"iPad 3 (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad3,3"])      return @"iPad 3"; //@"iPad 3 (GSM)";
    if ([platform isEqualToString:@"iPad3,4"])      return @"iPad 4"; //@"iPad 4 (WiFi)";
    if ([platform isEqualToString:@"iPad3,5"])      return @"iPad 4"; //@"iPad 4 (GSM)";
    if ([platform isEqualToString:@"iPad3,6"])      return @"iPad 4"; //@"iPad 4 (GSM+CDMA)";
    if ([platform isEqualToString:@"iPad4,1"])      return @"iPad Air"; //@"iPad Air (WiFi)";
    if ([platform isEqualToString:@"iPad4,2"])      return @"iPad Air"; //@"iPad Air (Cellular)";
    if ([platform isEqualToString:@"iPad4,3"])      return @"iPad Air";
    if ([platform isEqualToString:@"iPad4,4"])      return @"iPad Mini 2G"; //@"iPad Mini 2G (WiFi)";
    if ([platform isEqualToString:@"iPad4,5"])      return @"iPad Mini 2G"; //@"iPad Mini 2G (Cellular)";
    if ([platform isEqualToString:@"iPad4,6"])      return @"iPad Mini 2G";
    if ([platform isEqualToString:@"iPad4,7"])      return @"iPad Mini 3"; //@"iPad Mini 3 (WiFi)";
    if ([platform isEqualToString:@"iPad4,8"])      return @"iPad Mini 3"; //@"iPad Mini 3 (Cellular)";
    if ([platform isEqualToString:@"iPad4,9"])      return @"iPad Mini 3"; //@"iPad Mini 3 (China)";
    if ([platform isEqualToString:@"iPad5,3"])      return @"iPad Air 2"; //@"iPad Air 2 (WiFi)";
    if ([platform isEqualToString:@"iPad5,4"])      return @"iPad Air 2"; //@"iPad Air 2 (Cellular)";
    if ([platform isEqualToString:@"AppleTV2,1"])   return @"Apple TV 2G";
    if ([platform isEqualToString:@"AppleTV3,1"])   return @"Apple TV 3";
    if ([platform isEqualToString:@"AppleTV3,2"])   return @"Apple TV 3"; // @"Apple TV 3 (2013)";
    if ([platform isEqualToString:@"i386"])         return @"Simulator";
    if ([platform isEqualToString:@"x86_64"])       return @"Simulator";
    return platform;
}

@end
