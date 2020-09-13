---
title: "Running Go Code on iOS and Android"
date: 2020-08-30T14:51:26+10:00
type: post
tags:
- Go
- Mobile
draft: true
---

In this tutorial we'll be building a simple Go package that you can run from an iOS application (Swift) and also an
Android application (Kotlin).

This tutorial does **NOT** use the [Go Mobile](https://github.com/golang/mobile)
framework; instead it uses Cgo to build a static (iOS) and shared (Android) C library that can be imported into your
mobile project.

## Setup

For this tutorial we'll create a simple monorepo with the following structure:

```
.
├── android/
├── go/
│   ├── cmd/
│   │   └── libfoo/
│   │       └── main.go
│   ├── foo/
│   │   └── foo.go
│   ├── go.mod
│   └── go.sum
└── ios/
```

```
mkdir -p android ios go/cmd/libfoo go/foo
```

We'll start with the Go code and come back to creating the iOS and Android projects later.

```
cd go
go mod init rogchap.com/libfoo
```

## Foo package

```go
// go/foo/foo.go
package foo

// Reverse reverses the given string by each utf8 character
func Reverse(in string) string {
    n := 0
    rune := make([]rune, len(in))
    for _, r := range in { 
        rune[n] = r
        n++
    } 
    rune = rune[0:n]
    for i := 0; i < n/2; i++ { 
        rune[i], rune[n-1-i] = rune[n-1-i], rune[i] 
    } 
    return string(rune)
}
```

Our `foo` package has a single function `Reverse` that has a single string argument `in` and a single string output.

## Export for C

In order for our C library to call our `foo` package we need to export all the functions that we want to expose to C
with the special `export` comment.
This wrapper needs to be in the `main` package:

```go
// go/cmd/libfoo/main.go
pacakge main

import "C"

// other imports should be seperate from the special Cgo import
import (
    "rogchap.com/libfoo/foo"
)

//export reverse
func reverse(in *C.char) *C.char {
    return C.CString(foo.Reverse(C.GoString(in)))
}

func main() {}
```

We're using the special `C.GoString()` and `C.CString()` functions to convert between Go string and a C string.

*Note:* The function that we are exporting does not need to be an exported Go function (ie. starts with a Captial
letter). Also note the empty `main` function; this is required for the Go code to compile otherwise you'll get a
`function main is undeclared in the main package` error.

Lets test our build by creating a static C library using the Go `-buildmode` flag:

```
go build -buildmode=c-archive -o foo.a ./cmd/libfoo
```

This should have outputed the C library: `foo.a` and the header file: `foo.h`. You should see our exported
function at the bottom of our header file:

```C
extern char* reverse(char* in);
```

## Building for iOS

Our goal is to create a [fat binary](https://en.wikipedia.org/wiki/Fat_binary) that can be used on iOS devices and the
iOS simulator.

The Go standard library includes a script for building for iOS:
[`$GOROOT/misc/ios/clangwrap.sh`](https://golang.org/misc/ios/clangwrap.sh), however this script only builds for
`arm64`, and we need `x86_64` too for the iOS Simulator. So, we're going to create our own `clangwrap.sh`:

```sh
#!/bin/sh

SDK_PATH=`xcrun --sdk $SDK --show-sdk-path`
CLANG=`xcrun --sdk $SDK --find clang`

if [ "$GOARCH" == "amd64" ]; then
    CARCH="x86_64"
elif [ "$GOARCH" == "arm64" ]; then
    CARCH="arm64"
fi

exec $CLANG -arch $CARCH -isysroot $SDK_PATH -mios-version-min=10.0 "$@"
```
Don't forget to make it executable:
```
chmod +x clangwrap.sh
```

Now we can build our library for each architecture and combine into a fat binary using the `lipo` tool (via a Makefile):

```make
# go/Makefile

ios-arm64:
	CGO_ENABLED=1 \
	GOOS=darwin \
	GOARCH=arm64 \
	SDK=iphoneos \
	CC=$(PWD)/clangwrap.sh \
	CGO_CFLAGS="-fembed-bitcode" \
	go build -buildmode=c-archive -tags ios -o $(IOS_OUT)/arm64.a ./cmd/libfoo

ios-x86_64:
	CGO_ENABLED=1 \
	GOOS=darwin \
	GOARCH=amd64 \
	SDK=iphonesimulator \
	CC=$(PWD)/clangwrap.sh \
	go build -buildmode=c-archive -tags ios -o $(IOS_OUT)/x86_64.a ./cmd/libfoo

ios: ios-arm64 ios-x86_64
	lipo $(IOS_OUT)/x86_64.a $(IOS_OUT)/arm64.a -create -output $(IOS_OUT)/foo.a
	cp $(IOS_OUT)/arm64.h $(IOS_OUT)/foo.h
```

## Create our iOS Application

Using XCode we can create a simple single page application. I'm going to use Swift UI, but it is just as easy to do with
UIKit:

```swift
struct ContentView: View {

    @State private var txt: String = ""

    var body: some View {
        VStack{
            TextField("", text: $txt)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Reverse"){
                // Reverse text here
            }
            Spacer()
        }
        .padding(.all, 15)
    }
}
```

In XCode we can drag-and-drop our newly generated `foo.a` and `foo.h` into our project. For our Swift code to
interop with our library we need to create a bridging header:

```c
// foobar-Bridging-Header.h

#import "foo.h"
```

In Xcode `Build Settings`, under `Swift Compiler -General` set the `Objective-C Bridging Header` to the file we just
created: `foobar/foobar-Bridging-Header.h`.

We also need to set the `Library Search Paths` to include the directory of our generated header file `foo.h`.
(Xcode may have done this for you when you drag-and-drop the files into the project).

We can now call our function from Swift:

```swift
Button("Reverse"){
    let str = reverse(UnsafeMutablePointer<Int8>(mutating: (self.txt as NSString).utf8String))
    self.txt = String.init(cString: str!, encoding: .utf8)!
    // don't forget to release the memory to the C String
    str?.deallocate()
}
```

# Creating the Android application

Using Android Studio, we will create a new Android project. From the Project Templates select `Native C++`, which will
create a project with an Empty Activity that is configured to use the Java Native Interface (JNI). We will still select
`Kotlin` as our language of choice for the project.

After creating a simple Activity with a `EditText` and `Button` we create the basic functionality for our app:

```kotlin
// MainActivity.kt

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btn.setOnClickListener {
            txt.setText(reverse(txt.text.toString()))
        }
    }

    /**
     * A native method that is implemented by the 'native-lib' native library,
     * which is packaged with this application.
     */
    private external fun reverse(str: String): String

    companion object {
        // Used to load the 'native-lib' library on application startup.
        init {
            System.loadLibrary("native-lib")
        }
    }
}
```

We created (and called) and external function `reverse` that we need to implement in the JNI (C++):

```cpp
// native-lib.cpp

extern "C" {
    jstring
    Java_com_rogchap_foobar_MainActivity_reverse(JNIEnv* env, jobject, jstring str) {
        // Reverse text here 
        return str;
    }
}
```

The JNI code has to follow the conventions to interop correctly between the Native C++ and Kotlin (JVM).

## Build for Android

The way the JNI works with external libraries has changed over the many releases of Android and the NDK. The current
(and easiest) is to place out outputed library into a special `jniLibs` folder that is copied into our final APK file.

Rather than creating a Fat binary (as we did for iOS) we are going to place each archatecture in the correct folder.
Again, for the JNI conventions matter.

```
// Makefile


```
