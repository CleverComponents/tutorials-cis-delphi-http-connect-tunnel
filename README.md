# HTTP CONNECT Tunnel Server (Delphi)

This Delphi tutorial demonstrates how to implement an HTTP CONNECT tunnel (proxy) server with Clever Internet Suite. The console host accepts CONNECT requests, opens an outbound TCP connection to the requested target, returns `200 Connection Established`, and relays opaque bytes in both directions.

The primary use case is tunneling HTTPS traffic. After the CONNECT response, the tunnel does not interpret HTTP or terminate TLS.

---

## 🔔 Get Updates

We publish practical integration examples and technical guides for Clever Components products.

If you'd like to receive updates when new tutorials and component examples are released, you can subscribe here:

👉 https://www.clevercomponents.com/home/maillist.asp

---

## Overview

This tutorial shows how to:

- **Accept HTTP CONNECT** on a TCP listener built with `TclTcpServer`
- **Enforce a simple allowlist** of hosts and ports (empty allowlist denies CONNECT with `403`)
- **Open outbound TCP** to the requested target and complete the CONNECT handshake with `200`
- **Relay opaque bytes** bidirectionally after the tunnel is established
- **Apply practical limits** such as header size, request/connect/idle timeouts, and per-IP connection caps
- **Drive the server from INI** next to the console executable
- **Verify behavior** with DUnitX tests (`TclHttp` client through the local proxy)

## Features

- Console host: `CleverHttpTunnel` (default listen port `8080`)
- Shared library units: `TclHttpTunnelServer`, `TclHttpTunnelConfig`
- Allowlist: `AllowedHosts` + `AllowedPorts` (both required; empty either → deny)
- Optional INI `LocalBinding` (omit/empty = listen on all interfaces)
- Timeouts and status codes: `408` / `431` / `502` / `504` / `503` (and `400` / `403` / `405` as applicable)
- Per-IP concurrent connection limit (`MaxConnectionsPerIP`) and dedicated relay thread pool
- Sample config: `config/CleverHttpTunnel.ini.example`
- Automated tests: `run_tests.bat` (Win32 Debug by default)

## Limitations

This example is intended to demonstrate HTTP CONNECT tunneling, primarily for HTTPS traffic. It does not support TCP half-close: when either endpoint closes the connection or a socket error occurs, both sides of the tunnel are terminated.

Pending outgoing data may be discarded during connection termination. The example is not intended to provide all the connection-management guarantees of a production-grade TCP proxy.

Additional tutorial constraints:

- **IPv4 only**
- **No proxy authentication** (no Basic / NTLM / …)

## Prerequisites

Before running this tutorial, ensure you have:

1. **Clever Internet Suite** (version 12 or compatible) installed
2. **Delphi / RAD Studio** with DUnitX available for the test project
3. Windows compatible operating system

**Note:** This repository ships Delphi project files (`.dproj` / `.dpr`) for **Delphi 11**. The same sources can be compiled and used with other supported Delphi versions (open the `.dpr` or upgrade/recreate the `.dproj` as needed for your IDE).

Add the Clever Internet Suite source/units path to the Delphi **Library Path** (or equivalent search path). Project files intentionally do **not** embed machine-local CIS paths.

## Compilation Instructions

1. Clone the repository from [GitHub/CleverComponents/tutorials-cis-delphi-http-connect-tunnel](https://github.com/CleverComponents/tutorials-cis-delphi-http-connect-tunnel)
2. Download and install [Clever Internet Suite](https://www.clevercomponents.com/downloads/inetsuite/suitedownload.asp)
3. Configure the Delphi Library Path so CIS units (for example `clTcpServer`, `clHttp`, `clSocket`) resolve
4. Open `src/projects/D113/CleverHttpTunnel.dproj` in the Delphi IDE and build
5. Optional: open `test/projects/D113/Test.dproj`, or run `run_tests.bat` from the repository root

`run_tests.bat` calls `rsvars.bat` from a default RAD Studio install path (`C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat`). Edit that path in `run_tests.bat` to match your actual RAD Studio / Delphi installation before running the tests.

```bat
run_tests.bat
```

Optional Win64 test build:

```bat
run_tests.bat win64
```

## Usage

1. Copy `config/CleverHttpTunnel.ini.example` beside `CleverHttpTunnel.exe` as `CleverHttpTunnel.ini`
2. Edit `[Allowlist]` `Hosts` / `Ports` for the destinations you want to permit (empty values refuse start)
3. Start the console host
4. Point an HTTP client that supports CONNECT (for example `TclHttp` with `ProxySettings`, or another HTTPS client configured to use an HTTP proxy) at `http://127.0.0.1:8080`

Example allowlist for a single HTTPS host:

```ini
[Server]
Port=8080

[Allowlist]
Hosts=example.com
Ports=443
```

## Project Structure

```text
/src
  clHttpTunnelServer.pas
  clHttpTunnelConfig.pas
  /projects/D113
    CleverHttpTunnel.dpr
    CleverHttpTunnel.dproj
/test
  clHttpTunnelServerTests.pas
  /projects/D113
    Test.dpr
    Test.dproj
/config
  CleverHttpTunnel.ini.example

run_tests.bat
LICENSE
README.md
```

`projects/D113` is the Delphi 11 project port. Additional Delphi version ports may be added later under `projects/`.

## Components Used

### Clever Internet Suite

- **`TclTcpServer` / `TclUserConnection`**: inbound CONNECT listener and client connection
- **`TclTcpClientConnection`**: outbound TCP to the CONNECT target
- **`TclThreadPool`**: dedicated relay worker pool
- **`TclHttp` / proxy settings**: used by DUnitX tests to exercise CONNECT through the local tunnel

## Related Examples

- [Custom TCP Client / Server](https://github.com/CleverComponents/Clever-Internet-Suite-Tutorials/tree/master/vcl/CustomTcp): custom TCP protocols with Clever Internet Suite
- [HttpClientProxy](https://github.com/CleverComponents/Clever-Internet-Suite-Examples/tree/master/Delphi/HttpClientProxy): HTTP client using a proxy
- [Http-Server](https://github.com/CleverComponents/Http-Server): multithreaded HTTP server component built on CIS sockets / thread pool

## Repository

The [GitHub/CleverComponents/tutorials-cis-delphi-http-connect-tunnel](https://github.com/CleverComponents/tutorials-cis-delphi-http-connect-tunnel) repository contains this HTTP CONNECT tunnel tutorial.

For a broader set of Clever Internet Suite samples, see also [Clever-Internet-Suite-Tutorials](https://github.com/CleverComponents/Clever-Internet-Suite-Tutorials) and [Clever-Internet-Suite-Examples](https://github.com/CleverComponents/Clever-Internet-Suite-Examples).

## License

This tutorial is distributed under the MIT License. See the LICENSE file for details.

The MIT License applies only to the tutorial source code and does not cover Clever Internet Suite or other CleverComponents libraries.

Clever Internet Suite is a commercial product and is subject to its own End-User License Agreement.
