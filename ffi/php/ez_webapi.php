<?php
require_once("ez_rest.php");
require_once("./config.php");
require_once("./library/ez_request.php");
require_once("./library/ez_db_adapter.php");

class webapi extends ezRest {

    private $db = null; // 指向 EzDbAdapter 單例

    public function __construct() {
        parent::__construct();
        // 取得全域常駐 DB 介面實體 (零 MySQL 連線負擔)
        $this->db = EzDbAdapter::getInstance();
    }

    // 範例 1：取得商店設定資訊 
    private function getstoreconfig() {
        if ($this->get_request_method() != 'POST') {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Invalid Request Type']), 400);
        }

        $params = $this->isJson($this->_request) ? (array)json_decode($this->_request) : [];
        $storeId = $params['storeid'] ?? '';

        if (empty($storeId)) {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Inquired store id']), 400);
        }

        // 透過 EDX 標籤 "TAG_STOREID" 進行 B-Tree 秒級查找
        $store = $this->db->findOneByTag('vendor_config', 'TAG_STOREID', $storeId);

        if (!$store) {
            $this->response(json_encode(['status' => 'failed', 'message' => 'No Store information found.']), 404);
        }

        // 若 store_token 為空則就地補上 GUID 並更新實體列
        if (empty($store['store_token'])) {
            $token = $this->guid();
            $store['store_token'] = $token;
            $this->db->update('vendor_config', $store['__recno'], ['store_token' => $token]);
        }

        $res = [
            'status'    => 'success',
            'storeid'   => $store['storeid'],
            'storedata' => $store
        ];
        $this->response(json_encode($res), 200);
    }

    // 範例 2：使用者登入認證 
    private function appuserlogin() {
        if ($this->get_request_method() != 'POST') {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Invalid Request Type']), 400);
        }

        $params = $this->isJson($this->_request) ? (array)json_decode($this->_request) : [];
        $account = $params['account'] ?? '';
        $password = $params['password'] ?? '';

        if (empty($account) || empty($password)) {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Missing account or password']), 400);
        }

        // 透過 EDX Tag "TAG_ACCOUNT" 索引快速定位使用者
        $user = $this->db->findOneByTag('vendor_account', 'TAG_ACCOUNT', $account);

        if (!$user || $user['passwd'] !== $password || $user['ischecked'] !== '1') {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Account not registered or invalid password.']), 401);
        }

        $res = [
            'status'    => 'success',
            'logindata' => [
                'storeid' => $user['vendor_id'],
                'account' => $user['account_id'],
                'token'   => $user['token']
            ]
        ];
        $this->response(json_encode($res), 200);
    }

    // 範例 3：取號/排隊新增 
    private function appsetcallnumber() {
        if ($this->get_request_method() != 'POST') {
            $this->response(json_encode(['status' => 'failed', 'message' => 'Invalid Request Type']), 400);
        }

        $params = $this->isJson($this->_request) ? (array)json_decode($this->_request) : [];
        $storeId = $params['storeid'] ?? '';
        $account = $params['account'] ?? '';

        // 新增實體記錄到 vendor_waitqueue.ebf
        $newRecord = [
            'storeid'         => $storeId,
            'acquire_account' => $account,
            'callnumber'      => date('His'), // 範例號碼生成
            'status'          => '1',
            'checkin_time'    => date('Y-m-d H:i:s')
        ];

        $recNo = $this->db->insert('vendor_waitqueue', $newRecord);

        $res = [
            'status'   => 'success',
            'userdata' => ['waitnumber' => $newRecord['callnumber'], 'recno' => $recNo]
        ];
        $this->response(json_encode($res), 200);
    }

    public function processAPI() {
        $func = strtolower(trim(str_replace("/", "", $_REQUEST['request'] ?? '')));
        if (method_exists($this, $func)) {
            $this->$func();
        } else {
            $this->response('', 404);
        }
    }
}

// 實體化與派送
$api = new webapi();
$api->processAPI();

?>