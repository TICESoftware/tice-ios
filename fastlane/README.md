fastlane documentation
================
# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```
xcode-select --install
```

Install _fastlane_ using
```
[sudo] gem install fastlane -NV
```
or alternatively using `brew install fastlane`

# Available Actions
## iOS
### ios tests
```
fastlane ios tests
```
Run tests
### ios lint
```
fastlane ios lint
```
Run linter
### ios pr
```
fastlane ios pr
```
Prepare merge request
### ios download_provisioning_profiles
```
fastlane ios download_provisioning_profiles
```
Download provisioning profiles
### ios deployAdHoc
```
fastlane ios deployAdHoc
```
Deploy ad-hoc testing
### ios preview
```
fastlane ios preview
```
Trigger Preview
### ios updateAppVersion
```
fastlane ios updateAppVersion
```
Update App Version
### ios getAppVersion
```
fastlane ios getAppVersion
```
Get App Version
### ios buildPreview
```
fastlane ios buildPreview
```
Build Preview
### ios deliverPreview
```
fastlane ios deliverPreview
```
Deliver Preview
### ios release
```
fastlane ios release
```
Trigger Release
### ios buildRelease
```
fastlane ios buildRelease
```
Build Release
### ios deliverRelease
```
fastlane ios deliverRelease
```
Deliver Release
### ios bumpVersion
```
fastlane ios bumpVersion
```
Bump version
### ios style_screenshots
```
fastlane ios style_screenshots
```
Style screenshots

----

This README.md is auto-generated and will be re-generated every time [fastlane](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of fastlane can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
