//
//  EventTracker.m
//  EventTracker
//
//  Copyright MBSJ LLC
//

// builds the docs
// run from the project directory
// appledoc --project-name "eventtracker-ios" --project-company "com.test" --output "Docs" --keep-intermediate-files --ignore .m --ignore Reachability.h Engagement

#import "EventTracker.h"
#import <sqlite3.h>
#import <CoreLocation/CoreLocation.h>
#import "JFMReachability.h"
#import <sys/utsname.h>

// Constants
// production

#ifdef DEBUG
static NSString * const kApiEndpoint = @"https://staging-analytics.arclight.org/VideoPlayEvent/";
#else
static NSString * const kApiEndpoint = @"https://analytics.arclight.org/VideoPlayEvent/";
#endif

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
@property(nonatomic, strong) JFMReachability *hostReachability;
@property(nonatomic, assign) UIBackgroundTaskIdentifier syncTaskID;
@end

@implementation EventTracker

+ (id) sharedInstance
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
        [self initLocationManager];
        
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
    [[EventTracker sharedInstance] setApiKey:apiKey];
    [[EventTracker sharedInstance] setAppDomain:appDomain];
    [[EventTracker sharedInstance] setAppName:appName];
    [[EventTracker sharedInstance] setAppVersion:appVersion];
}

+ (void) applicationDidBecomeActive
{
    [[[EventTracker sharedInstance] locationManager] startUpdatingLocation];
    // Sync when the app becomes active
    [[EventTracker sharedInstance] syncEvents];
}

+ (void) trackPlayEventWithRefID:(NSString *) refID
                    apiSessionID:(NSString *) apiSessionID
                       streaming:(BOOL) streaming
          mediaViewTimeInSeconds:(float) seconds
    mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent
{
    
    if(![[EventTracker sharedInstance] apiKey])
    {
        NSLog(@"Error: Event tracker API key not set. Tracking events will not be logged.");
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
    NSString *deviceName = machineName();
    
    NSString *deviceOS = [NSString stringWithFormat:@"%@ %@",@"iOS",
                          [[UIDevice currentDevice] systemVersion]];
    NSString *domain = [[EventTracker sharedInstance] appDomain];
    NSString *appName = [[EventTracker sharedInstance] appName];
    NSString *appVersion = [[EventTracker sharedInstance] appVersion];
    
    NSDictionary *eventDictionary = @{
                                      @"timestamp" : [NSNumber numberWithLongLong:timestamp],
                                      @"uuid" : eventUUID,
                                      @"type" : type,
                                      @"latitude" : [NSNumber numberWithFloat:latitude],
                                      @"longitude" : [NSNumber numberWithFloat:longitude],
                                      @"refId" : refID ? refID : @"N/A",
                                      @"apiSessionId" : apiSessionID ? apiSessionID : @"N/A",
                                      @"deviceFamily" : deviceFamily,
                                      @"deviceName" : deviceName,
                                      @"deviceOs" : deviceOS,
                                      @"domain" : domain,
                                      @"appName" : appName,
                                      @"appVersion" : appVersion,
                                      @"isStreaming" : streaming ? @"true" : @"false",
                                      @"mediaViewTimeInSeconds" : [NSString stringWithFormat:@"%f",seconds],
                                      @"mediaEngagementOver75Percent" : mediaEngagementOver75Percent ? @"true" : @"false"
                                      };
    
    JFMEvent *event = [JFMEvent new];
    event.hasLocationData = hasLocationData;
    event.event_id = 0;
    event.request = [eventDictionary mutableCopy];
    event.timestamp = timestamp;
    
    if([[EventTracker sharedInstance] insertEvent:event])
    {
        NSLog(@"successfully added event with dict: %@", eventDictionary);
    }
    
    // Attempt a sync on event insert
    [[EventTracker sharedInstance] syncEvents];
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
        NSLog(@"Failed to open/create database");
        return NO;
    }
    
    char *errMsg;
    const char *sql_stmt =
    "create table if not exists events (id integer primary key autoincrement, timestamp long, has_location_data integer, request text)";
    BOOL success = sqlite3_exec(self.database, sql_stmt, NULL, NULL, &errMsg) != SQLITE_OK;
    if (!success) {
        NSLog(@"Failed to create database table");
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
        NSLog(@"Error inserting event. Database doesn't exit.");
        return NO;
    }
    
    const char *dbpath = [[self databasePath] UTF8String];
    if (sqlite3_open(dbpath, &_database) != SQLITE_OK)
    {
        NSLog(@"Error opening database");
        return NO;
    }
    
    const char *stmt = [sql UTF8String];
    sqlite3_stmt *statement = nil;
    sqlite3_prepare_v2(self.database, stmt, -1, &statement, NULL);
    
    BOOL success = sqlite3_step(statement) == SQLITE_DONE;
    if (!success) {
        NSLog(@"Error %s while preparing statement", sqlite3_errmsg(self.database));
    }
    sqlite3_reset(statement);
    sqlite3_close(self.database);
    
    return success;
}

/**
 * Inserts a new event into the database
 *
 * @params the event object to be inserted
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
 * @return a boolean value as to whether the record was updated
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
 * @params withoutLocationData a boolean determining if we only want events with no location data
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
        NSLog(@"Error opening database");
        return events;
    }
    
    if (sqlite3_prepare_v2(_database, [query UTF8String], -1, &statement, nil) != SQLITE_OK)
    {
        NSLog(@"Error preparing database");
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
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    [self.locationManager startUpdatingLocation];
}

/**
 * Delegate method for CLLocationManager fired when the user's location has been found. At this point,
 * we need to power down the GPS and store the location.
 */
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
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
                NSLog(@"Error parsing JSON while trying to post event: %@",[jsonError localizedDescription]);
                continue;
            }
            
            NSString *jsonString = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
            NSData *jsonStringData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
            
            NSLog(@"postData.body(JSON) == %@",jsonString);
            
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?apiKey=%@",kApiEndpoint,[[EventTracker sharedInstance] apiKey]]];
            
            NSLog(@"using url %@",url);
            
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
                                                 
                                                 NSLog(@"response code: %d", (int)httpResp.statusCode);
                                                 NSLog(@"raw response: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                                                 
                                                 if (httpResp.statusCode == 200)
                                                 {
                                                     NSError *jsonResponseError = nil;
                                                     NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonResponseError];
                                                     NSLog(@"response dict: %@", json);
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
                                                     }
                                                     
                                                     webError = [NSError errorWithDomain:@"com.arclight" code:(long)httpResp.statusCode userInfo:@{}];
                                                 }
                                                 
                                                 dispatch_semaphore_signal(semaphore);
                                             }] resume];
            
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        }
        
        if(!webError)
        {
            NSLog(@"deleting synced events %@", events);
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
                NSLog(@"A recoverable error occurred %@", webError);
            }
        }
        
        self.syncing = NO;
        
        [[UIApplication sharedApplication] endBackgroundTask:self.syncTaskID];
        self.syncTaskID = UIBackgroundTaskInvalid;
    });
}

NSString* machineName()
{
    struct utsname systemInfo;
    uname(&systemInfo);
    
    return [NSString stringWithCString:systemInfo.machine
                              encoding:NSUTF8StringEncoding];
}

@end
