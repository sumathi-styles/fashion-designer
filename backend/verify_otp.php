<?php
header('Content-Type: application/json');
require_once 'otp_config.php';

$data = json_decode(file_get_contents('php://input'), true);
$mobile = isset($data['mobile']) ? trim($data['mobile']) : '';
$otp = isset($data['otp']) ? trim($data['otp']) : '';
$reqId = isset($data['reqId']) ? trim($data['reqId']) : '';

if (empty($mobile) || empty($otp)) {
    echo json_encode(['success' => false, 'message' => 'Mobile and OTP required']);
    exit;
}

if (strlen($mobile) === 10) {
    $mobile = '91' . $mobile;
}

$payload = json_encode([
    'widgetId' => MSG91_WIDGET_ID,
    'tokenAuth' => MSG91_TOKEN_AUTH,
    'identifier' => $mobile,
    'otp' => $otp,
    'reqId' => $reqId
]);

$ch = curl_init(MSG91_VERIFY_OTP_URL);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'accept: application/json'
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$result = json_decode($response, true);

if ($httpCode === 200 && isset($result['type']) && $result['type'] === 'success') {
    echo json_encode([
        'success' => true,
        'message' => 'OTP verified successfully'
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Invalid OTP or verification failed',
        'raw' => $result
    ]);
}
?>