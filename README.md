# Arclight Event Tracker

A CocoaPods library for tracking video play and share events for Arclight Videos in iOS applications.

## Requirements

- iOS 12.0+
- Xcode 8.0+
- The following frameworks must be linked to your project:
  - `libsqlite3.0.dylib`
  - `CoreLocation.framework`
  - `UIKit.framework`

## Install

To install arclight-event-tracker, simply add the following line to your Podfile:

	pod 'arclight-event-tracker'

If you would like to keep arclight-event-tracker updated you can simply include it like this in your podfile and "pod update" will always pull down the latest 1.20.x version. 

	pod 'arclight-event-tracker', '~> 1.20.0'

## How to Use

### 1. Import the Header

```objc
#import "EventTracker.h"
```

### 2. Initialize the Tracker

In your `AppDelegate.m`, initialize the tracker with your API key and app information:

```objc
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSString *appVersionString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    // Initialize tracker
    [EventTracker initializeWithApiKey:@"YOUR_API_KEY"
                             appDomain:@"com.yourcompany.appname"
                               appName:@"Your App Name"
                            appVersion:appVersionString
                         isProduction:YES
                       trackLocation:YES];
    
    return YES;
}
```

**Parameters:**
- `apiKey`: Your application's API key
- `appDomain`: Your app's bundle identifier (e.g., "com.companyname.appname")
- `appName`: The name of your application
- `appVersion`: The version of your application
- `isProduction`: Set to `YES` for production, `NO` for staging
- `trackLocation`: Set to `YES` to track user location, `NO` to disable

### 3. Track Play Events

Call this method when a user plays a video:

```objc
[EventTracker trackPlayEventWithRefID:@"video_id_123"
                         apiSessionID:@"session_id_456"
                            streaming:YES
               mediaViewTimeInSeconds:120.0
         mediaEngagementOver75Percent:YES];
```

**Parameters:**
- `refID`: The unique identifier of the video being played
- `apiSessionID`: Session ID retrieved from your server for tracking playback sessions
- `streaming`: `YES` if video is streamed from web, `NO` if played from cache
- `mediaViewTimeInSeconds`: Number of seconds the video was viewed
- `mediaEngagementOver75Percent`: `YES` if video was played over 75%, `NO` otherwise

### 4. Track Play Events with Extra Parameters

For more detailed tracking, you can include additional parameters:

```objc
NSDictionary *extraParams = @{
    @"appScreen": @"VideoPlayerScreen",
    @"subtitleLanguageId": @"en",
    @"mediaComponentId": @"component_123",
    @"languageId": @"en"
};

[EventTracker trackPlayEventWithRefID:@"video_id_123"
                         apiSessionID:@"session_id_456"
                            streaming:YES
               mediaViewTimeInSeconds:120.0
         mediaEngagementOver75Percent:YES
                          extraParams:extraParams];
```

### 5. Track Share Events

Track when users share videos:

```objc
[EventTracker trackShareEventFromShareMethod:kShareMethodFacebook
                                      refID:@"video_id_123"
                               apiSessionID:@"session_id_456"];
```

**Available Share Methods:**
- `kShareMethodTwitter` - Twitter sharing
- `kShareMethodEmail` - Email sharing
- `kShareMethodFacebook` - Facebook sharing
- `kShareMethodBlueTooth3GP` - Bluetooth 3GP sharing
- `kShareMethodEmbedURL` - Embed URL copying

### 6. Handle App Lifecycle

Call this method when your app becomes active to check for location changes:

```objc
- (void)applicationDidBecomeActive:(UIApplication *)application
{
    [EventTracker applicationDidBecomeActive];
}
```

### 7. Optional Configuration

Enable logging for debugging:

```objc
[EventTracker setLoggingEnabled:YES];
```

Set custom location coordinates:

```objc
[EventTracker setLatitude:37.7749 longitude:-122.4194];
```

## Example

See the `Example/` directory for a complete working example of how to integrate the EventTracker into your iOS application.

## Development

To run the example project:

 clone the repo, and run `pod install` from the Example directory first.

## Releasing

This project uses automated releases via GitHub Actions. To release a new version:

### 1. Update Version

Update the version in `arclight-event-tracker.podspec`:

```ruby
s.version = "1.20.1"  # Change to your new version
```

### 2. Update Changelog (Optional)

Document your changes in `CHANGELOG.md` file or update the release notes.

### 3. Commit and Tag

```bash
# Add your changes
git add .

# Commit with a descriptive message
git commit -m "Release v1.20.1"

# Create and push the tag
git tag v1.20.1
git push origin main
git push origin v1.20.1
```

### 4. Automated Release

Once you push the tag, GitHub Actions will automatically:

- ✅ Validate that the podspec version matches the git tag
- ✅ Run RuboCop to check code style
- ✅ Validate the podspec with `pod lib lint`
- ✅ Publish to CocoaPods Trunk

### 5. Verify Release

Check that your release was successful:

- **GitHub Actions**: Check the Actions tab for successful completion
- **CocoaPods**: Verify the new version appears on [CocoaPods.org](https://cocoapods.org/?q=arclight-event-tracker)

### Prerequisites

Before releasing, ensure you have:

1. **Valid Podspec**: Your podspec should pass `pod lib lint` locally
2. **Clean Code**: All RuboCop checks should pass

> **Note**: CocoaPods Trunk Token is already configured as a GitHub secret.

### Version Guidelines

- Use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`
- **MAJOR**: Breaking changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

### Troubleshooting

If the release fails:

1. **Check GitHub Actions logs** for specific error messages
2. **Verify podspec syntax** by running `pod lib lint` locally
3. **Ensure version consistency** between podspec and git tag
4. **Check CocoaPods Trunk Token** is properly configured