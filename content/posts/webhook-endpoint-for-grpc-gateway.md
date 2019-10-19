---
title: "Webhook Endpoint for grpc-gateway"
date: 2019-10-19T13:50:32+11:00
type: post
tags:
- Go
- gRPC
---

[grpc-gatway](https://github.com/grpc-ecosystem/grpc-gateway) is a protoc plugin that reads protobuf service definitions 
and generates a reverse-proxy server which translates a RESTful HTTP API into gRPC.

Each field in a proto message would normally match to a JSON field:

```proto
message Request {
    id int32 = 1;
    first_name string = 2;
    last_name string = 3;
}
```
```JSON
{
    "id": 123456,
    "first_name": "Roger",
    "last_name": "Chapman"
}
```

However, for a webhook (or other arbitrary data) being POSTed you may just want to pass the raw JSON body to your gRPC handler.

We'll use the example of a [Stripe Webhook](https://stripe.com/docs/webhooks) sending us data for an event.

## Protocol Buffer definition

```proto
service WebhookService {
  rpc StripeWebhook(WebhookRequest) returns (google.protobuf.Empty) {
    option (google.api.http) = {
      post: "/webhook:Stripe"
      body: "raw"  // this mapping is key for this to work
    };
  }
}

message WebhookRequest {
  bytes raw = 1;
}
```

REST options you may have set previously would map the whole request message as the body via `body: *`; but the magic in our example, is that we 
are mapping the `POST body` directly to the `raw` field.

## Custom marshalling

The default marshalling will expect the incoming request body to be `base64` encoded as this is the default for `bytes`. See 
the JSON mapping table in the [proto3 language guide](https://developers.google.com/protocol-buffers/docs/proto3#json) for more details. 

`grpc-gateway` allows you to create custom marshaller for a given MIME type, so we'll use this hook to create our own custom marshaller for our raw JSON body:

```go
var (
  typeOfBytes = reflect.TypeOf([]byte(nil))
  rawJSONMIME = "application/raw-json" // made-up MIME type for our webhook
)

type rawJSONPb struct {
  *gateway.JSONPb
}

func (*rawJSONPb) ContentType() string {
  return rawJSONMIME
}

func (*rawJSONPb) NewDecoder(r io.Reader) runtime.Decoder {
  return runtime.DecoderFunc(func(v interface{}) error {
    raw, err := ioutil.ReadAll(r)
    if err != nil {
      return err
    }
    rv := reflect.ValueOf(v)

    if rv.Kind() != reflect.Ptr {
      return fmt.Errorf("%T is not a pointer", v)
    }

    rv = rv.Elem()
    if rv.Type() != typeOfBytes {
      return fmt.Errorf("Type must be []byte but got %T", v)
    }

    rv.Set(reflect.ValueOf(raw))
    return nil
  })
}
```

Now we can use our new custom marshaller for requests with this new MIME type:

```go
func newRESTServer() *runtime.ServeMux {
  jsonpb := &gateway.JSONPb{
    EmitDefaults: true,
    Indent:       "  ",
    OrigName:     true,
  }

  mux = runtime.NewServeMux(
    runtime.WithMarshalerOption(rawJSONMIME, &rawJSONPb{jsonpb}), // if content-type == "application/raw-json"
    runtime.WithMarshalerOption(runtime.MIMEWildcard, jsonpb),    // all other content-types
    runtime.WithProtoErrorHandler(runtime.DefaultHTTPProtoErrorHandler),
  )
  return mux
}
```

With this custom marshaller, our JSON body (`[]byte`) will now be correctly mapped to the `raw` field of our request message; but only for 
request where the `Content-Type` header is set to "application/raw-json".

## Content-Type middleware

If you control the application that is sending the webhook, you can just make sure that you set the correct `Content-Type` for the 
endpoint to marshal the data correctly. For the Stripe webhook we can't change the `Content-Type` header so we add a simple middleware to catch the route and update 
the `Content-Type`:

```go
func customMIME(h http.Handler) http.Handler {
  return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    if strings.Contains(r.URL.Path, "webhook") {
      r.Header.Set("Content-Type", rawJSONMIME)
    }
    h.ServeHTTP(w, r)
  })
}

func NewServer() {
  // ...
  restHandler = http.NewServeMux()
  restHandler.Handle("/", customMIME(restServer))
  // ...
}
```

## Process webhook data

Now we can process the request just like any other RPC method; but we get the benifit of using the Stripe-Go library to 
do all the heavy lifting for us to unmarshal the JSON payload.

```go
func (a *app) StripeWebhook(ctx context.Context, req *api.WebhookRequest) (*protobuf.Empty, error) {
    md _ := metadata.FromIncomingContext(ctx)

    // https://stripe.com/docs/webhooks/signatures#verify-official-libraries
    endpointSecret := "whsec_...";
    event, _ := webhook.ConstructEvent(req.GetRaw(), md.Get("Stripe-Signature")[0], endpointSecret)

    switch event.Type {
    case "payment_intent.succeeded":
    // ...
    case "payment_method.attached":
    // ...
    // etc
    }

    return &protobuf.Empty{}, nil
}

```
