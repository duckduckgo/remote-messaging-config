# DuckDuckGo Remote Messaging Configuration
===========================================

## What is it?
This is the configuration repository for the Remote Messaging Framework (RMF). This repository hosts the configuration files that enable the RMF system, remotely controlling messages received and processed by native app clients.


## Folder Structure
Remote Messaging Config is organized as follows:

- /live/: Hosts the configurations for each client.
- /samples/: Contains example configurations.
- /templates/: Provides template files for creating new configurations.

# Remote Config URLs
- Native apps using the Remote Messaging Configuration:
    -   [iOS app](https://github.com/duckduckgo/iOS)
        -   Live: [ios-config.json](https://staticcdn.duckduckgo.com/remotemessaging/config/v1/ios-config.json)
    -   [Android app](https://github.com/duckduckgo/Android)
        -   Live: [android-config.json](https://staticcdn.duckduckgo.com/remotemessaging/config/v1/android-config.json)
    -   [Mac app](https://github.com/duckduckgo/macos-browser):
        -   Live: [macos-config.json](https://staticcdn.duckduckgo.com/remotemessaging/config/v1/macos-config.json)
    -   Windows app (in beta, code not yet open source)
        -   Live: [windows-config.json](https://staticcdn.duckduckgo.com/remotemessaging/config/v1/windows-config.json)

## License
DuckDuckGo is distributed under the Apache 2.0 [license](https://github.com/duckduckgo/BrowserServicesKit/blob/main/LICENSE).
