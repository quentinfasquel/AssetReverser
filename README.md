# AssetReverser

[![CI Status](http://img.shields.io/travis/quentinfasquel/AssetReverser.svg?style=flat)](https://travis-ci.org/quentinfasquel/AssetReverser)
[![Version](https://img.shields.io/cocoapods/v/AssetReverser.svg?style=flat)](http://cocoapods.org/pods/AssetReverser)
[![License](https://img.shields.io/cocoapods/l/AssetReverser.svg?style=flat)](http://cocoapods.org/pods/AssetReverser)
[![Platform](https://img.shields.io/cocoapods/p/AssetReverser.svg?style=flat)](http://cocoapods.org/pods/AssetReverser)

## Example

To run the example project, clone the repo, and open `Example/AssetReverserExample.xcodeproj` with a version of Xcode that supports **Swift 5.0**

## Usage

On iOS 13 +

```swift

let asset = AVURLAsset(url: inputURL) // Your video file URL
let session = AssetReverseSession(asset: asset, outputFileURL: outputURL)
let reversedAsset = try await session.reverse()
```

## Installation

### Using [Swift Package Manager](https://www.swift.org/package-manager/)

```swift
// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "TestProject",
  dependencies: [
    .package(url: "https://github.com/quentinfasquel/AssetReverser", from: "0.0.2")
  ],
  targets: [
    .target(name: "TestProject", dependencies: ["AssetReverser"])
  ]
)
```

### Using [CocoaPods](http://cocoapods.org)

```ruby
# Podfile
use_frameworks!

target 'YOUR_TARGET_NAME' do
    pod 'AssetReverser', '0.0.2'
end
```

### Using [Carthage](https://github.com/Carthage/Carthage)
Add this to `Cartfile`

```
github "quentinfasquel/AssetReverser" "6.5.0"
```

```
$ carthage update
```

## Author

Quentin Fasquel

## License

AssetReverser is available under the MIT license. See the LICENSE file for more info.
