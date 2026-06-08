abstract class PaymentGateway {
  Future<Map<String, dynamic>> createWechatPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  });

  Future<Map<String, dynamic>> createAlipayPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  });

  Future<Map<String, dynamic>> createUnionpayPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  });

  Future<Map<String, dynamic>> queryPaymentStatus({
    required String orderNo,
    String? paymentMethod,
  });
}
