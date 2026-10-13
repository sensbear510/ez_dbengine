<?php

if (filter_has_var(INPUT_SERVER, "SERVER_NAME")) {    
    $servername = filter_input(INPUT_SERVER, "SERVER_NAME",FILTER_UNSAFE_RAW, FILTER_NULL_ON_FAILURE);
} else {
    if (isset($_SERVER["SERVER_NAME"]))
        $servername = filter_var($_SERVER["SERVER_NAME"],FILTER_UNSAFE_RAW, FILTER_NULL_ON_FAILURE);
    else
        $servername = null;
}

if (!isset($servername)) {
    // HTTP
    define('HTTP_SERVER', 'https://ezlink.io/');
    // HTTPS
    define('HTTPS_SERVER', 'https://ezlink.io/');    
} else {
    // HTTP
    define('HTTP_SERVER', 'https://' . $servername . '/');    
    // HTTPS
    define('HTTPS_SERVER', 'https://' . $servername . '/');    
}

// DIR
define('DIR_APPLICATION', '/var/ezlink/catalog/');
define('DIR_SYSTEM', '/var/ezlink/system/');
define('DIR_DATABASE', '/var/ezlink/system/database/');
define('DIR_LANGUAGE', '/var/ezlink/catalog/language/');
define('DIR_TEMPLATE', '/var/ezlink/catalog/view/theme/');
define('DIR_CONFIG', '/var/ezlink/system/config/');
define('DIR_IMAGE', '/var/ezlink/image/');
define('DIR_CACHE', '/var/ezlink/system/cache/');
define('DIR_DOWNLOAD', '/var/ezlink/download/');
define('DIR_LOGS', '/var/ezlink/system/logs/');
define('DIR_WEBAPI', '/var/ezlink/webapi/');
define('DIR_DATA', '/var/ezlink/data/'); // 存放 .ebf edx erl ezb etc,,

// 捨棄 MySQL 連線，改用 C-Core 核心路徑與 FFI 設定
define('EZ_SDK_PATH',     '/mnt/ez_dbengine/ffi/php/ez_dbengine.php');
define('EBF_TABLE_PREFIX', ''); // 若需要檔名前綴

?>
