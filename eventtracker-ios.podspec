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
  s.version          = "0.1.1"
  s.summary          = "A short description of eventtracker-ios."
  s.description      = <<-DESC
                       An optional longer description of eventtracker-ios

                       * Markdown format.
                       * Don't worry about the indent, we strip it!
                       DESC
  s.homepage         = "https://bitbucket.org/arclight/eventtracker-ios"
  s.license          = 'Copyright MBSJ LLC'
  s.source           = { :git => "git@bitbucket.org:arclight/eventtracker-ios.git", :tag => s.version.to_s }


  s.platform     = :ios, '6.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes'
  s.resource_bundles = {
    'eventtracker-ios' => ['Pod/Assets/*.png']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  s.frameworks = 'UIKit', 'MapKit', 'CoreData'
  s.dependency 'sqlite3'

end
