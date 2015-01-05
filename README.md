# eventtracker-ios


## Usage

To run the example project, clone the repo, and run `pod install` from the Example directory first.


## Requirements

## Private Repo Configuration 

eventracker-ios is available through the [arclight-cocoa-pods](https://bitbucket.org/arclight/arclight-cocoa-pods) Private Pods library. 

To use the eventracker-ios pod you will need to add the arclight-cocoa-pods pods private repo to your cocoapods setup.

To add the Private Repo to your CocoaPods installation, run the following:

	pod repo add arclight-cocoa-pods https://bitbucket.org/arclight/arclight-cocoa-pods


## Install

To install
it, simply add the following lines to your Podfile:

at the top: 

	source 'https://bitbucket.org/arclight/arclight-cocoa-pods'

and with your other pods:

    pod "eventtracker-ios"

also if you would like to keep eventtracker-ios updated you can simply include it like this in your podfile and "pod update" will always pull down the latest 1.8.x version. 

	pod 'eventtracker-ios', '~> 1.8.3'