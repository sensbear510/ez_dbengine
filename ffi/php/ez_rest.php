<?php

/*
 * 檔案 : ez_rest.php.
 * 說明 : 提供REST 基礎協定類別
 * 版本 : 1.0.0 初始化建構
 */

/**
 * Description of ezlink_rest
 *
 * @author bear
 */
class ezRest {
    
    public $_allow = array();
    public $_content_type = "application/json";
    public $_request = array();
    //
    private $_method = "";
    private $_code = 200;
    private $_languageid = "";
    //
    
    public function __construct() {        
        $this->inputs();
    }    
   
    public function get_referer() {
        return $_SERVER['HTTP_REFERER'];
    }
    
    public function response($data, $status) {
        $this->_code = ($status) ? $status : 200;
        $this->set_headers();
        echo $data;
        exit;
    }    
    
    public function _debug($name, $var = null) {
        ob_start();
        if (isset($var) && !empty($var) ) {
            if (strtolower(gettype($var)) == "array") {
                $data = '[DEBUG] -('. $name . ') => ' . implode(' ',$var) . NL;
            } else {
                $data = '[DEBUG] -('. $name . ') => ' . print_r($var) . NL;
            }
        } else {
            $data = '[DEBUG] -('. $name . ')'. NL;
        }
        file_put_contents('./webapilog_'.date("Y-m-d").'.log',$data, FILE_APPEND);        
        ob_end_flush();
    }
    
    function gensecurecode() {        
        return sprintf("%06d", mt_rand(1, 999999));
    }
        
    private function get_status_message() {
        $status = array(
                        100 => 'Continue',  
                        101 => 'Switching Protocols',  
                        200 => 'OK',
                        201 => 'Created',  
                        202 => 'Accepted',  
                        203 => 'Non-Authoritative Information',  
                        204 => 'No Content',  
                        205 => 'Reset Content',  
                        206 => 'Partial Content',  
                        300 => 'Multiple Choices',  
                        301 => 'Moved Permanently',  
                        302 => 'Found',  
                        303 => 'See Other',  
                        304 => 'Not Modified',  
                        305 => 'Use Proxy',  
                        306 => '(Unused)',  
                        307 => 'Temporary Redirect',  
                        400 => 'Bad Request',  
                        401 => 'Unauthorized',  
                        402 => 'Payment Required',  
                        403 => 'Forbidden',  
                        404 => 'Not Found',  
                        405 => 'Method Not Allowed',  
                        406 => 'Not Acceptable',  
                        407 => 'Proxy Authentication Required',  
                        408 => 'Request Timeout',  
                        409 => 'Conflict',  
                        410 => 'Gone',  
                        411 => 'Length Required',  
                        412 => 'Precondition Failed',  
                        413 => 'Request Entity Too Large',  
                        414 => 'Request-URI Too Long',  
                        415 => 'Unsupported Media Type',  
                        416 => 'Requested Range Not Satisfiable',  
                        417 => 'Expectation Failed',  
                        500 => 'Internal Server Error',  
                        501 => 'Not Implemented',  
                        502 => 'Bad Gateway',  
                        503 => 'Service Unavailable',  
                        504 => 'Gateway Timeout',  
                        505 => 'HTTP Version Not Supported'
        );
        return ($status[$this->_code]) ? $status[$this->_code] : $status[500] ;
    }

    public function get_request_method() {
        return $_SERVER['REQUEST_METHOD'];
    }
    
    private function inputs() {
        switch ( $this->get_request_method() ) {
            case "POST":
                //$this->_request = $this->purgeInputs($_POST);
                $this->_request = file_get_contents("php://input");
                if (!isset($this->_request) || ($this->_request == "")) {
                    $this->_request = $_POST;
                }
                break;
            case "GET":
            case "DELETE":                    
                $this->_request = $this->purgeInputs($_GET);
                break;
            case "PUT":                
                parse_str(file_get_contents("php://input"), $this->_request);
                //$this->_request = $this->purgeInputs($this->_request);
                $this->_request = file_get_contents("php://input");
                break;
            default:
                $this->response('',406);
                break;
        }
    }
    
    // 去除不需要的符號字元
    private function purgeInputs($data) {
        $purge_input = array();
        
        if (is_array($data)) {
            foreach($data as $tmp => $value) {
                $purge_input[$tmp] = $this->purgeInputs($value);
            }
        } else {
            $data = strip_tags($data);
            $purge_input = trim($data);
        }
        return $purge_input;
    }
    
    private function set_headers() {
        header("HTTP/1.1 ". $this->_code . " " . $this->get_status_message());
        header("Content-Type:". $this->_content_type);
    }    
}
