---
title: "Demystify Go's Empty Interface"
date: 2019-10-06T14:03:20+11:00
type: post
tags:
- Go
---

One of delights of using the Go programming language is how quickly Engineers can learn and start using the language;
but at the same time, Engineers also "Copy/Paste" without some of the understanding.

Go's empty interface `interface{}` is one such mystery when learning the language; Engineers are happy to use `interface{}` 
to represent any type, but get confused about the `interface` keyword and why it's used.

```
let i:any = 1;          // Typescript
std::any i = 1;         // C++17
Object i = 1;           // Java
var i interface{} = 1   // Go
```

> #### "interface{} says nothing" -- Rob Pike 

## Interface type

Lets start with a regular interface:

```go
type I interface {
	M()
}

type T struct {}

func (t T) M() {}
```

Type `T` has the `M()` method, therfore implements the `I` interface; interfaces are implemented implicitly in Go so there 
is no need explicitly declare that it does so.

## Interface with no methods

If we now change the interface to the following, does type `T` still implement the interface?

```go
type I interface {

}

type T struct {}

func (t T) M() {}
```

For `T` to implement the `I` interface, `T` is required to implement *all* the methods defined in the interface...

> #### "How do you implement zero methods?"

I hope you already know the answer; `T` does implement `I` because it does not need to implement any methods to comply. 
Our final implementation can be reduced to:

```go
type I interface{}
type T struct{}

func main() {
    var a I = &T{}
}
```

## Empty interface

In Go we can delare types inline:

```go
func main() {
    user := struct{
        ID string
        Name string
    }{
        "uuid_1234",
        "Roger",
    }
    fmt.Println(user)
    // output: {uuid_1234 Roger}
}
```

We can also declare an empty struct too:

```go
done := make(chan struct{}, 1)
//...
done <- struct{}{}
```

> #### "All types implement at least zero methods"

This now leads us to the empty interface:

```go
var i interface{} = "x"
```

The empty interface is exactly the same interface `I` that we declared eairler; all types implement at least zero methods 
an therfore can be used to hold any value.
