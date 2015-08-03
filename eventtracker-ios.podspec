#
# Be sure to run `pod lib lint eventtracker-ios.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "eventtracker-ios"
  s.version          = "1.8.9"
  s.summary          = "Arclight engagement tracker for iOS"
  s.description      = "Arclight engagement tracker for iOS for logging engagements"
  s.homepage         = "https://bitbucket.org/arclight/eventtracker-ios"
  s.license          = 'Copyright MBSJ LLC'
  s.source           = { :git => "https://bitbucket.org/arclight/eventtracker-ios.git", :tag => s.version.to_s }
  s.author           = { "Arclight" => "Arclight" }

  s.platform     = :ios, '6.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes'
  s.resource_bundles = {
    'eventtracker-ios' => ['Pod/Assets/*.png']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'UIKit', 'MapKit', 'CoreData'
  s.library = 'sqlite3'

end
