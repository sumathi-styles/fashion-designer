import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'app_colors.dart';
import 'app_state.dart';
import 'models.dart';
import 'api_service.dart';
import 'services/onesignal_service.dart';

/// ---------------------------------------------------------------------
/// CARD INPUT FORMATTERS — auto space every 4 digits on Card Number,
/// auto insert "/" after MM on Expiry (MM/YY).
/// ---------------------------------------------------------------------

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 16 ? digits.substring(0, 16) : digits;

    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      buffer.write(limited[i]);
      if ((i + 1) % 4 == 0 && i + 1 != limited.length) {
        buffer.write(' ');
      }
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 4 ? digits.substring(0, 4) : digits;

    final text = limited.length <= 2
        ? limited
        : '${limited.substring(0, 2)}/${limited.substring(2)}';

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// ---------------------------------------------------------------------
/// PAYMENT METHOD
/// ---------------------------------------------------------------------

enum PaymentMethod {
  upi,
  card,
  cod,
}

/// ---------------------------------------------------------------------
/// CHECKOUT PAGE
/// ---------------------------------------------------------------------

class CheckoutPage extends StatefulWidget {
  final List<Product> items;
  final bool fromCart;

  final Map<int, int>? quantities;

  const CheckoutPage({
    super.key,
    required this.items,
    this.fromCart = false,
    this.quantities,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // 0 = Address
  // 1 = Summary
  // 2 = Payment
  int _step = 0;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _altPhoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _pincodeCtrl = TextEditingController();

  // Card fields shown on the Payments step. Actual secure card entry
  // still happens inside Razorpay's own checkout sheet (PCI-compliant) —
  // these are just the visible Flipkart-style fields on our screen.
  final TextEditingController _cardNumberCtrl = TextEditingController();
  final TextEditingController _cardExpiryCtrl = TextEditingController();
  final TextEditingController _cardCvvCtrl = TextEditingController();

  bool _cardNumberError = false;
  bool _cardExpiryError = false;

  PaymentMethod _payment = PaymentMethod.upi;

  // Which accordion section is open on the Payments step. UPI is
  // expanded by default, matching the reference screenshots.
  PaymentMethod? _expandedMethod = PaymentMethod.upi;

  bool _placingOrder = false;
  String? _previewOrderId;

  Future<String> _getOrGenerateOrderId() async {
    if (_previewOrderId != null) return _previewOrderId!;
    final db = FirebaseFirestore.instance;
    final phone = _phoneCtrl.text.trim();
    final year = DateTime.now().year;
    final yearStart = DateTime(year, 1, 1);
    final snap = await db
        .collection('orders')
        .where(
          'created_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(yearStart),
        )
        .get();
    final sequence = (snap.docs.length + 1).toString().padLeft(3, '0');
    final last3 =
        phone.length >= 3 ? phone.substring(phone.length - 3) : phone;
    _previewOrderId = 'SS$year$sequence$last3';
    return _previewOrderId!;
  }

  Future<void> _awardCoinsIfEligible(String userId) async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('user_coins').doc(userId);
    final snap = await ref.get();
    final currentOrderCount = (snap.data()?['orderCount'] ?? 0) as int;
    final newOrderCount = currentOrderCount + 1;

    final updates = <String, dynamic>{'orderCount': newOrderCount};
    if (newOrderCount >= 6) {
      updates['coins'] = FieldValue.increment(2);
    }
    await ref.set(updates, SetOptions(merge: true));
  }

  // -------------------------------------------------------------------
  // RAZORPAY
  // -------------------------------------------------------------------

  late Razorpay _razorpay;

  String? _razorpayOrderId;
  String? _razorpayPaymentId;
  String? _razorpaySignature;

  // -------------------------------------------------------------------
  // BACKEND — Vercel-hosted create-order / verify-payment endpoints.
  // Real server-side signature verification happens here (Key Secret
  // stays on Vercel as an environment variable, never in this app).
  // -------------------------------------------------------------------
  static const String createOrderUrl =
      'https://fashion-designer-lime.vercel.app/api/createOrder';

  static const String verifyPaymentUrl =
      'https://fashion-designer-lime.vercel.app/api/verifyPayment';

  // Razorpay Key ID (public, safe to keep in the app).
  static const String razorpayKeyId = 'rzp_live_Tf5OaRI34pvsH9';

  // -------------------------------------------------------------------
  // DELIVERY CHARGE
  // -------------------------------------------------------------------
  //
  // Free delivery above this order value; otherwise a flat fee applies.
  static const double freeDeliveryThreshold = 499;
  static const double deliveryFee = 40;

  // -------------------------------------------------------------------
  // INIT
  // -------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    final state = AppState.instance;

    if (state.isLoggedIn) {
      _nameCtrl.text = state.userName ?? '';
      _phoneCtrl.text = state.userId ?? '';
    }
    // Auto-fill the delivery address fields from the most recently
    // confirmed/saved address (via LocationMapPickerPage).
    _prefillSavedAddress();

    // Razorpay setup
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  // -------------------------------------------------------------------
  // DISPOSE
  // -------------------------------------------------------------------

  @override
  void dispose() {
    _razorpay.clear();

    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _pincodeCtrl.dispose();

    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvvCtrl.dispose();

    super.dispose();
  }

  // -------------------------------------------------------------------
  // QUANTITY
  // -------------------------------------------------------------------

  int _qtyOf(Product product) {
    final overrideQty = widget.quantities?[product.id];

    if (overrideQty != null && overrideQty > 0) {
      return overrideQty;
    }

    if (product.qty > 0) {
      return product.qty;
    }

    return 1;
  }

  // -------------------------------------------------------------------
  // PREFILL SAVED ADDRESS
  // -------------------------------------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_addressCtrl.text.trim().isEmpty) {
      _prefillSavedAddress();
    }
  }

  Future<void> _prefillSavedAddress() async {
    final state = AppState.instance;

    try {
      final addresses = await ApiService.instance.getAddresses();

      if (addresses.isNotEmpty) {
        // Most recently confirmed address is the last one added.
        final latest = addresses.last;

        if (!mounted) return;

        setState(() {
          if (_addressCtrl.text.trim().isEmpty) {
            _addressCtrl.text = latest.addressLine;
          }
          if (_pincodeCtrl.text.trim().isEmpty) {
            _pincodeCtrl.text = latest.pincode;
          }
          if ((latest.phone ?? '').trim().isNotEmpty &&
              _phoneCtrl.text.trim().isEmpty) {
            _phoneCtrl.text = latest.phone!.trim();
          }
        });
        return;
      }
    } catch (_) {
      // Fall through to the delivery-location fallback below.
    }

    // No saved address on file yet — fall back to whatever address the
    // user already picked earlier (Home / Shop / Cart / Product Details
    // pages all write to AppState.deliveryLocation via LocationPickerSheet).
    if (!mounted) return;
    setState(() {
      if (_addressCtrl.text.trim().isEmpty &&
          state.deliveryLocation.trim().isNotEmpty) {
        _addressCtrl.text = state.deliveryLocation;
      }
      if (_pincodeCtrl.text.trim().isEmpty &&
          state.deliveryPincode.trim().isNotEmpty) {
        _pincodeCtrl.text = state.deliveryPincode;
      }
    });
  }

  // -------------------------------------------------------------------
  // SUBTOTAL / DELIVERY / TOTAL
  // -------------------------------------------------------------------

  double get _subtotal {
    double total = 0;
    for (final product in widget.items) {
      final qty = _qtyOf(product);
      total += product.price * qty;
    }
    return total;
  }

  double get _delivery {
    if (_subtotal <= 0) return 0;
    return _subtotal >= freeDeliveryThreshold ? 0 : deliveryFee;
  }

  double get _total => _subtotal + _delivery;

  // -------------------------------------------------------------------
  // NEXT
  // -------------------------------------------------------------------

  void _goNext() {
    // ADDRESS
    if (_step == 0) {
      final isValid = _formKey.currentState?.validate() ?? false;

      if (!isValid) {
        return;
      }

      setState(() {
        _step = 1;
      });

      return;
    }

    // SUMMARY
    if (_step == 1) {
      setState(() {
        _step = 2;
      });

      return;
    }

    // PAYMENT — handled inline by each accordion section's own button now,
    // but the bottom bar still works as a fallback trigger for whichever
    // method is currently selected.
    if (_step == 2) {
      if (_payment == PaymentMethod.cod) {
        _placeCodOrder();
      } else {
        _startRazorpayPayment();
      }
    }
  }

  // -------------------------------------------------------------------
  // BACK
  // -------------------------------------------------------------------

  void _goBack() {
    if (_placingOrder) {
      return;
    }

    if (_step == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _step--;
    });
  }

  // ===================================================================
  // RAZORPAY PAYMENT — order is created on the Vercel backend first,
  // then Razorpay's checkout sheet is opened with that order_id.
  // ===================================================================

  Future<void> _startRazorpayPayment() async {
    if (_placingOrder) {
      return;
    }

    if (widget.items.isEmpty) {
      _showMessage('No items available for checkout.');
      return;
    }

    setState(() {
      _placingOrder = true;
    });

    try {
      // Razorpay expects paise.
      final int amountInPaise = (_total * 100).round();

      final response = await http.post(
        Uri.parse(createOrderUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amountInPaise,
          'currency': 'INR',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(
          data['message'] ?? 'Unable to create payment order',
        );
      }

      _razorpayOrderId = data['order_id']?.toString();

      if (_razorpayOrderId == null || _razorpayOrderId!.isEmpty) {
        throw Exception('Razorpay order ID missing');
      }

      // Razorpay's own checkout sheet — this is what shows the native
      // UPI app picker (Google Pay / PhonePe / Paytm) and the card
      // entry screen. We don't need to build those ourselves; the card
      // fields on our screen are only a Flipkart-style visual cue.
      final options = {
        'key': razorpayKeyId,
        'amount': amountInPaise,
        'currency': 'INR',
        'name': 'Sumathi',
        'description': 'Dress / Tailoring Order',
        'order_id': _razorpayOrderId,
        'prefill': {
          'name': _nameCtrl.text.trim(),
          'contact': _phoneCtrl.text.trim(),
        },
        'theme': {
          'color':
              '#${AppColors.primary.value.toRadixString(16).substring(2)}',
        },
        'retry': {
          'enabled': true,
          'max_count': 2,
        },
        'send_sms_hash': true,
        // Restrict the sheet's payment methods to match what this
        // screen offers (UPI or Card), based on what the user picked.
        if (_payment == PaymentMethod.upi)
          'method': {'upi': true, 'card': false, 'netbanking': false, 'wallet': false}
        else if (_payment == PaymentMethod.card)
          'method': {'upi': false, 'card': true, 'netbanking': false, 'wallet': false},
      };

      _razorpay.open(options);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _placingOrder = false;
      });

      _showMessage('Unable to start payment. Please try again.');
    }
  }

  // ===================================================================
  // PAYMENT SUCCESS
  // ===================================================================

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    _razorpayPaymentId = response.paymentId;
    _razorpayOrderId = response.orderId ?? _razorpayOrderId;
    _razorpaySignature = response.signature;

    await _verifyPaymentOnServer();
  }

  // ===================================================================
  // VERIFY PAYMENT — server confirms the signature is genuine before
  // we treat the order as paid.
  // ===================================================================

  Future<void> _verifyPaymentOnServer() async {
    try {
      final response = await http.post(
        Uri.parse(verifyPaymentUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_payment_id': _razorpayPaymentId,
          'razorpay_order_id': _razorpayOrderId,
          'razorpay_signature': _razorpaySignature,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Payment verification server error');
      }

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        await _finishPaidOrder();
      } else {
        throw Exception(
          data['message'] ?? 'Payment verification failed',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _placingOrder = false;
      });

      _showMessage('Payment verification failed.');
    }
  }

  // ===================================================================
  // PAYMENT ERROR
  // ===================================================================

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) {
      return;
    }

    setState(() {
      _placingOrder = false;
    });

    _showMessage('Payment failed. Please try again.');
  }

  // ===================================================================
  // EXTERNAL WALLET
  // ===================================================================

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) {
      return;
    }

    setState(() {
      _placingOrder = false;
    });

    _showMessage('External wallet selected.');
  }

  // ===================================================================
  // PAID ORDER
  // ===================================================================

  Future<void> _finishPaidOrder() async {
    if (widget.items.isEmpty) {
      return;
    }

    final db = FirebaseFirestore.instance;

    final double orderTotal = _total;
    final phone = _phoneCtrl.text.trim();

    final orderId = await _getOrGenerateOrderId();

    final productNames = widget.items.map((p) => p.name).join(', ');

    await db.collection('orders').add({
      'order_id': orderId,
      'name': _nameCtrl.text.trim(),
      'mobile': phone,
      'alternate_mobile': _altPhoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'pincode': _pincodeCtrl.text.trim(),
      'delivery_address':
          '${_addressCtrl.text.trim()}, ${_pincodeCtrl.text.trim()}',
      'product': productNames,
      'product_image': widget.items.isNotEmpty ? widget.items.first.image : '',
      'amount': orderTotal,
      'status': 'Ordered',
      'source': 'website',
      'payment_method': _payment == PaymentMethod.card ? 'Card' : 'UPI',
      'payment_status': 'paid',
      'razorpay_payment_id': _razorpayPaymentId,
      'razorpay_order_id': _razorpayOrderId,
      'ordered_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    });

    await _awardCoinsIfEligible(phone);

    OneSignalService.instance.sendPushToRole(
      'admin',
      '🛒 New Order Received',
      '${_nameCtrl.text.trim()} — $productNames (₹${orderTotal.toStringAsFixed(0)})',
    );

    await _completeLocalOrder(orderTotal, _payment, orderId);
  }

  // ===================================================================
  // COD ORDER
  // ===================================================================

  Future<void> _placeCodOrder() async {
    if (_placingOrder) {
      return;
    }

    if (widget.items.isEmpty) {
      _showMessage('No items available for checkout.');
      return;
    }

    setState(() {
      _placingOrder = true;
    });

    try {
      final db = FirebaseFirestore.instance;

      final double orderTotal = _total;
      final phone = _phoneCtrl.text.trim();

      final orderId = await _getOrGenerateOrderId();

      final productNames = widget.items.map((p) => p.name).join(', ');

      await db.collection('orders').add({
        'order_id': orderId,
        'name': _nameCtrl.text.trim(),
        'mobile': phone,
        'alternate_mobile': _altPhoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'pincode': _pincodeCtrl.text.trim(),
        'delivery_address':
            '${_addressCtrl.text.trim()}, ${_pincodeCtrl.text.trim()}',
        'product': productNames,
        'product_image': widget.items.isNotEmpty ? widget.items.first.image : '',
        'amount': orderTotal,
        'status': 'Ordered',
        'source': 'website',
        'payment_method': 'COD',
        'payment_status': 'Not Required',
        'ordered_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      });

      await _awardCoinsIfEligible(phone);

      OneSignalService.instance.sendPushToRole(
        'admin',
        '🛒 New Order Received',
        '${_nameCtrl.text.trim()} — $productNames (₹${orderTotal.toStringAsFixed(0)})',
      );

      await _completeLocalOrder(orderTotal, PaymentMethod.cod, orderId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _placingOrder = false;
      });

      _showMessage('Something went wrong.');
    }
  }

  // ===================================================================
  // COMPLETE LOCAL ORDER
  // ===================================================================

  Future<void> _completeLocalOrder(
    double orderTotal,
    PaymentMethod paymentMethod,
    String orderId,
  ) async {
    final state = AppState.instance;

    // Remove ordered products from cart.
    if (widget.fromCart) {
      for (final item in widget.items) {
        state.removeFromCart(item.id);
      }
    }

    state.addNotification(
      'Order Placed',
      'Your order of ₹${orderTotal.toStringAsFixed(0)} has been placed successfully.',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _placingOrder = false;
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _OrderSuccessPage(
          total: orderTotal,
          paymentMethod: paymentMethod,
          orderId: orderId,
        ),
      ),
    );
  }

  // ===================================================================
  // MESSAGE
  // ===================================================================

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ===================================================================
  // BUILD
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.light,

      appBar: AppBar(
        title: Text(_titleForStep()),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _placingOrder ? null : _goBack,
        ),
      ),

      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),

      // ---------------------------------------------------------------
      // BOTTOM BUTTON — hidden on the Payments step since each accordion
      // section now has its own inline Pay / Place Order button.
      // ---------------------------------------------------------------

      bottomNavigationBar: _step == 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  onPressed: _placingOrder ? null : _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.dark,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _placingOrder
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
    );
  }

  // ===================================================================
  // CURRENT STEP
  // ===================================================================

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildAddressStep();
      case 1:
        return _buildSummaryStep();
      case 2:
        return _buildPaymentStep();
      default:
        return _buildAddressStep();
    }
  }

  // ===================================================================
  // TITLE
  // ===================================================================

  String _titleForStep() {
    switch (_step) {
      case 0:
        return 'Delivery Address';
      case 1:
        return 'Order Summary';
      case 2:
        return 'Payments';
      default:
        return 'Checkout';
    }
  }

  // ===================================================================
  // STEP INDICATOR
  // ===================================================================

  Widget _buildStepIndicator() {
    const labels = ['Address', 'Summary', 'Payment'];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(labels.length * 2 - 1, (index) {
          if (index.isOdd) {
            final passed = (index ~/ 2) < _step;

            return Container(
              width: 30,
              height: 2,
              color: passed ? AppColors.primary : AppColors.gray,
            );
          }

          final stepIndex = index ~/ 2;
          final active = stepIndex <= _step;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    active ? AppColors.primary : AppColors.gray,
                child: Text(
                  '${stepIndex + 1}',
                  style: TextStyle(
                    color: active ? Colors.white : AppColors.textLight,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[stepIndex],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? AppColors.primary : AppColors.textLight,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ===================================================================
  // ADDRESS
  // ===================================================================

  Widget _buildAddressStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your delivery details',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Please enter the address where you want your order delivered.',
            style: TextStyle(color: AppColors.textLight, fontSize: 12),
          ),
          const SizedBox(height: 18),
          _field(
            controller: _nameCtrl,
            label: 'Full Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _phoneCtrl,
            label: 'Mobile Number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            validator: _validatePhone,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _altPhoneCtrl,
            label: 'Alternate Mobile Number',
            icon: Icons.phone_forwarded_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            validator: _validateAltPhone,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _addressCtrl,
            label: 'Full Address',
            icon: Icons.home_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _pincodeCtrl,
            label: 'Pincode',
            icon: Icons.pin_drop_outlined,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: _validatePincode,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Make sure your phone number and delivery address are correct before continuing.',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // FIELD
  // ===================================================================

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.gray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        counterText: '',
      ),
      validator: validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Required';
            }
            return null;
          },
    );
  }

  // ===================================================================
  // PHONE VALIDATION
  // ===================================================================

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final phone = value.trim();

    if (phone.length != 10) {
      return 'Enter a valid 10-digit phone number';
    }

    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)) {
      return 'Enter a valid phone number';
    }

    return null;
  }

  // Alternate number is optional — only validate if the user typed something.
  String? _validateAltPhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Required';

    if (phone.length != 10) {
      return 'Enter a valid 10-digit phone number';
    }

    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)) {
      return 'Enter a valid phone number';
    }

    if (phone == _phoneCtrl.text.trim()) {
      return 'Enter a different number than above';
    }

    return null;
  }

  // ===================================================================
  // PINCODE VALIDATION
  // ===================================================================

  String? _validatePincode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    final pincode = value.trim();

    if (!RegExp(r'^[0-9]{6}$').hasMatch(pincode)) {
      return 'Enter a valid 6-digit pincode';
    }

    return null;
  }

  // ===================================================================
  // SUMMARY
  // ===================================================================

  Widget _buildSummaryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Deliver To',
                          style: TextStyle(fontSize: 11, color: AppColors.textLight),
                        ),
                        InkWell(
                          onTap: _placingOrder
                              ? null
                              : () {
                                  setState(() {
                                    _step = 0;
                                  });
                                },
                          child: const Text(
                            'Change',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _nameCtrl.text,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _addressCtrl.text,
                      style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    ),
                    Text(
                      'Pincode: ${_pincodeCtrl.text}',
                      style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    ),
                    Text(
                      _phoneCtrl.text,
                      style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    ),
                    if (_altPhoneCtrl.text.trim().isNotEmpty)
                      Text(
                        'Alternate: ${_altPhoneCtrl.text.trim()}',
                        style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        FutureBuilder<String>(
          future: _getOrGenerateOrderId(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Order ID: #${snap.data}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 18),

        const Text(
          'Items',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),

        const SizedBox(height: 10),

        ...widget.items.map((product) {
          final qty = _qtyOf(product);
          final itemTotal = product.price * qty;

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: product.isNetworkImage
                      ? Image.network(
                          product.image,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imageErrorBox(),
                        )
                      : Image.asset(
                          product.image,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imageErrorBox(),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '₹${product.price.toStringAsFixed(0)} × $qty',
                        style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${itemTotal.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _priceRow('Subtotal', '₹${_subtotal.toStringAsFixed(0)}'),
              const SizedBox(height: 8),
              _priceRow(
                'Delivery',
                _delivery == 0 ? 'FREE' : '₹${_delivery.toStringAsFixed(0)}',
                valueColor: _delivery == 0 ? Colors.green : null,
              ),
              if (_delivery > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Free delivery on orders above ₹${freeDeliveryThreshold.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textLight),
                ),
              ],
              const Divider(height: 22),
              _priceRow(
                'Total Amount',
                '₹${_total.toStringAsFixed(0)}',
                bold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // IMAGE ERROR
  // ===================================================================

  Widget _imageErrorBox() {
    return Container(
      width: 60,
      height: 60,
      color: AppColors.gray,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.textLight,
      ),
    );
  }

  // ===================================================================
  // PRICE ROW
  // ===================================================================

  Widget _priceRow(
    String title,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            fontSize: bold ? 15 : 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            fontSize: bold ? 17 : 13,
            color: valueColor ?? (bold ? AppColors.primary : AppColors.text),
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // PAYMENT SCREEN — Flipkart/Razorpay-native accordion style
  // ===================================================================

  Widget _buildPaymentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Payments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 13),
                  SizedBox(width: 4),
                  Text('100% Secure', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Total Amount', style: TextStyle(color: AppColors.primary, fontSize: 13.5)),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 18),
                ],
              ),
              Text(
                '₹${_total.toStringAsFixed(0)}',
                style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // -------------------------------------------------------------
        // UPI — expands to Google Pay + "Pay with other UPI Apps",
        // both open Razorpay's own native UPI picker.
        // -------------------------------------------------------------

        _accordionTile(
          method: PaymentMethod.upi,
          icon: Icons.qr_code_2,
          title: 'UPI',
          subtitle: 'GPay, PhonePe, Paytm & more',
          content: _upiExpandedContent(),
        ),

        const SizedBox(height: 10),

        // -------------------------------------------------------------
        // CARD — expands to Card Number / Valid Thru / CVV fields +
        // Pay button. Actual entry happens in Razorpay's secure sheet.
        // -------------------------------------------------------------

        _accordionTile(
          method: PaymentMethod.card,
          icon: Icons.credit_card_outlined,
          title: 'Credit / Debit / ATM Card',
          subtitle: 'Add and secure cards as per RBI guidelines',
          content: _cardExpandedContent(),
        ),

        const SizedBox(height: 10),

        // -------------------------------------------------------------
        // COD — fully available, places order directly (no Razorpay)
        // -------------------------------------------------------------

        _accordionTile(
          method: PaymentMethod.cod,
          icon: Icons.payments_outlined,
          title: 'Cash on Delivery',
          subtitle: 'Pay when your order arrives',
          availableTag: true,
          content: _codExpandedContent(),
        ),

        const SizedBox(height: 10),

        // EMI — not offered, shown disabled to match the reference layout.
        _disabledTile(
          icon: Icons.calendar_month_outlined,
          title: 'EMI',
        ),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            '35 Crore happy customers and counting!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textLight, fontSize: 13),
          ),
        ),

        const SizedBox(height: 16),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.security_outlined, color: AppColors.primary, size: 15),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Payments are processed securely by Razorpay.',
                  style: TextStyle(fontSize: 11, color: AppColors.textLight),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // ACCORDION TILE — header (icon, title, subtitle/tag, chevron) +
  // collapsible content, single-open behaviour.
  // ===================================================================

  Widget _accordionTile({
    required PaymentMethod method,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget content,
    bool availableTag = false,
  }) {
    final expanded = _expandedMethod == method;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expanded ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _placingOrder
                ? null
                : () {
                    setState(() {
                      _payment = method;
                      _expandedMethod = expanded ? null : method;
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: Colors.black87),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                        if (!expanded) ...[
                          const SizedBox(height: 2),
                          Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
                        ],
                      ],
                    ),
                  ),
                  if (availableTag)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Available',
                        style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: content,
            ),
        ],
      ),
    );
  }

  // ===================================================================
  // EMI — always disabled/unavailable, non-interactive
  // ===================================================================

  Widget _disabledTile({required IconData icon, required String title}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.grey.shade400)),
          ),
          Row(
            children: [
              Text('Unavailable', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
              const SizedBox(width: 4),
              Icon(Icons.help_outline, size: 14, color: Colors.grey.shade400),
            ],
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // UPI EXPANDED CONTENT
  // ===================================================================

  Widget _upiExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary, width: 1.4),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.radio_button_checked, color: AppColors.primary, size: 18),
                  SizedBox(width: 10),
                  Text('Google Pay', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Spacer(),
                  Icon(Icons.g_mobiledata, size: 26, color: AppColors.primary),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _placingOrder ? null : _startRazorpayPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.dark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _placingOrder
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(
                          'Pay ₹${_total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _placingOrder ? null : _startRazorpayPayment,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pay with other UPI Apps',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Offers not valid if chosen from here',
                      style: TextStyle(color: AppColors.textLight, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // CARD EXPANDED CONTENT
  // ===================================================================

  Widget _cardExpandedContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Card Number', style: TextStyle(fontSize: 12.5, color: AppColors.textLight)),
          const SizedBox(height: 6),
          TextField(
            controller: _cardNumberCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              _CardNumberFormatter(),
            ],
            onChanged: (value) {
              final digits = value.replaceAll(' ', '');
              setState(() {
                _cardNumberError = digits.isNotEmpty && digits.length < 16;
              });
            },
            decoration: InputDecoration(
              hintText: 'XXXX XXXX XXXX XXXX',
              hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 2),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _cardNumberError ? Colors.red : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _cardNumberError ? Colors.red : AppColors.primary, width: 1.4),
              ),
              suffixIcon: const Icon(Icons.credit_card, size: 18),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Valid Thru', style: TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cardExpiryCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        _CardExpiryFormatter(),
                      ],
                      onChanged: (value) {
                        final digits = value.replaceAll('/', '');
                        bool invalid = false;
                        if (digits.length >= 2) {
                          final month = int.tryParse(digits.substring(0, 2)) ?? 0;
                          if (month < 1 || month > 12) invalid = true;
                        }
                        setState(() => _cardExpiryError = invalid);
                      },
                      decoration: InputDecoration(
                        hintText: 'MM / YY',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _cardExpiryError ? Colors.red : Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _cardExpiryError ? Colors.red : AppColors.primary, width: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CVV', style: TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cardCvvCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: InputDecoration(
                        hintText: 'CVV',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                        ),
                        suffixIcon: const Icon(Icons.help_outline, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _placingOrder ? null : _startRazorpayPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.dark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _placingOrder
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(
                      'Pay ₹${_total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Note: Please ensure your card can be used for online transactions.',
            style: TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // COD EXPANDED CONTENT
  // ===================================================================

  Widget _codExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pay in cash when your order is delivered to your doorstep.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textLight),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _placingOrder ? null : _placeCodOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.dark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: _placingOrder
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Text(
                    'Place Order  •  ₹${_total.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }
}

// =======================================================================
// ORDER SUCCESS PAGE
// =======================================================================

class _OrderSuccessPage extends StatelessWidget {
  final double total;
  final PaymentMethod paymentMethod;
  final String orderId;

  const _OrderSuccessPage({
    required this.total,
    required this.paymentMethod,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    final String paymentText = paymentMethod == PaymentMethod.cod
        ? 'Cash on Delivery'
        : paymentMethod == PaymentMethod.card
            ? 'Card'
            : 'UPI';

    return Scaffold(
      backgroundColor: AppColors.light,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 80),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Order Placed!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your order has been placed successfully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textLight),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Order ID',
                        style: TextStyle(color: AppColors.textLight, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#$orderId',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      const Text(
                        'Order Total',
                        style: TextStyle(color: AppColors.textLight, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Payment: $paymentText',
                        style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'Continue Shopping',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}