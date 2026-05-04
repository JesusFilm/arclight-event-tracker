// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "arclight-event-tracker",
    platforms: [.iOS(.v12)],
    products: [
        .library(
            name: "arclight_event_tracker",
            targets: ["arclight_event_tracker"]
        )
    ],
    targets: [
        .target(
            name: "arclight_event_tracker",
            path: "Pod/Classes",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("UIKit"),
                .linkedFramework("CoreData"),
                .linkedFramework("MapKit"),
                .linkedFramework("CoreLocation"),
            ]
        )
    ]
)
