
# Developer Guide

```
gem install xcpretty

! sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 
! xcode-select -p
  xcodebuild -scheme WinDock -configuration Release -derivedDataPath build \                                                                    
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet | xcpretty 
./build.sh
```
