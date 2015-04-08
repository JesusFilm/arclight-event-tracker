//
//  Engagement.m
//  Engagement
//
//  Copyright MBSJ LLC
//

// builds the docs
// run from the project directory
// appledoc --project-name "eventtracker-ios" --project-company "com.test" --output "Docs" --keep-intermediate-files --ignore .m --ignore Reachability.h Engagement

#import "EventTracker.h"
#import <sqlite3.h>
#import <CoreLocation/CoreLocation.h>
#import "Reachability.h"
#import <dispatch/dispatch.h>
#import <sys/utsname.h>

// Constants
// production

#ifdef DEBUG
    #define kApiEndpoint @"http://jfm-oestage-env.elasticbeanstalk.com/VideoPlayEvent/"
#else
    #define kApiEndpoint @"https://analytics.arclight.org/VideoPlayEvent/"
#endif

#define kReachabilityHostName @"analytics.arclight.org"
#define kType @"mobile"
#define kDeviceFamily @"Apple"
#define kMaxEventsPerRequest 100
#define kSyncWithWebTime 10
// User Defaults
#define kUserDefaultLastKnownLatitude @"kUserDefaultLastKnownLatitude"
#define kUserDefaultLastKnownLongitude @"kUserDefaultLastKnownLongitude"
typedef void (^EventOperationResponseBlock) (NSArray *events, NSError *error);

#pragma mark - private class declarations
/**
 * Defines our Event class to hold the event data.
 */
@interface Event:NSObject
@property(nonatomic) NSInteger event_id;
@property(nonatomic) long timestamp;
@property(nonatomic) BOOL hasLocationData;
@property(nonatomic, strong) NSMutableDictionary *request;
@property(nonatomic) BOOL synced;
@end

@implementation Event
@end

/**
 * Defines the interface for our operation
 */
@interface EventOperation: NSOperation
@property(nonatomic, strong) NSArray *events;
@property(nonatomic, strong) EventOperationResponseBlock block;
@end

@implementation EventOperation

- (void) main
{
    NSError *webError = nil;
    BOOL recoverable = NO;
    
    for(Event *event in self.events)
    {
        NSError *jsonError;
        
        NSDictionary *eventData = [NSDictionary dictionaryWithDictionary:event.request];
        NSArray *events = @[eventData];
        NSDictionary *body = @{@"events": events};
        
        NSData *postData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        
        if (!jsonError)
        {
            NSString *jsonString = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
            NSData *jsonStringData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
            
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?apiKey=%@",kApiEndpoint,[[EventTracker sharedInstance] apiKey]]];

            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0f];
            
            [request setHTTPMethod:@"POST"];
            [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
            [request setHTTPBody:jsonStringData];
            
            NSHTTPURLResponse *response = nil;
            NSError *requestError = nil;
            
            // Check success from the server
            NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&requestError];
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            
            if (httpResp.statusCode == 200)
            {
                NSError *jsonResponseError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonResponseError];
                
                if(jsonResponseError)
                {
                    webError = jsonResponseError;
                }
                else
                {
                    // Check the JSON response
                    NSString *type = json[@"Result"][@"Type"];
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
        }
        else
        {
            webError = jsonError;
            NSLog(@"Error parsing JSON while trying to post event: %@",[jsonError localizedDescription]);
        }
    }
    
    if(self.block)
    {
        if(webError && !recoverable) // Non recoverable error
        {
            self.block(self.events, webError);
        }
        else
        {
            if(webError) // Error but recoverable
            {
                self.block(nil, webError);
            }
            else // Success case
            {
                self.block(self.events, webError);
            }
        }
    }
}

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
@property(nonatomic, strong) NSOperationQueue *operationQueue;
@property(assign) BOOL webServicesAvailable;
@property(nonatomic, strong) Reachability *hostReachability;
@end

@implementation EventTracker
{
	dispatch_queue_t backGroundQueue;
}


+ (id)sharedInstance {
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
        self.operationQueue = [NSOperationQueue new];
        
        /*
         Observe the kNetworkReachabilityChangedNotification. When that notification is posted, the method reachabilityChanged will be called.
         */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
        
        // Determine current reachability status
        self.hostReachability = [Reachability reachabilityWithHostName:kReachabilityHostName];
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
    [[EventTracker sharedInstance] syncWithWeb:self];
}

