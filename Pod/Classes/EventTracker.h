//
//  EventTracker.h
//  EventTracker
//
//  Copyright MBSJ LLC
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// share method constants
extern NSString * const kShareMethodTwitter;
extern NSString * const kShareMethodEmail;
extern NSString * const kShareMethodFacebook;
extern NSString * const kShareMethodBlueTooth3GP;
extern NSString * const kShareMethodEmbedURL;

/**
 *  <p>The Event Tracker is used to track plays of a given video.</p>
 *
 *  <p>Make sure to link the following frameworks with your project.</p>
 *  <ul>
 *    <li> libsqlite3.0.dylib</li>
 *    <li> CoreLocation.framework</li>
 *    <li> UIKit.framework</li>
 *  </ul>
 */
@interface EventTracker : NSObject

/**
 *  Configures the tracker for the given application.
 *
 *  @param apiKey     Your application's API key
 *  @param appDomain  the domain of the application (ie com.companynae). This should be your bundle identifier
 *  @param appName    The name of your application
 *  @param appVersion The version of your application
 */
+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion __deprecated;


/**
 *  Configures the tracker for the given application.
 *
 *  @param apiKey     Your application's API key
 *  @param appDomain  the domain of the application (ie com.companynae). This should be your bundle identifier
 *  @param appName    The name of your application
 *  @param appVersion The version of your application
 *  @param isProd Bool saying if the application is pointed to the production urls or not.
 */
+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion isProduction:(BOOL) isProd;

/**
 *  Configures the tracker for the given application.
 *
 *  @param apiKey     Your application's API key
 *  @param appDomain  the domain of the application (ie com.companynae). This should be your bundle identifier
 *  @param appName    The name of your application
 *  @param appVersion The version of your application
 *  @param isProd Bool saying if the application is pointed to the production urls or not.
 */
+ (void) initializeWithApiKey:(NSString *) apiKey appDomain:(NSString *) appDomain appName:(NSString *) appName appVersion:(NSString *) appVersion isProduction:(BOOL) isProd latitude:(float) latitude longitude:(float) longitude;

/**
 * This method should be called when the application resumes from the background.  It performs another check to
 * see if the user's location changed.
 */
+ (void) applicationDidBecomeActive;

/**
 *  This method is used to track a play event. It's meant to be called when a user plays a video.
 *
 *  @param refID                        the id of the video being played
 *  @param apiSessionID                 this should be retrieved from the server and is used to track a single playback session
 *  @param streaming                    a boolean value that is true when the video is being streamed from the web vs played from cache
 *  @param seconds                      the number of seconds that the video was viewed
 *  @param mediaEngagementOver75Percent set to true only if the video was played over 75%
 */
+ (void) trackPlayEventWithRefID:(NSString *) refID apiSessionID:(NSString *) apiSessionID streaming:(BOOL) streaming mediaViewTimeInSeconds:(float) seconds mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent;

/**
 *  This method is used to track a play event. It's meant to be called when a user plays a video.
 *
 *  @param refID                        the id of the video being played
 *  @param apiSessionID                 this should be retrieved from the server and is used to track a single playback session
 *  @param streaming                    a boolean value that is true when the video is being streamed from the web vs played from cache
 *  @param seconds                      the number of seconds that the video was viewed
 *  @param mediaEngagementOver75Percent set to true only if the video was played over 75%
 *  @param extraParams                  nsdictionary to hold any of these key/value pairs:
                                          key: @"appScreen" value: a string that displays the screen the video was streamed from
                                          key: @"subtitleLanguageId" value: a string of the last subtitle's language Id used
                                          key: @"mediaComponentId" value: a string of the media's component id
                                          key: @"languageId" value: string of the media's language id
 */
+ (void) trackPlayEventWithRefID:(NSString *) refID apiSessionID:(NSString *) apiSessionID streaming:(BOOL) streaming mediaViewTimeInSeconds:(float) seconds mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent extraParams:(NSDictionary *)extraParams;


+ (void) trackPlayEventWithRefID:(NSString *) refID apiSessionID:(NSString *) apiSessionID streaming:(BOOL) streaming mediaViewTimeInSeconds:(float) seconds mediaEngagementOver75Percent:(BOOL) mediaEngagementOver75Percent extraParams:(NSDictionary *)extraParams customParams:(NSDictionary *)customParams;


/**
 * This method is used to track a share event. It;s meant to be called when a user shares a video.
 *
 * @param shareMethod                 the method that the video was shared. (Email, Facebook, Twitter, Bluetooth 3GP, Embed URL Copy)
 * @param refID                       the id of the video being played
 * @param apiSessionID                this should be retrieved from the server and is used to track a single playback session
 */
+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod refID:(NSString *) refID apiSessionID:(NSString *) apiSessionID;

+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod
                                  refID:(NSString *) refID
                           apiSessionID:(NSString *) apiSessionID
                            extraParams:(NSDictionary *)extraParams
                           customParams: (NSDictionary*)customParams;


/**
 * This method is used to track a share event. It;s meant to be called when a user shares a video.
 *
 * @param shareMethod                 the method that the video was shared. (Email, Facebook, Twitter, Bluetooth 3GP, Embed URL Copy)
 * @param refID                       the id of the video being played
 * @param apiSessionID                this should be retrieved from the server and is used to track a single playback session
 * @param extraParams                 nsdictionary to hold any of these key/value pairs:
                                      key: @"mediaComponentId" value: a string of the media's component id
                                      key: @"languageId" value: string of the media's language id
 */
+ (void) trackShareEventFromShareMethod:(NSString *) shareMethod
                                  refID:(NSString *) refID
                           apiSessionID:(NSString *) apiSessionID
                            extraParams:(NSDictionary *)extraParams;

/**
 * Singleton reference so that there only ever exists one event tracker. Make sure to
 * use this method when intializing and interfacing with the tracker.
 *
 * @return the one and only instance of the event tracker.
 */
+ (instancetype)sharedInstance;

/**
 *  Allows you to control whether EventTracker logs messages to the console
 *
 *  @param loggingEnabled   a boolean value which determine whether or not EventTracker logs messages to the console
 */
+ (void) setLoggingEnabled: (BOOL)loggingEnabled;   // default = NO

/**
 *  Allows you to set the latitude and longitude of the EventTracker
 *
 *  @param latitude   a float value of the current latitude of the device's location
 *  @param longitude   a float value of the current longitude of the device's location
 */
+ (void) setLatitude: (float)latitude longitude: (float)longitude;

/**
 *  Allows you to update the API key for the tracker
 */
@property(nonatomic, readonly) NSString *apiKey;

@end
