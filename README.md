# AWS Lambda Runtime for Zig
![Zig v0.14 (dev)](https://img.shields.io/badge/Zig-v0.14_(dev)-black?logo=zig&logoColor=F7A41D "Zig v0.14 – master branch")
[![MIT License](https://img.shields.io/github/license/by-nir/aws-lambda-zig)](/LICENSE)

Write _AWS Lambda_ functions in the Zig programming language to achieve blazing fast invocations and cold starts!

[🐣 Quick Start](#quick-start) ·
[📒 Documentation](#documentation) ·
[💽 Demos](#demos)

## Features
- [x] Runtime API
- [ ] Extensions API
- [ ] Telemetry API
- [ ] Structured events
- [x] Response streaming
- [x] CloudWatch & X-Ray integration
- [ ] Lifecycle hooks
- [ ] Dependency injection
- [x] Build system target configuration
- [ ] Managed build step
- [ ] Testing utilities

### Benchmark
Using zig allows creating small and fast functions.<br />
Minimal [Hello World demo](#hello-world) on _`arm64` (256 MiB, Amazon Linux 2023)_:

- ❄️ `~13ms` cold start invocation duration
- ⚡ `~1.5ms` warm invocation duration
- 💾 `12 MB` max memory consumption
- ⚖️ `1.8 MB` function size (zip)


> [!TIP]
> Check out [AWS SDK for Zig](https://github.com/by-nir/aws-sdk-zig) for a
> comprehensive Zig-based AWS cloud solution.

## Quick Start
1. Add a dependency to your project:
    ```console
    zig fetch --save git+https://github.com/by-nir/aws-lambda-zig#0.2.0
    ```
2. Configure the [executable build](#build-script):
    - Named the executable _bootstrap_.
    - Import the Lambda Runtime module.
3. Implement a handler (exmaples: [minimal handler](#minimal-handler), [streaming handler](#streaming-handler)).
4. Build the handler executable for _Linux_ with either _x86_ or _arm_ architecture.<br />
    If you used the library provided [managed architecture target](#build-target) utility, specify the architecture:
    ```console
    zig build --release -Darch=x86
    zig build --release -Darch=arm
    ```
5. Archive the executable into a zip:
    ```console
    zip -qj lambda.zip zig-out/bin/bootstrap
    ```
4. Deploy the zip archive to a Lambda function:
    - Configure it with _Amazon Linux 2023_ or other **OS-only runtime**.
    - Use you prefered deployment method: console, CLI, SAM or any CI solution.

### Build Script
```zig
const std = @import("std");
const lambda = @import("aws-lambda");

pub fn build(b: *std.Build) void {
    // Add an architecture confuration option and resolves a target query.
    const target = lambda.resolveTargetQuery(b, lambda.archOption(b));
    
    // Alternatively, hard-code an architecture.
    // const target = lambda.resolveTargetQuery(b, .arm);

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // Add the handler executable.
    const exe = b.addExecutable(.{
        // Note the executable name must be "bootstrap".
        .name = "bootstrap",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Import the runtime module.
    const runtime = b.dependency("aws-lambda", .{}).module("lambda");
    exe.root_module.addImport("aws-lambda", runtime);
}
```

### Minimal Handler
```zig
const lambda = @import("aws-lambda");

// Entry point for the Lambda function.
pub fn main() void {
    // Bind the handler to the runtime:
    lambda.handle(handler, .{});
}

// Eeach event is processed separetly the handler function.
// The function must have the following signature:
fn handler(
    ctx: lambda.Context,    // Metadata and utilities
    event: []const u8,      // Raw event payload (JSON)
) ![]const u8 {
    return "Hello, world!";
}
```

### Streaming Handler
```zig
const lambda = @import("aws-lambda");

// Entry point for the Lambda function.
pub fn main() void {
    // Bind the handler to the runtime:
    lambda.handleStream(handler, .{});
}

// Eeach event is processed separetly the handler function.
// The function must have the following signature:
fn handler(
    ctx: lambda.Context,    // Metadata and utilities
    event: []const u8,      // Raw event payload (JSON)
    stream: lambda.Stream,  // Response stream
) !void {
    // Start streaming the response for a given content type.
    try stream.open("text/event-stream");

    // Append to the streaming buffer.
    try stream.write("data: Message");
    try stream.writeFmt(" number {d}\n\n", .{1});

    // Publish the buffer to the client.
    try stream.flush();

    // Wait for half a second.
    std.time.sleep(500_000_000);

    // Append to streaming buffer and immediatly publish to the client.
    try stream.publish("data: Message number 2\n\n");
    std.time.sleep(100_000_000);

    // Publish also supports formatting.
    try stream.publishFmt("data: Message number {d}\n\n", .{3});

    // Optionally close the stream.
    try stream.close();
}
```

## Documentation

### Build Target
AWS Lambda provides two architectures for the runtime environment: _x86_64_ and _arm64_ based on _Graviton2_. In order to build the event handler correctly and to squeeze the best performance, the build target must be configured accordingly.

The mananged target resolver sets the operating system, architecture and specific CPU supported features. It can be utilizes in the build script in two forms:

```zig
const std = @import("std");
const lambda = @import("aws-lambda");

pub fn build(b: *std.Build) void {
    // Option A – CLI confuration:
    const arch = lambda.archOption(b);
    const target = lambda.resolveTargetQuery(b, arch);
    
    // Option B – Hard-coded architecture (`.x86` or `.arm`):
    const target = lambda.resolveTargetQuery(b, .arm);

    // ···
}
```

If `lambda.archOption(b)` is used, the configuration option `-Darch=x86|arm` is added (defaults to _x86_).

### Event Handler
The event handler is the entry point for the Lambda function.

The library provides a runtime that handles the event lifecycle and communication with the Lambda’s execution environment. With it, you can focus on imlementing only the meaningful part of processing and responding to the event.

Since the library manages the lifecycle, it expects the handler to have a specific signature. _Note that [response streaming](#response-streaming) has a dedicated lifecycle and handler signature._

```zig
const lambda = @import("aws-lambda");

// Entry point for the Lambda function.
pub fn main() void {
    // Bind the handler to the runtime:
    lambda.handle(handler, .{});
}

// Eeach event is processed separetly the handler function.
// The function must have the following signature:
fn handler(
    ctx: lambda.Context,    // Metadata and utilities
    event: []const u8,      // Raw event payload (JSON)
) ![]const u8 {
    // The handler’s implement should process the `event` payload and return a response payload.
    return switch(payload.len) {
        0 => "Empty payload.",
        else => payload,
    };
}
```

#### Errors & Logging
When a handler returns an error, the runtime will log it to _CloudWatch_ and return an error response to the client.

The runtime exposes a static logging function that can be used to manually log messages to _CloudWatch_. The function follows Zig’s standard logging conventions.

```zig
const lambda = @import("aws-lambda");

lambda.log.err("This error is logged to {s}.", .{"CloudWatch"});
```

> [!WARNING]
> In release mode only _error_ level is preserved, other levels are removed at compile time. This behavior may be overriden at build.

#### Handler Context
The handler signature includes the parameter `ctx: lambda.Context`, it provides metadata and utilities to assist with the processing the event.

The following sections describe the context...

#### Memory Allocation
Since the runtime manages the function and invocation lifecycle, it also owns the memory. The _handler context_ provides two allocators:

| Allocator | Behavior |
| --------- | -------- |
| `ctx.gpa` | You own the memory and **must deallocate it** by the end of the invocation. |
| `ctx.arena` | The memory is tied to the invocation’s lifetime. The runtime will deallocate it on your behalf after the invocation resolves. |

> [!NOTE]
> While `ctx.gpa` may be used to persist data and services between invocations, for such cases consider using [dependency injection](#dependency-injection) or [extensions](#extensions--telemetry).

#### Environment Variables
The functions’ environment variables are mapped by the _handler context_, they can be accesed using the `env(key)` method:

```zig
const foo_value = ctx.env("FOO_KEY") orelse "some_default_value";
```

#### Invocation Metadata
Per-invocation metadata is provided by the _handler context_ `ctx.request` field. It contains the following fields:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `request_id` | `[]const u8` | AWS request ID associated with the request. |
| `xray_trace` | `[]const u8` | X-Ray tracing id. |
| `invoked_arn` | `[]const u8` | The function ARN requested. It may be different in **each invoke** that executes the same version. |
| `deadline_ms` | `u64` | Function execution deadline counted in milliseconds since the _Unix epoch_. |
| `client_context` | `[]const u8` | Information about the client application and device when invoked through the AWS Mobile SDK. |
| `cognito_identity` | `[]const u8` | Information about the Amazon Cognito identity provider when invoked through the AWS Mobile SDK. |

#### Configuration Metadata
Static config metadata is provided by the _handler context_ `ctx.config` field. It contains the following fields:

| Field | Type | Description |
| ----- | ---- | ----------- |
| `aws_region` | `[]const u8` | AWS Region where the Lambda function is executed. |
| `aws_access_id` | `[]const u8` | Access key obtained from the function's [execution role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html). |
| `aws_access_secret` | `[]const u8` | Access key obtained from the function's [execution role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html). |
| `aws_session_token` | `[]const u8` | Access key obtained from the function's [execution role](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html). |
| `func_name` | `[]const u8` | Name of the function. |
| `func_version` | `[]const u8` | Version of the function being executed. |
| `func_size` | `u16` | Amount of memory available to the function in MB. |
| `func_init` | `InitType` | Initialization type of the function. |
| `func_handler` | `[]const u8` | Handler location configured on the function. |
| `log_group` | `[]const u8` | Name of the Amazon CloudWatch Logs group for the function. |
| `log_stream` | `[]const u8` | Name of the Amazon CloudWatch Logs stream for the function. |

### Response Streaming
The runtime supports streaming responses to the client; though implementing a streaming handler differs from the standard handler.

```zig
const lambda = @import("aws-lambda");

// Entry point for the Lambda function.
pub fn main() void {
    // Bind the handler to the runtime:
    lambda.handleStream(handler, .{});
}

// Eeach event is processed separetly the handler function.
// The function must have the following signature:
fn handler(
    ctx: lambda.Context,    // Metadata and utilities
    event: []const u8,      // Raw event payload (JSON)
    stream: lambda.Stream,  // Stream delegate
) !void {
    // Start streaming the response for a given content type.
    try stream.open("text/event-stream");

    // Publish a message to the client.
    try stream.publish("data: Hello, world!\n\n");    
}
```

#### Stream Delegate

Instead of resolving payload by returning from the handler we use the _stream delegate_.

Once a content type is known, the handler should call `stream.open(content_type)` to open the response stream. After the stream is opened you may incrementally append to the response.
_Closing the stream is not required._

| Method | Description |
| ------ | ----------- |
| `stream.open(content_type)` | Opens the response stream with the provided content type. |
| `stream.write(message)` | Appends a message to the response buffer. |
| `stream.writeFmt(format, args)` | Appends a message to the response buffer using Zig’s standard formatting conventions. |
| `stream.flush()` | Publish the buffer to the client. |
| `stream.publish(message)` | Appends a message to the buffer and **immediatly** publish it to the client. |
| `stream.publishFmt(format, args)` | Appends a message to the buffer using Zig’s standard formatting conventions, and **immediatly** publish it to the client. |
| `stream.close()` | Optionally conclude the response stream while continuing to process the event. |
| `stream.closeWithError(err, message)` | Terminate the stream with an error and publish a message to the client. |

### Structured Events
Not yet implemented.

### Lifecycle Hooks
Not yet implemented.

### Dependency Injection
Not yet implemented.

### Extensions & Telemetry
Not yet implemented.

## Demos

### Hello World
Returns a short message.

```console
zig build demo:hello --release -Darch=ARCH_OPTION
```

### Debug
🛑 _Deploy with caution! May expose sensitive data to the public._

Returns the raw payload as-is:
```console
zig build demo:echo --release -Darch=ARCH_OPTION
```

Returns the function’s metadata, environment variables and the event’s raw payload:
```console
zig build demo:debug --release -Darch=ARCH_OPTION
```

### Errors
Immediatly returns an error; the runtime logs the error to _CloudWatch_:
```console
zig build demo:fail --release -Darch=ARCH_OPTION
```

Returns an output larger than the Lambda limit; the runtime logs an error to _CloudWatch_:
```console
zig build demo:oversize --release -Darch=ARCH_OPTION
```

### Response Streaming
👉 _Be sure to configure the function with streaming enabled._

Stream a response to the client and continue execution of the response conclusion:
```console
zig build demo:stream --release -Darch=ARCH_OPTION
```

Stream a response to the client and eventually fail:
```console
zig build demo:stream_throw --release -Darch=ARCH_OPTION
```

## License
The author and contributors are not responsible for any issues or damages caused
by the use of this software, part of it, or its derivatives. See [LICENSE](/LICENSE)
for the complete terms of use.

**_AWS Lambda Runtime for Zig_ is not an official _Amazon Web Services_ software,
nor is it affiliated with _Amazon Web Services, Inc_.**