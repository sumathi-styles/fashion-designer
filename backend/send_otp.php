<?php
header('Content-Type: application/json');
require_once 'otp_config.php';

// Flutter app POST panna data eduthukurom
$data = json_decode(file_get_contents('php://input'), true);
$mobile = isset($data['mobile']) ? trim($data['mobile']) : '';

if (empty($mobile)) {
    echo json_encode(['success' => false, 'message' => 'Mobile number required']);
    exit;
}

// Country code sethukurom illana add pannurom (India = 91)
if (strlen($mobile) === 10) {
    $mobile = '91' . $mobile;
}

$payload = json_encode([
    'widgetId' => MSG91_WIDGET_ID,
    'tokenAuth' => MSG91_TOKEN_AUTH,
    'identifier' => $mobile
]);

$ch = curl_init(MSG91_SEND_OTP_URL);
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
        'message' => 'OTP sent successfully',
        'reqId' => $result['message'] ?? null // MSG91 verify time-la idhu venum
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'Failed to send OTP',
        'raw' => $result
    ]);
}
?>