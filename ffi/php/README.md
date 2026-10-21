# # ez_dbengine PHP FFI Module

This module provides standard PHP FFI bindings and an object-oriented wrapper for the high-performance `ez_dbengine` C-Core engine. It includes both Command-Line Interface (CLI) and Web Dashboard (Web UI) tools for stress testing and integration validation.

---

## 📁 Directory Structure

```text
ffi/php/
├── ez_dbengine.php             # 核心 C-Core FFI SDK
├── ez_stress_master.php        # CLI 壓測
├── README.md                   # 剛剛翻譯完成的英文技術文件
└── saas/                       # SaaS WebAPI 專屬目錄
    ├── config.php              # 常數與目錄設定
    ├── ez_rest.php             # REST 基礎協定類別
    ├── webapi.php              # API 派送控制器 (?request=xxx)
    ├── client_test.php         # cURL 呼叫驗證腳本
    └── library/
        ├── ez_config.php
        ├── ez_language.php
        ├── ez_request.php
        ├── ez_session.php
        └── ez_db_adapter.php   # 常駐單例 EzDBEngine 適配器
```

## ⚙️ Environment Configuration (php.ini)
Invoking native shared libraries via PHP requires enabling the built-in PHP FFI extension.

# Modify php.ini
**Open the system php.ini configuration file and add or uncomment the following directives:**
```text
extension=ffi
ffi.enable = true
```
**Verify FFI status (Execute in Terminal):**
```text
php -r "var_dump(extension_loaded('ffi'));"
# Expected output: Must return bool(true) indicating the environment is ready.
```

## 🚀 Execution & Testing Methods
模式 A：CLI High-Throughput Stress Test

**Suitable for terminal environments to run automated tests and benchmark Transactions Per Second (TPS):**
```text
cd ffi/php
php -d ffi.enable=true -d opcache.enable_cli=1 -d opcache.jit=tracing -d opcache.jit_buffer_size=64M ez_stress_master.php
```

模式 B：Web UI Visualization Dashboard
**Suitable for browser observation of multithreaded partitioned write latency, index construction progress, and real-time dynamic charts:**
* **1. Launch PHP Built-in Web Server:** 
```text
cd ffi/php
php -d ffi.enable=true -d opcache.enable_cli=1 -d opcache.jit=tracing -d opcache.jit_buffer_size=64M -S 0.0.0.0:8080
```
* **2. Access via Browser:** 
```text
http://localhost:8080/ez_stress_master_html.php
        
```
## 💡 Architectural Features
* **Single Source of Truth (Single SDK):** All low-level C structs and function signatures are encapsulated within ez_dbengine.php. Business and test suites directly consume high-level objects without exposing raw pointer semantics.

* **Adaptive Dynamic Library Discovery:** Automatically compatible with Windows (ez_dbengine.dll) and Linux (libez_dbengine.so), performing fallback resolution from the current directory and project build paths.

* **Zero External Dependencies:** Built entirely on the standard native PHP FFI extension without requiring third-party Composer packages

```text

  ez_stress_master.php - Web Edition
  Coupling PHP FFI C-Core Engine with Web Stress Testing Dashboard
  =================================================================
  [System Setup & Execution Guide]
        
  1. Configure php.ini (Enable FFI extension and execution permissions):
     --------------------------------------------------------------
     extension=ffi
     ffi.enable = true
           
  2. Verify FFI activation (Run in Terminal):
     --------------------------------------------------------------
     php -r "var_dump(extension_loaded('ffi'));"   
     # Must output: bool(true)
           
  3. Start Web Server:
     --------------------------------------------------------------
     cd ffi/php
     php -d ffi.enable=true -S localhost:8900
           
  4. Access Dashboard URL:
     --------------------------------------------------------------
     http://localhost:8000/ez_stress_master_html.php
  =================================================================
  
```

## 💡 WebAPI (SaaS) Invocations & Integration Examples

This section provides complete invocation examples designed for direct integration with front-end clients (mobile apps, SPAs, and third-party systems).
In this architecture, API endpoints are dispatched via webapi.php?request=method_name and consume incoming POST JSON payloads.
The following examples demonstrate three standard integration scenarios:

