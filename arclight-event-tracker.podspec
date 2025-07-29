Pod::Spec.new do |s|
  s.name             = "arclight-event-tracker"
  s.version          = "1.20.0"
  s.summary          = "Arclight engagement tracker for iOS"
  s.description      = "Arclight engagement tracker for iOS for logging engagements"
  s.homepage         = "https://github.com/JesusFilm/arclight-event-tracker"
  s.license          = 'Copyright MBSJ LLC'
  s.source           = { :git => "https://github.com/JesusFilm/arclight-event-tracker.git", :tag => s.version.to_s }
  s.author           = { "Arclight" => "Arclight" }

  s.platform     = :ios, '12.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes'

  s.frameworks = 'UIKit', 'MapKit', 'CoreData'
  s.library = 'sqlite3'
end
