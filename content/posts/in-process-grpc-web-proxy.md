---
title: "In Process gRPC-Web Proxy"
date: 2019-07-26T17:11:06+10:00
type: post
---

From the offical [gRPC-Web](https://github.com/grpc/grpc-web) docs:

> "gRPC-Web clients connect to gRPC services via a special gateway proxy: the current version of the library uses Envoy by default, in which gRPC-Web support is built-in."

For production we can just enable the `envoy.grpc_web` filter and we are good to go.

But for development I wanted to create a gRPC server that engineers could install via a single binary and not have to run anything extra (like envoy running in docker).
## gRPC-Web Wrapper
Prior to the release of the offical gRPC-Web implementation the good guys at Improbable Engineering had created there own version of gRPC-Web and also have a [`grpcweb`](https://github.com/improbable-eng/grpc-web/tree/master/go/grpcweb) pacakge that implements the gRPC-Web spec as a wrapper around a gRPC-Go Server.

Turns out that, with a little extra configuration, it can be made compatible with the offical gRPC-Web client:
```go
grpcServer := grpc.Server()
grpcWebServer := grpcweb.WrapServer(grpcServer)

httpServer = &http.Server{
    Handler: h2c.NewHandler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if r.ProtoMajor == 2 {
            grpcWebServer.ServeHTTP(w, r)
        } else {
            w.Header().Set("Access-Control-Allow-Origin", "*")
            w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
            w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, X-User-Agent, X-Grpc-Web")
            w.Header().Set("grpc-status", "")
            w.Header().Set("grpc-message", "")
            if grpcWebServer.IsGrpcWebRequest(r) {
                grpcWebServer.ServeHTTP(w, r)
            }
        }
    }), &http2.Server{}),
}
```
**Note:** Were also using the `golang.org/x/net/http2/h2c` package to allow HTTP/2 over cleartext as we are also listening for HTTP/1.1 requests on the same port without TLS. This is not recomended for production, but means we don't require certificates during development.
## Debugging gRPC-Web on the wire
For our frontend engineers they rely on chrome devtools to view newtwork traffic, but for gRPC-Web it appears as a base64 string; not very useful. 

So we created [gRPC-Web Dev Tools](https://github.com/SafetyCulture/grpc-web-devtools) a network like extension for Chrome that alows you to view the gRPC-Web requests and responses de-serialized to JSON objects; much better:

![gRPC-Web Dev Tools](/posts/img/grpc-web-devtools.png)