* PHP cURL Client (Microservices / Backend-to-Backend)
* Bash cURL Commands (Terminal Troubleshooting & Automation Scripts)
* Native JavaScript Fetch (Web Front-ends / Mobile Apps)

    * **1. PHP cURL Client Example (client_test.php) Simulates an external backend service making an HTTP POST call to the SaaS Web API powered by ez_dbengine:**


    ```text
    <?php
    /**
    * client_test.php - Example client for ez_dbengine SaaS Web API
    */

    const API_BASE_URL = '[http://192.168.42.128:8900/webapi.php?request=](http://192.168.42.128:8900/webapi.php?request=)';

    /**
    * Generic HTTP POST JSON request handler
    */
    function callWebApi(string $endpoint, array $payload): array {
        $url = API_BASE_URL . $endpoint;
        $jsonBody = json_encode($payload);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonBody),
                'User-Agent: ezLink-Client/1.0'
            ],
            CURLOPT_POSTFIELDS     => $jsonBody,
            CURLOPT_TIMEOUT        => 10,
        ]);

        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error    = curl_error($ch);
        curl_close($ch);

        if ($error) {
            return ['status' => 'error', 'message' => 'cURL Error: ' . $error, 'http_code' => $httpCode];
        }

        $data = json_decode($response, true) ?: [];
        $data['http_code'] = $httpCode;
        return $data;
    }

    echo "=== 1. Test: Retrieve Store Configuration (getstoreconfig) ===\n";
    $resStore = callWebApi('getstoreconfig', [
        'storeid' => 'STORE_001'
    ]);
    print_r($resStore);

    echo "\n=== 2. Test: User Authentication (appuserlogin) ===\n";
    $resLogin = callWebApi('appuserlogin', [
        'storeid'  => 'STORE_001',
        'appid'    => 'APP_BEACON_IOS',
        'account'  => 'bear@ezlink.io',
        'password' => 'ombb3900'
    ]);
    print_r($resLogin);

    echo "\n=== 3. Test: Issue Queue Ticket (appsetcallnumber) ===\n";
    $resTicket = callWebApi('appsetcallnumber', [
        'storeid' => 'STORE_001',
        'account' => 'bear@ezlink.io'
    ]);
    print_r($resTicket);
    ```

    * **2. Bash cURL Command-Line Examples Execute these commands directly in the Linux terminal to verify physical data retrieval through ez_dbengine:**


        **Retrieve Store Configuration (getstoreconfig):**

        ```text
        curl -X POST "[http://192.168.42.128:8900/webapi.php?request=getstoreconfig](http://192.168.42.128:8900/webapi.php?request=getstoreconfig)" \
        -H "Content-Type: application/json" \
        -d '{"storeid": "STORE_001"}'
        ```

        **User Authentication (appuserlogin):**
        ```text
        curl -X POST "http://192.168.42.128:8900/webapi.php?rquest=appuserlogin" \
        -H "Content-Type: application/json" \
        -d '{
        "storeid": "STORE_001",
        "appid": "APP_BEACON_IOS",
        "account": "bear@ezlink.io",
        "password": "ombb3900"
        }'
        ```

        **Issue Queue Ticket (appsetcallnumber):**
        ```text
        curl -X POST "[http://192.168.42.128:8900/webapi.php?request=appsetcallnumber](http://192.168.42.128:8900/webapi.php?request=appsetcallnumber)" \
        -H "Content-Type: application/json" \
        -d '{
        "storeid": "STORE_001",
        "account": "bear@ezlink.io"
        }'
        ```

    * **3. JavaScript Fetch Example (SPA Front-end / Mobile App)Standard Fetch API integration for Vue, React, or Flutter Web clients:**

    ```text
    /**
    * Generic API request wrapper
    */
    async function requestWebApi(action, payload) {
        const url = `[http://192.168.42.128:8900/webapi.php?request=$](http://192.168.42.128:8900/webapi.php?request=$){action}`;
        
        try {
            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                },
                body: JSON.stringify(payload)
            });

            const result = await response.json();
            if (!response.ok) {
                console.error(`API [${action}] failed (${response.status}):`, result.message);
                return null;
            }

            return result;
        } catch (err) {
            console.error(`Network request error:`, err);
            return null;
        }
    }

    // Workflow Example: Authentication followed by Queue Ticket Issuance
    async function handleUserFlow() {
        // 1. Sign in
        const loginData = await requestWebApi('appuserlogin', {
            storeid: 'STORE_001',
            appid: 'APP_BEACON_IOS',
            account: 'bear@ezlink.io',
            password: 'ombb3900'
        });

        if (loginData && loginData.status === 'success') {
            console.log('Login successful. Session Token:', loginData.logindata.token);

            // 2. Issue queue ticket
            const ticketData = await requestWebApi('appsetcallnumber', {
                storeid: loginData.logindata.storeid,
                account: loginData.logindata.account
            });

            console.log('Ticket issued successfully. Queue Number:', ticketData.userdata.waitnumber);
        }
    }
    ```