+ (void) trackPlayEventWithRefID:(NSString *) refID
                    apiSessionID:(NSString *) apiSessionID
                       streaming:(BOOL) streaming
          mediaViewTimeInSeconds:(float) seconds
    mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent
{
    
    if(![[EventTracker sharedInstance] apiKey])
    {
        NSLog(@"Error: Event tracker API key not set.  Tracking events will not be logged");
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
    
    Event *event = [[Event alloc] init];
    event.hasLocationData = hasLocationData;
    event.event_id = 0;
    event.request = [eventDictionary mutableCopy];
    event.timestamp = timestamp;
	
	[[EventTracker sharedInstance] insertEvent:event];
    
    // Attempt a sync on event insert
    [[EventTracker sharedInstance] syncWithWeb:self];
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

/**
 * Creates the sqlite database if it doesn't already exit. If the database exits, this method fails siliently.
 *
 * @return a boolean as to whether the db was created correctly
 */
- (BOOL)createDB
{
    NSString *databasePath = [self databasePath];
    BOOL isSuccess = YES;
    NSFileManager *filemgr = [NSFileManager defaultManager];
    // Check if the databse exits
    if (![filemgr fileExistsAtPath: databasePath ])
    {
        const char *dbpath = [databasePath UTF8String];
        if (sqlite3_open(dbpath, &_database) == SQLITE_OK)
        {
            char *errMsg;
            const char *sql_stmt =
            "create table if not exists events (id integer primary key autoincrement, timestamp long, has_location_data integer, request text)";
            if (sqlite3_exec(self.database, sql_stmt, NULL, NULL, &errMsg)
                != SQLITE_OK)
            {
                isSuccess = NO;
                NSLog(@"Failed to create database table");
            }
            sqlite3_close(self.database);
            return  isSuccess;
        }
        else {
            isSuccess = NO;
            NSLog(@"Failed to open/create database");
        }
    }
    return isSuccess;
}

#pragma mark - Reachability setup

/*
 * Called by Reachability whenever status changes.
 */
- (void) reachabilityChanged:(NSNotification *)note
{
	Reachability* curReach = [note object];
	NSParameterAssert([curReach isKindOfClass:[Reachability class]]);
	[self updateInterfaceWithReachability:curReach];
}

- (void)updateInterfaceWithReachability:(Reachability *)reachability
{
    if (reachability == self.hostReachability)
	{
        NetworkStatus netStatus = [reachability currentReachabilityStatus];
        self.webServicesAvailable = (netStatus != NotReachable);
        [self syncWithWeb:self];
    }
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
    NSString *databasePath = [self databasePath];
    BOOL isSuccess = YES;
    NSFileManager *filemgr = [NSFileManager defaultManager];
    // Check if the databse exits
    if ([filemgr fileExistsAtPath: databasePath ])
    {
        const char *dbpath = [databasePath UTF8String];
        if (sqlite3_open(dbpath, &_database) == SQLITE_OK)
        {
            const char *stmt = [sql UTF8String];
            sqlite3_stmt *statement = nil;
            sqlite3_prepare_v2(self.database, stmt,-1, &statement, NULL);
            if (sqlite3_step(statement) == SQLITE_DONE)
            {
                sqlite3_close(self.database);
                return YES;
            }
            else
            {
                NSLog(@"Error %s while preparing statement", sqlite3_errmsg(self.database));
                sqlite3_close(self.database);
                return NO;
            }
            sqlite3_reset(statement);
        }
        else
        {
            isSuccess = NO;
        }
    }
    else
    {
        NSLog(@"Error inserting event. Database doesn't exit.");
        isSuccess = NO;
    }
    
    return isSuccess;
}

/**
 * Inserts a new event into the database 
 *
 * @params the event object to be inserted
 * @return boolean as to whether or not the request completed
 */
- (BOOL) insertEvent:(Event *) event
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
- (BOOL) updateEvent:(Event *) event
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
- (BOOL) removeEvent:(Event *)event
{
    NSString *sql = [NSString stringWithFormat:@"delete from events where id = %d ",(int)event.event_id];
    return [self queryDatabase:sql];
}

/**
 * Updates the location for all events that are missing a location. 
 * @return a boolean value as to whether the record was updated
 */
- (BOOL) updateLocationForEvents
{
    NSArray *events = [self getAllEvents:YES];
    
    for (Event *event in events)
    {
        NSMutableDictionary *request = event.request;
        request[@"latitude"] = [NSNumber numberWithFloat:self.latitude];
        request[@"longitude"] = [NSNumber numberWithFloat:self.longitude];
        event.request = request;
        event.hasLocationData = YES;
        [self updateEvent:event];
    }
    
    return 1;
}

/**
 * Fetches all events from the database.
 * 
 * @params withoutLocationData a boolean determining if we only want events with no location data
 * @return an array of event objects
 **/
- (NSArray *) getAllEvents:(BOOL) withoutLocationData
{
    NSMutableArray *events = [@[] mutableCopy];
    NSString *databasePath = [self databasePath];
    const char *dbpath = [databasePath UTF8String];
    NSString *query;
    if(withoutLocationData)
    {
        query = [NSString stringWithFormat:@"SELECT * from events where has_location_data = 0"];
    }
    else
    {
        query = [NSString stringWithFormat:@"SELECT * from events"];
    }
    sqlite3_stmt *statement;
    if (sqlite3_open(dbpath, &_database) == SQLITE_OK)
    {
        if (sqlite3_prepare_v2(_database, [query UTF8String], -1, &statement, nil) == SQLITE_OK)
        {
           while (sqlite3_step(statement) == SQLITE_ROW)
           {
               int uniqueId = sqlite3_column_int(statement, 0);
               long timestamp = (long)sqlite3_column_int(statement, 1);
               int has_location_data = sqlite3_column_int(statement, 2);
               char *request_char = (char *) sqlite3_column_text(statement, 3);
               NSString *request = [[NSString alloc] initWithUTF8String:request_char];
               
               Event *event = [[Event alloc] init];
               event.event_id = uniqueId;
               event.timestamp = timestamp;
               event.hasLocationData = has_location_data;
               NSData *jsonData = [request dataUsingEncoding:NSUTF8StringEncoding];
               event.request = [[NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil] mutableCopy];
               [events addObject:event];
           }
           sqlite3_finalize(statement);
        }
        
    }
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
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
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

- (void) syncWithWeb:(id) sender
{
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void){
        NSArray *events = [[EventTracker sharedInstance] getAllEvents:NO];
        
        if ([events count] > 0)
        {
            NSError *webError = nil;
            BOOL recoverable = NO;
            
            for(Event *event in events)
            {
                NSError *jsonError;
                
                NSDictionary *eventData = [NSDictionary dictionaryWithDictionary:event.request];
                NSArray *events = @[eventData];
                NSDictionary *body = @{@"events": events};
                
                NSData *postData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
                
                if (!jsonError)
                {
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
                    
                    NSHTTPURLResponse *response = nil;
                    NSError *requestError = nil;
                    
                    // Check success from the server
                    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                         returningResponse:&response
                                                                     error:&requestError];
                    NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
                    
//                    NSString *strResponse = [[NSString alloc] initWithData:data
//                                                                  encoding:NSUTF8StringEncoding];
                    
                    if (httpResp.statusCode == 200)
                    {
                        NSError *jsonResponseError = nil;
                        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonResponseError];
                        
                        if(jsonResponseError)
                        {
                            webError = jsonResponseError;
                        }
                        else
                        {
                            // Check the JSON response
                            NSString *type = json[@"Result"][@"Type"];
                            if(![type isEqualToString:@"Success"])
                            {
                                webError = [NSError errorWithDomain:@"com.arclight.response" code:(long)httpResp.statusCode userInfo:@{}];
                            }
                        }
                        NSLog(@"response %@", json);
                        
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
                }
                else
                {
                    webError = jsonError;
                    NSLog(@"Error parsing JSON while trying to post event: %@",[jsonError localizedDescription]);
                }
            }
            
            if(!webError)
            {
                
                NSLog(@"deleting these events %@", events);
                // Delete this group of events
                for (Event *event in events)
                {
                    [self removeEvent:event];
                }
            }
            else
            {
                if(events && events.count && !recoverable) // Unrecoverable error
                {
                    for (Event *event in events)
                    {
                        [self removeEvent:event];
                    }
                }
                else
                {
                    // Do nothing and ignore
                    NSLog(@"A recoverable error occured %@", webError);
                }
            }
        }
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
