---
title: "Running Go Code on iOS and Android"
date: 2020-09-14T14:51:26+10:00
type: post
tags:
- Go
- Mobile
- iOS
- Android
---

In this tutorial we'll be building a simple Go package that you can run from an iOS application (Swift) and also an
Android application (Kotlin).

This tutorial does **NOT** use the [Go Mobile](https://github.com/golang/mobile)
framework; instead it uses Cgo to build the raw static (iOS) and shared (Android) C library that can be imported into your
mobile project (which is what the Go Mobile framework does under-the-hood).

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

```zsh
$ mkdir -p android ios go/cmd/libfoo go/foo
```

We'll start with the Go code and come back to creating the iOS and Android projects later.

```zsh
$ cd go
$ go mod init rogchap.com/libfoo
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

# go/clangwrap.sh

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
// ios/foobar/ContentView.swift

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
// ios/foobar/foobar-Bridging-Header.h

#import "foo.h"
```

In Xcode `Build Settings`, under `Swift Compiler - General` set the `Objective-C Bridging Header` to the file we just
created: `foobar/foobar-Bridging-Header.h`.

We also need to set the `Library Search Paths` to include the directory of our generated header file `foo.h`.
(Xcode may have done this for you when you drag-and-drop the files into the project).

We can now call our function from Swift, then build and run:

```swift
// ios/foobar/ContentView.swift

Button("Reverse"){
    let str = reverse(UnsafeMutablePointer<Int8>(mutating: (self.txt as NSString).utf8String))
    self.txt = String.init(cString: str!, encoding: .utf8)!
    // don't forget to release the memory to the C String
    str?.deallocate()
}
```

![libfoo ios app](/posts/img/libfoo_ios.gif)

# Creating the Android application

Using Android Studio, we will create a new Android project. From the Project Templates select `Native C++`, which will
create a project with an Empty Activity that is configured to use the Java Native Interface (JNI). We will still select
`Kotlin` as our language of choice for the project.

After creating a simple Activity with a `EditText` and `Button` we create the basic functionality for our app:

```kotlin
// android/app/src/main/java/com/rogchap/foobar/MainActivity.kt

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
// android/app/src/main/cpp/native-lib.cpp

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
(and easiest) is to place our outputted library into a special `jniLibs` folder that is copied into our final APK file.

Rather than creating a Fat binary (as we did for iOS) we are going to place each architecture in the correct folder.
Again, for the JNI, conventions matter.

```make
// go/Makefile

ANDROID_OUT=../android/app/src/main/jniLibs
ANDROID_SDK=$(HOME)/Library/Android/sdk
NDK_BIN=$(ANDROID_SDK)/ndk/21.0.6113669/toolchains/llvm/prebuilt/darwin-x86_64/bin

android-armv7a:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=arm \
	GOARM=7 \
	CC=$(NDK_BIN)/armv7a-linux-androideabi21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/armeabi-v7a/libfoo.so ./cmd/libfoo

android-arm64:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=arm64 \
	CC=$(NDK_BIN)/aarch64-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/arm64-v8a/libfoo.so ./cmd/libfoo

android-x86:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=386 \
	CC=$(NDK_BIN)/i686-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/x86/libfoo.so ./cmd/libfoo

android-x86_64:
	CGO_ENABLED=1 \
	GOOS=android \
	GOARCH=amd64 \
	CC=$(NDK_BIN)/x86_64-linux-android21-clang \
	go build -buildmode=c-shared -o $(ANDROID_OUT)/x86_64/libfoo.so ./cmd/libfoo

android: android-armv7a android-arm64 android-x86 android-x86_64
```

**Note** Make sure you set the correct location for your Android SDK and the version of the NDK you have downloaded.

Running `make android` will now build all the shared libraries we need into the correct folder. We now need to add our
library to CMake:

```cmake
// android/app/src/main/cpp/CMakeLists.txt

// ...

add_library(lib_foo SHARED IMPORTED)
set_property(TARGET lib_foo PROPERTY IMPORTED_NO_SONAME 1)
set_target_properties(lib_foo PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${CMAKE_ANDROID_ARCH_ABI}/libfoo.so)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${CMAKE_ANDROID_ARCH_ABI}/)

// ...

target_link_libraries(native-lib lib_foo ${log-lib})
```

It took me a while to figure out these settings, once again, naming matters so was important to name the library with
`lib_xxxx` and also set the property `IMPORTED_NO_SONAME 1` otherwise your apk will be looking for your library in the
wrong place.

We can now hookup our JNI code to our Go library, cross our fingers, and run our app:

```cpp
// android/app/src/main/cpp/native-lib.cpp

#include "libfoo.h"

extern "C" {
    jstring
    Java_com_rogchap_foobar_MainActivity_reverse(JNIEnv* env, jobject, jstring str) {
        const char* cstr = env->GetStringUTFChars(str, 0);
        char* cout = reverse(const_cast<char*>(cstr));
        jstring out = env->NewStringUTF(cout);
        env->ReleaseStringUTFChars(str, cstr);
        free(cout);
        return out;
    }
}
```

![libfoo android app](/posts/img/libfoo_android.gif)

## Conclusion

One of Go's strengths is that it's cross-platform; but that doesn't just mean Window, Mac and Linux, Go can target many
other architectures including iOS and Android. Now you have another option in your toolbelt to create shared libraries
that run on server, your mobile apps and maybe even web (via web assembly).

All the code for this tutorial, is available on GitHub: [rogchap/libfoo](https://github.com/rogchap/libfoo)

Looking forward to hearing about the new killer app that you build with Go.
