<?php
/**
 * client_test.php - 呼叫 ez_dbengine SaaS Web API 範例
 */

const API_BASE_URL = 'http://192.168.42.128:8900/webapi.php?rquest=';

/**
 * 通用 HTTP POST JSON 請求函式
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

echo "=== 1. 測試：取得商店設定 (getstoreconfig) ===\n";
$resStore = callWebApi('getstoreconfig', [
    'storeid' => 'STORE_001'
]);
print_r($resStore);

echo "\n=== 2. 測試：會員登入認證 (appuserlogin) ===\n";
$resLogin = callWebApi('appuserlogin', [
    'storeid'  => 'STORE_001',
    'appid'    => 'APP_BEACON_IOS',
    'account'  => 'bear@ezlink.io',
    'password' => 'ombb3900'
]);
print_r($resLogin);

echo "\n=== 3. 測試：線上取號排隊 (appsetcallnumber) ===\n";
$resTicket = callWebApi('appsetcallnumber', [
    'storeid' => 'STORE_001',
    'account' => 'bear@ezlink.io'
]);
print_r($resTicket);