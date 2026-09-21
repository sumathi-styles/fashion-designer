import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_colors.dart';
import 'admin_page.dart';
import 'app_state.dart';
import 'login_page.dart';
import 'shop_page.dart';
import 'product_details_page.dart';
import 'notification_service.dart';
import 'models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
/// ---------------------------------------------------------------------
/// MODELS
/// ---------------------------------------------------------------------
class AppUser {
  String name;
  String phone;
  String email;
  AppUser({this.name = '', this.phone = '', this.email = ''});
  bool get isLoggedIn => phone.isNotEmpty;
}

class SavedAddress {
  // Saved label: Home / Work / Other.
  String name;
  String recipient;
  String phone;
  String door;
  String street;
  String area;
  String city;
  String state;
  String pin;
  String landmark;

  SavedAddress({
    required this.name,
    this.recipient = '',
    this.phone = '',
    required this.door,
    required this.street,
    this.area = '',
    required this.city,
    this.state = '',
    this.pin = '',
    this.landmark = '',
  });

  String get detail {
    final parts = <String>[
      if (door.trim().isNotEmpty) door.trim(),
      if (street.trim().isNotEmpty) street.trim(),
      if (area.trim().isNotEmpty) area.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
      if (pin.trim().isNotEmpty) pin.trim(),
    ];
    return parts.join(', ');
  }

  bool get isOffice =>
      name.toUpperCase() == 'WORK' ||
      name.toUpperCase() == 'OFFICE';

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'recipient': recipient,
      'phone': phone,
      'door': door,
      'street': street,
      'area': area,
      'city': city,
      'state': state,
      'pin': pin,
      'landmark': landmark,
    };
  }

  factory SavedAddress.fromMap(Map<String, dynamic> map) {
    return SavedAddress(
      // Backward-compatible with older saved address documents.
      name: (map['name'] ?? 'Home').toString(),
      recipient: (map['recipient'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      door: (map['door'] ?? '').toString(),
      street: (map['street'] ?? '').toString(),
      area: (map['area'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      state: (map['state'] ?? '').toString(),
      pin: (map['pin'] ?? '').toString(),
      landmark: (map['landmark'] ?? '').toString(),
    );
  }
}

 class MyOrder {
  final String id;
  final String docId;
  final String product;
  final String productImage;
  final double amount;
  String status; // Ordered, Processing, Shipping, Delivered, Cancelled
  // 'paid' or 'pending' — set from the `payment_status` field saved on the
  // order document at checkout. Invoice download is only allowed when
  // this is 'paid' (see OrderDetailsPage._showHelpSheet).
  final String paymentStatus;
  final String orderedAt;
  // Raw timestamp behind `orderedAt` (which is only a formatted display
  // string). Used by OrderDetailsPage to work out the cancel-window
  // (see OrderDetailsPage._canCancelOrder).
  final DateTime? orderedAtRaw;
  final String processingAt;
  final String shippingAt;
    final String deliveredAt;
  final String cancelledAt;
  // Full delivery address exactly as entered at checkout for THIS order
  // (saved to the `delivery_address` field). Used on the invoice so it
  // never depends on which saved address happens to be first.
  final String deliveryAddress;
  MyOrder({
    required this.id,
    required this.docId,
    required this.product,
    this.productImage = '',
    required this.amount,
    this.status = 'Ordered',
    this.paymentStatus = 'pending',
    this.orderedAt = '',
    this.orderedAtRaw,
    this.processingAt = '',
    this.shippingAt = '',
    this.deliveredAt = '',
    this.cancelledAt = '',
    this.deliveryAddress = '',
  });
}

enum _Panel {
  home,
  profile,
  orders,
  wishlist,
  coins,
  addresses,
  notif,
  privacyMenu,
  privacyPolicy,
  requestData,
  grievance,
  deactivate,
  deleteAccount,
  terms,
  faq,
  qna,
  help,
  reviews,
  devices,
}

/// ---------------------------------------------------------------------
/// SETTINGS PAGE — mirrors settings.html ("My Account")
/// ---------------------------------------------------------------------
class SettingsPage extends StatefulWidget {
  final AppUser? user;
  final VoidCallback? onLoginRequested;
  final ValueChanged<AppUser?>? onUserChanged;
  final VoidCallback? onLogout;

  const SettingsPage({
    super.key,
    this.user,
    this.onLoginRequested,
    this.onUserChanged,
    this.onLogout,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Panel _panel = _Panel.home;
  AppUser _user = AppUser();

  // Profile edit controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  // Profile edit lock states. Fields are locked until the user taps Edit.
  bool _editingPersonalInfo = false;
  bool _editingEmail = false;
  bool _editingMobile = false;

  // Notification toggles (persisted locally via SharedPreferences —
  // see _loadNotifPrefs / _setNotifPref for the backend/FCM TODOs
  // needed to actually deliver a push when admin sends one).
  bool _notifOrder = true;
  bool _notifPromo = true;
  bool _notifClass = false;

  // Consent toggles (privacy)
  // bool _consentMarketing = true;
  // bool _consentLocation = false;

    // Orders — starts empty. Real orders should be loaded from your
  // backend in _loadOrders() (see TODO there); no sample/dummy data.
      bool _loadingOrders = false;
  String _orderFilter = 'all';
  final List<MyOrder> _orders = [];

  // Tracks which FAQ questions are currently expanded (by index).
  final Set<int> _openFaq = {};

  // Tracks which Question & Answer items are currently expanded (by index).
  final Set<int> _openQna = {};

  // Super Coins — real balance from Firestore `user_coins/{phone}`.
  // Coins start being awarded only from the 6th order onward (2 coins
  // per order), and can only be redeemed once the balance reaches 12.
  bool _loadingCoins = false;
  int _coinBalance = 0;
  int _coinOrderCount = 0;
  static const int _coinRedeemThreshold = 12;
  static const int _coinsStartFromOrder = 6;

  // Reviews
  bool _loadingReviews = false;
  final List<Map<String, dynamic>> _reviews = [];
  final _reviewCommentCtrl = TextEditingController();
  int _reviewRating = 5;

  // Addresses
    final List<SavedAddress> _addresses = [];
  final List<String> _addressDocIds = [];
  int _addrEditIndex = -1;
  bool _showAddrForm = false;
  final _addrNameCtrl = TextEditingController();
  final _addrRecipientCtrl = TextEditingController();
  final _addrPhoneCtrl = TextEditingController();
  final _addrDoorCtrl = TextEditingController();
  final _addrStreetCtrl = TextEditingController();
  final _addrAreaCtrl = TextEditingController();
  final _addrCityCtrl = TextEditingController();
  final _addrStateCtrl = TextEditingController();
  final _addrPinCtrl = TextEditingController();
  final _addrLandmarkCtrl = TextEditingController();
  String _addrType = 'Home';

  // Grievance
  final _grievanceSubjectCtrl = TextEditingController();
  final _grievanceOrderIdCtrl = TextEditingController();
  final _grievanceDescCtrl = TextEditingController();

  // Delete account confirm
  final _deleteConfirmCtrl = TextEditingController();
  final _deactivateReasonCtrl = TextEditingController();

  // Deactivate flow (OTP-style confirmation, mirrors delete flow)
  final _deactivatePhoneCtrl = TextEditingController();
  final _deactivateOtpCtrl = TextEditingController();
  bool _deactivateOtpSent = false;

  // Delete flow checkboxes + feedback
  bool _deleteAgreeTerms = false;
  bool _deleteAgreeBalance = false;
  bool _deleteAgreeNoService = false;
  final _deleteFeedbackCtrl = TextEditingController();

  // Contact details used by Help Center's Call Us / Mail Us buttons.

  static const String _supportEmail = 'divyadeveloper2025@gmail.com';

  // Browse FAQs — a short, focused set of account-update questions.
  final List<Map<String, String>> _faqData = const [
    {
      'q': 'What happens when I update my email address (or mobile number)?',
      'a': "Your login email id (or mobile number) changes accordingly. You'll receive all your account-related communication on your updated email address (or mobile number).",
    },
    {
      'q': 'When will my account be updated with the new email address (or mobile number)?',
      'a': 'It happens as soon as you confirm the verification code sent to your email (or mobile) and save the changes.',
    },
    {
      'q': 'What happens to my existing account when I update my email address (or mobile number)?',
      'a': "Updating your email address (or mobile number) doesn't invalidate your account. Your account remains fully functional. You'll continue seeing your Order history, saved addresses and personal details.",
    },
  ];

  // Question and Answer — the original order-related question set.
  final List<Map<String, String>> _qnaData = const [
    {
      'q': 'How can I place an order?',
      'a': 'Select your favourite product, choose the required options, add it to your cart, and tap Buy Now or proceed through Checkout to place your order.',
    },
    {
      'q': 'Can I cancel my order?',
      'a': "Yes, you can cancel your order free of cost while the status is still 'Ordered'. Once the status changes to 'Processing', stitching work has begun and the order can no longer be cancelled.",
    },
    {
      'q': 'How can I track my order?',
      'a': "Go to 'My Orders' to view your order status. You can track your order through Ordered, Processing, Shipping, and Delivered stages.",
    },
    {
      'q': 'How long will it take to receive my order?',
      'a': 'Custom-stitched orders are usually delivered within 10–15 days, depending on the stitching and order requirements.',
    },
    {
      'q': 'Can I change my delivery address after placing an order?',
      'a': 'Please update your delivery address as soon as possible. If the order has already entered Processing, the delivery address may not be changeable.',
    },
    {
      'q': 'Can I change my order after placing it?',
      'a': 'For changes to size, design, measurements, or other custom requirements, contact us as soon as possible before the order enters Processing.',
    },
    {
      'q': 'What happens if my order is delayed?',
      'a': 'If your order is taking longer than the expected delivery time, please contact us with your order details. Our team will check the status and assist you.',
    },
    {
      'q': 'What should I do if I receive the wrong or damaged product?',
      'a': 'Contact us as soon as possible with your order details and photos of the product. Our team will review the issue and guide you on the next steps.',
    },
    {
      'q': 'Can I order a custom-designed dress?',
      'a': 'Yes. Use Custom Order to share your preferred design, fabric, measurements, and other requirements. Our team will review your request.',
    },
    {
      'q': 'Where can I see my previous orders?',
      'a': "Open 'My Orders' from your account to view your current and previous orders along with their status.",
    },
  ];



    @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onAppStateChanged);
    _syncFromAppState();
    _loadNotifPrefs();
    if (_user.isLoggedIn) _loadAddresses();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppStateChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _addrNameCtrl.dispose();
    _addrRecipientCtrl.dispose();
    _addrPhoneCtrl.dispose();
    _addrDoorCtrl.dispose();
    _addrStreetCtrl.dispose();
    _addrAreaCtrl.dispose();
    _addrCityCtrl.dispose();
    _addrStateCtrl.dispose();
    _addrPinCtrl.dispose();
    _addrLandmarkCtrl.dispose();
    _grievanceSubjectCtrl.dispose();
    _grievanceOrderIdCtrl.dispose();
    _grievanceDescCtrl.dispose();
    _deleteConfirmCtrl.dispose();
    _deactivateReasonCtrl.dispose();
    _deactivatePhoneCtrl.dispose();
    _deactivateOtpCtrl.dispose();
    _deleteFeedbackCtrl.dispose();
    _reviewCommentCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    setState(_syncFromAppState);
  }

  void _syncFromAppState() {
    final state = AppState.instance;
    final newPhone = state.isLoggedIn ? (state.userId ?? '') : '';
    // Only true when the logged-in identity itself changed (login,
    // logout, or switched account) — not on every unrelated AppState
    // notification.
    final identityChanged = newPhone != _user.phone;
    if (state.isLoggedIn) {
      _user = AppUser(
        name: state.userName ?? '',
        phone: state.userId ?? '',
        email: _user.email,
      );
    } else {
      _user = AppUser();
    }
    // Refresh the Edit Profile text fields ONLY when identity changed.
    // Otherwise, if the user is mid-typing in Edit Profile, a routine
    // AppState notification (e.g. from elsewhere in the app) would wipe
    // out what they just typed before they hit Save.
    if (identityChanged) {
      _syncControllersFromUser();
      _editingPersonalInfo = false;
      _editingEmail = false;
      _editingMobile = false;
      if (_user.isLoggedIn) {
        _loadAddresses();
      } else {
        _addresses.clear();
        _addressDocIds.clear();
      }
    }
  }
  void _syncControllersFromUser() {
    final parts = _user.name.split(' ');
    _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
    _lastNameCtrl.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    _emailCtrl.text = _user.email;
    _mobileCtrl.text = _user.phone;
  }

       void _openPanel(_Panel p) {
    setState(() => _panel = p);
    if (p == _Panel.orders || p == _Panel.coins) _loadOrders();
    if (p == _Panel.coins) _loadCoins();
    if (p == _Panel.addresses) _loadAddresses();
    if (p == _Panel.reviews) _loadReviews();
  }

  Future<void> _loadCoins() async {
    if (!_user.isLoggedIn) return;
    setState(() => _loadingCoins = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_coins')
          .doc(_user.phone)
          .get();
      final data = doc.data();
      if (!mounted) return;
      setState(() {
        _coinBalance = (data?['coins'] as num?)?.toInt() ?? 0;
        _coinOrderCount = (data?['orderCount'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) _showToast('Could not load Super Coins: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingCoins = false);
    }
  }

         Future<void> _loadOrders() async {
    if (!_user.isLoggedIn) return;
    setState(() => _loadingOrders = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('mobile', isEqualTo: _user.phone)
          .get();
      final loaded = snap.docs
          .where((doc) {
            // Customized Order requests should NOT appear in My Orders.
            final source = '${doc.data()['source'] ?? ''}'.toLowerCase();
            return source != 'custom-order';
          })
          .map((doc) {
        final m = doc.data();
        // Use the human-readable order_id saved at checkout (e.g.
        // "SS2026001965") instead of the Firestore auto document id,
        // so this matches exactly what the admin dashboard shows.
        final savedOrderId = '${m['order_id'] ?? ''}'.trim();
        final displayId = savedOrderId.isNotEmpty
            ? savedOrderId
            : (doc.id.length > 6 ? doc.id.substring(0, 6).toUpperCase() : doc.id);

        String statusDate(String key) {
          final ts = m[key];
          if (ts is Timestamp) return _formatOrderDate(ts.toDate());
          return '';
        }

        // Raw ordered_at timestamp (not just the formatted display
        // string) so OrderDetailsPage can compute the cancel-window.
        final orderedTs = m['ordered_at'];

        return MyOrder(
          id: displayId,
          docId: doc.id,
          product: '${m['product'] ?? ''}',
          productImage: '${m['product_image'] ?? ''}',
          amount: (num.tryParse('${m['amount'] ?? 0}') ?? 0).toDouble(),
          status: '${m['status'] ?? 'Ordered'}',
          // 'paid' unlocks invoice download; anything else (including a
          // missing field on older orders) defaults to 'pending'.
          paymentStatus: '${m['payment_status'] ?? 'pending'}',
          orderedAt: statusDate('ordered_at'),
          orderedAtRaw: orderedTs is Timestamp ? orderedTs.toDate() : null,
          processingAt: statusDate('processing_at'),
          shippingAt: statusDate('shipping_at'),
                    deliveredAt: statusDate('delivered_at'),
          cancelledAt: statusDate('cancelled_at'),
          deliveryAddress: '${m['delivery_address'] ?? ''}',
        );
          }).toList();
      // Latest order on top, oldest order at the bottom.
      loaded.sort((a, b) {
        final aTime = a.orderedAtRaw;
        final bTime = b.orderedAtRaw;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      if (mounted) _showToast('Could not load orders: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  // ---------------------------------------------------------------
  // REVIEWS (Firestore-backed, shown under Privacy Center)
  // ---------------------------------------------------------------
  Future<void> _loadReviews() async {
    if (!_user.isLoggedIn) return;
    setState(() => _loadingReviews = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('mobile', isEqualTo: _user.phone)
          .get();
      final loaded = snap.docs.map((doc) {
        final m = doc.data();
        return {
          'id': doc.id,
          'name': '${m['name'] ?? ''}',
          'rating': (num.tryParse('${m['rating'] ?? 5}') ?? 5).toInt(),
          'comment': '${m['comment'] ?? ''}',
        };
      }).toList();
      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      if (mounted) _showToast('Could not load reviews: $e', error: true);
    } finally {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _submitReview() async {
    if (!_user.isLoggedIn) {
      _showToast('Please login to write a review!', error: true);
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('reviews').add({
        'mobile': _user.phone,
        'name': _user.name,
        'rating': _reviewRating,
        'comment': _reviewCommentCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _showToast('Thank you for your review!');
      await _loadReviews();
    } catch (e) {
      if (mounted) _showToast('Could not submit review: $e', error: true);
    }
  }

  Future<void> _editReview(Map<String, dynamic> review) async {
    if (!_user.isLoggedIn) {
      _showToast('Please login first!', error: true);
      return;
    }

    final reviewId = review['id']?.toString() ?? '';
    if (reviewId.isEmpty) {
      _showToast('Unable to edit this review.', error: true);
      return;
    }

    final commentCtrl = TextEditingController(
      text: review['comment']?.toString() ?? '',
    );
    int rating = (review['rating'] as num?)?.toInt() ?? 5;

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text(
                  'Edit your review',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your rating',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final star = index + 1;
                          return IconButton(
                            tooltip: '$star star',
                            onPressed: () => setDialogState(() => rating = star),
                            icon: Icon(
                              star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                              color: AppColors.secondary,
                              size: 30,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your review',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentCtrl,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Share your experience...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result != true) return;

      await FirebaseFirestore.instance.collection('reviews').doc(reviewId).update({
        'rating': rating,
        'comment': commentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showToast('Review updated successfully!');
      await _loadReviews();
    } catch (e) {
      if (mounted) _showToast('Could not update review: $e', error: true);
    } finally {
      commentCtrl.dispose();
    }
  }

  Future<void> _deleteReview(Map<String, dynamic> review) async {
    if (!_user.isLoggedIn) {
      _showToast('Please login first!', error: true);
      return;
    }

    final reviewId = review['id']?.toString() ?? '';
    if (reviewId.isEmpty) {
      _showToast('Unable to delete this review.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete your review?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to delete this review? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('reviews').doc(reviewId).delete();
      if (!mounted) return;
      _showToast('Review deleted successfully!');
      await _loadReviews();
    } catch (e) {
      if (mounted) _showToast('Could not delete review: $e', error: true);
    }
  }

  void _openReviewForm() {
    if (!_user.isLoggedIn) {
      _showToast('Please login to write a review!', error: true);
      return;
    }
    _reviewCommentCtrl.clear();
    _reviewRating = 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Write a review',
                              style: TextStyle(
                                  fontFamily: 'PlayfairDisplay',
                                  fontSize: 21,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryDark)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          icon: const Icon(Icons.close, color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text("Share your experience with Sumathi's Style",
                        style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                    const SizedBox(height: 20),

                    // Logged-in user preview
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 23,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              _user.name.isNotEmpty ? _user.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                                            Text(_user.name.isNotEmpty ? _user.name : 'You',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                                const SizedBox(height: 3),
                                Text(_formatContact(_user.phone),
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
                              ],
                            ),
                          ),
                          const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text('Your Rating',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final starNumber = i + 1;
                        final selected = starNumber <= _reviewRating;
                        return IconButton(
                          tooltip: '$starNumber star',
                          onPressed: () => setSheet(() => _reviewRating = starNumber),
                          iconSize: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          icon: Icon(
                            selected ? Icons.star_rounded : Icons.star_border_rounded,
                            color: selected ? AppColors.secondary : Colors.grey.shade500,
                          ),
                        );
                      }),
                    ),
                    Center(
                      child: Text(
                        _reviewRating == 0 ? 'Tap a star to rate' : '$_reviewRating out of 5 stars',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textLight),
                      ),
                    ),

                    const SizedBox(height: 18),
                    const Text('Your Review',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _reviewCommentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Tell us about your experience...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),

                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (_reviewRating == 0) {
                            _showToast('Please select a star rating!', error: true);
                            return;
                          }
                          Navigator.pop(sheetCtx);
                          await _submitReview();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 17),
                        label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

      // 'dd MMM, hh:mm a' style date used on the order timeline
  // (e.g. "10 Sep, 02:30 PM").
  String _formatOrderDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hour12:$minute $ampm';
  }

     // Only prefix +91 when it's an actual 10-digit phone number.
  // Prevents "+91someone@gmail.com" when phone field holds an email.
  String _formatContact(String value) {
    final isPhone = RegExp(r'^\d{10}$').hasMatch(value);
    return isPhone ? '+91$value' : value;
  }

  void _showToast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------
  // NOTIFICATION PREFS (local persistence)
  // ---------------------------------------------------------------
  Future<void> _loadNotifPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifOrder = prefs.getBool('notif_order') ?? true;
      _notifPromo = prefs.getBool('notif_promo') ?? true;
      _notifClass = prefs.getBool('notif_class') ?? false;
    });
  }

  // Maps the SharedPreferences key used by each toggle to the matching
  // FCM topic name (kept in one place in NotificationService so the
  // Cloud Function and this screen never drift apart).
  static const Map<String, String> _notifTopicByKey = {
    'notif_order': NotificationService.topicOrder,
    'notif_promo': NotificationService.topicPromo,
    'notif_class': NotificationService.topicClass,
  };

  Future<void> _setNotifPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);

    // Subscribe/unsubscribe this device's FCM topic right away, so the
    // change takes effect immediately — no app restart needed. Once the
    // Cloud Function in functions/index.js is deployed, admin broadcasts
    // of that type will now reach (or stop reaching) this device.
    final topic = _notifTopicByKey[key];
    if (topic != null) {
      await NotificationService.instance.setTopicSubscription(topic, value);
    }
  }



  Future<void> _mailUs() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent("Query from Sumathi's Style App")}',
    );
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      _showToast('Could not open a mail app', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.light,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
          child: _buildPanelBody(),
        ),
      ),
    );
  }

  Widget _buildPanelBody() {
    switch (_panel) {
      case _Panel.home:
        return _buildHomePanel();
      case _Panel.profile:
        return _buildProfilePanel();
      case _Panel.orders:
        return _buildOrdersPanel();
      case _Panel.wishlist:
        return _buildWishlistPanel();
      case _Panel.coins:
        return _buildCoinsPanel();
      case _Panel.addresses:
        return _buildAddressesPanel();
      case _Panel.notif:
        return _buildNotifPanel();
      case _Panel.privacyMenu:
        return _buildPrivacyMenuPanel();
      case _Panel.privacyPolicy:
        return _buildPrivacyPolicyPanel();
      case _Panel.requestData:
        return _buildRequestDataPanel();
      case _Panel.grievance:
        return _buildGrievancePanel();
      case _Panel.deactivate:
        return _buildDeactivatePanel();
      case _Panel.deleteAccount:
        return _buildDeleteAccountPanel();
      case _Panel.terms:
        return _buildTermsPanel();
      case _Panel.faq:
        return _buildFaqPanel();
      case _Panel.qna:
        return _buildQnaPanel();
      case _Panel.help:
        return _buildHelpPanel();
      case _Panel.reviews:
        return _buildReviewsPanel();
      case _Panel.devices:
        return _buildDevicesPanel();
    }
  }

  // ---------------------------------------------------------------
  // shared: panel header with back button
  // ---------------------------------------------------------------
  Widget _panelHeader(String title, IconData icon, {_Panel back = _Panel.home}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          InkWell(
            onTap: () => _openPanel(back),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.arrow_back, size: 16, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  // ---------------------------------------------------------------
  // HOME PANEL
  // ---------------------------------------------------------------
  Widget _buildHomePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profile hero card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // Profile avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _user.isLoggedIn ? (_user.name.isNotEmpty ? _user.name : 'User') : 'Guest User',
                      style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 17,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _user.isLoggedIn ? '+91${_user.phone}' : 'Not logged in',
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
                             if (!_user.isLoggedIn)
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.dark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Login', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Quick action grid — icons/labels centered in each cell.
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
          children: [
            _quickGridItem(Icons.inventory_2_outlined, 'Orders', () => _openPanel(_Panel.orders)),
            _quickGridItem(Icons.favorite_border, 'Wishlist', () => _openPanel(_Panel.wishlist)),
            _quickGridItem(Icons.monetization_on_outlined, 'Super Coins', () => _openPanel(_Panel.coins),
                iconColor: AppColors.secondary),
            _quickGridItem(Icons.support_agent, 'Drop Your Idea', () => _openPanel(_Panel.help)),
          ],
        ),
        const SizedBox(height: 20),

        // My Wishlist (the duplicate "My Shopping" row that pointed to the
        // same place as the "Orders" quick-action above has been removed).
        _menuCard('MY SHOPPING', [
          _menuRow(Icons.inventory_2_outlined, 'My Orders', () => _openPanel(_Panel.orders)),
          _menuRow(Icons.favorite_border, 'My Wishlist', () => _openPanel(_Panel.wishlist),
              iconColor: AppColors.danger),
        ]),

        // Account Settings
        _menuCard('ACCOUNT SETTINGS', [
          _menuRow(Icons.phone_android, 'Manage Devices', () => _openPanel(_Panel.devices)),
          _menuRow(Icons.edit, 'Edit Profile', () => _openPanel(_Panel.profile)),
          _menuRow(Icons.notifications_none, 'Notification Settings', () => _openPanel(_Panel.notif),
              iconColor: AppColors.secondary),
          _menuRow(Icons.shield_outlined, 'Privacy Center', () => _openPanel(_Panel.privacyMenu),
              iconColor: AppColors.success),
          _menuRow(Icons.description_outlined, 'Terms, Policies & Licenses', () => _openPanel(_Panel.terms)),
        ]),

        // My Activity
        _menuCard('MY ACTIVITY', [
          _menuRow(Icons.star_outline, 'Reviews', () => _openPanel(_Panel.reviews),
              iconColor: AppColors.secondary),
          _menuRow(Icons.question_answer_outlined, 'Question and Answer', () => _openPanel(_Panel.qna)),
        ]),

        // Feedback & Information
        // NOTE: "Terms, Policies and Licenses" row removed from here —
        // only Browse FAQs stays under this section now.
        _menuCard('FEEDBACK & INFORMATION', [
          _menuRow(Icons.help_outline, 'Browse FAQs', () => _openPanel(_Panel.faq)),
        ]),

        // Logout button — always visible directly below Browse FAQs.
        _menuCard(null, [
          _menuRow(
            Icons.logout,
            'Log Out',
            _doLogout,
            iconColor: AppColors.danger,
            labelColor: AppColors.danger,
          ),
        ]),

        // Admin Panel entry: tap to open the separate AdminPage. Kept
        // subtle so regular customers don't accidentally open it, but
        // it now lives right after Logout as requested.
        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminPage()),
              );
            },
            child: Opacity(
              opacity: 0.18,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.admin_panel_settings_outlined, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'Admin Panel',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickGridItem(IconData icon, String label, VoidCallback onTap, {Color iconColor = AppColors.primary}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _menuCard(String? title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Text(
                title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textLight, letterSpacing: 0.5),
              ),
            ),
          ...rows,
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label, VoidCallback onTap,
      {Color iconColor = AppColors.primary, Color labelColor = AppColors.text}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF2F2F2))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: labelColor)),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

    Future<void> _doLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of your account?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear the current login state.
    AppState.instance.logout();

    // Update this SettingsPage immediately.
    if (mounted) {
      setState(() {
        _user = AppUser();
        _syncControllersFromUser();
        _addresses.clear();
        _addressDocIds.clear();
        _editingPersonalInfo = false;
        _editingEmail = false;
        _editingMobile = false;
        _panel = _Panel.home;
      });
    }

    // Tell the parent/main page to switch to the Home tab.
    widget.onUserChanged?.call(null);
    widget.onLogout?.call();

    if (mounted) {
      _showToast('Logged out successfully!');
    }

    // If Settings was opened as a pushed page (e.g. from the drawer or
    // the account icon on Home), pop all the way back so the user
    // actually lands on the Home page instead of staying here.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ---------------------------------------------------------------
  // ---------------------------------------------------------------
  // PROFILE PANEL — locked fields, unlocked via the Edit link
  // ---------------------------------------------------------------
  Widget _buildProfilePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Profile Information', Icons.edit),

        // PERSONAL INFORMATION
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.badge_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Personal Information',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingPersonalInfo = true),
                  child: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _textField(
                    _firstNameCtrl,
                    'First Name',
                    readOnly: !_editingPersonalInfo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _textField(
                    _lastNameCtrl,
                    'Last Name',
                    readOnly: !_editingPersonalInfo,
                  ),
                ),
              ]),
              if (_editingPersonalInfo) ...[
                const SizedBox(height: 14),
                Row(children: [
                  ElevatedButton(
                    onPressed: _savePersonalInfo,
                    style: _saveBtnStyle(),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _syncControllersFromUser();
                        _editingPersonalInfo = false;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ]),
              ],
            ],
          ),
        ),

        // EMAIL
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Email Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingEmail = true),
                  child: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              _textField(
                _emailCtrl,
                'Enter email address',
                keyboardType: TextInputType.emailAddress,
                readOnly: !_editingEmail,
              ),
              if (_editingEmail) ...[
                const SizedBox(height: 12),
                Row(children: [
                  ElevatedButton(
                    onPressed: _saveEmail,
                    style: _saveBtnStyle(),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _emailCtrl.text = _user.email;
                        _editingEmail = false;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ]),
              ],
            ],
          ),
        ),

        // MOBILE
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.phone_android, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mobile Number',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _editingMobile = true),
                  child: const Text(
                    'Edit',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              _textField(
                _mobileCtrl,
                '10-digit number',
                keyboardType: TextInputType.phone,
                maxLength: 10,
                readOnly: !_editingMobile,
              ),
              if (_editingMobile) ...[
                const SizedBox(height: 12),
                Row(children: [
                  ElevatedButton(
                    onPressed: _saveMobileNumber,
                    style: _saveBtnStyle(),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _mobileCtrl.text = _user.phone;
                        _editingMobile = false;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ]),
              ],
              const SizedBox(height: 8),
              const Text(
                "Note: changing mobile number here won't move your past orders — those stay linked to the number you logged in with.",
                style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
              ),
            ],
          ),
        ),

        // ADDRESS IS NOW INLINE — tapping Edit Profile no longer opens
        // another address page. Saved addresses are visible and editable here.
        _buildInlineAddressSection(),
      ],
    );
  }

  Widget _buildInlineAddressSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Save an address for faster checkout',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Add address',
              onPressed: () => _openAddressForm(-1),
              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            ),
          ]),
          const SizedBox(height: 14),
          if (_addresses.isEmpty && !_showAddrForm)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.home_work_outlined, size: 34, color: AppColors.primary),
                  const SizedBox(height: 8),
                  const Text(
                    'No delivery address saved',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Add your address here. It will appear automatically on the product page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openAddressForm(-1),
                    style: _saveBtnStyle(),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Add Address'),
                  ),
                ],
              ),
            )
          else
            ..._addresses.asMap().entries.map((e) => _inlineAddressCard(e.key, e.value)),
          if (_showAddrForm) ...[
            const SizedBox(height: 12),
            _buildAddressForm(),
          ],
        ],
      ),
    );
  }

  Widget _inlineAddressCard(int index, SavedAddress a) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              a.isOffice ? Icons.work_outline : Icons.home_outlined,
              size: 19,
              color: AppColors.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name.isNotEmpty ? a.name : 'Home',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  if (a.recipient.isNotEmpty)
                    Text(
                      a.recipient,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit address',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openAddressForm(index),
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
            ),
            IconButton(
              tooltip: 'Delete address',
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteAddress(index),
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            a.detail,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.5),
          ),
          if (a.landmark.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Landmark: ${a.landmark}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textLight),
              ),
            ),
          if (a.phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Phone: +91 ${a.phone}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textLight),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle _saveBtnStyle() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      );

  Widget _textField(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
    int? maxLength,
    bool readOnly = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLength: maxLength,
      readOnly: readOnly,
      enableInteractiveSelection: !readOnly,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF5F5F5) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: readOnly ? const Color(0xFFE7E7E7) : const Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        suffixIcon: readOnly
            ? const Icon(Icons.lock_outline, size: 17, color: Colors.grey)
            : const Icon(Icons.edit_outlined, size: 17, color: AppColors.primary),
      ),
    );
  }

  void _savePersonalInfo() {
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isEmpty) {
      _showToast('Please enter your first name!', error: true);
      return;
    }
    setState(() {
      _user.name = [first, last].where((s) => s.isNotEmpty).join(' ');
      _editingPersonalInfo = false;
    });
    widget.onUserChanged?.call(_user);
    _showToast('Name updated!');
  }

  void _saveEmail() {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _showToast('Enter a valid email address!', error: true);
      return;
    }
    setState(() {
      _user.email = email;
      _editingEmail = false;
    });
    widget.onUserChanged?.call(_user);
    _showToast('Email updated!');
  }

  void _saveMobileNumber() {
    final mobile = _mobileCtrl.text.trim();
    if (mobile.length != 10 || int.tryParse(mobile) == null) {
      _showToast('Enter a valid 10-digit number!', error: true);
      return;
    }
    // TODO: trigger real OTP verification via your backend before saving
    setState(() {
      _user.phone = mobile;
      _editingMobile = false;
    });
    widget.onUserChanged?.call(_user);
    _showToast('Mobile number updated!');
  }

  // ---------------------------------------------------------------
  // ORDERS PANEL
  // ---------------------------------------------------------------
  Widget _buildOrdersPanel() {
    final filtered = _orderFilter == 'all'
        ? _orders
        : _orders.where((o) => o.status == _orderFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('My Orders', Icons.inventory_2_outlined),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['all', 'Ordered', 'Processing', 'Shipping', 'Delivered', 'Cancelled'].map((f) {
              final active = _orderFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f == 'all' ? 'All' : f),
                  selected: active,
                  onSelected: (_) => setState(() => _orderFilter = f),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(color: active ? Colors.white : AppColors.primary, fontSize: 12.5),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.primary),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (_loadingOrders)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
         else if (!_user.isLoggedIn)
  _emptyState(Icons.inventory_2_outlined, 'Login required', 'Login to see your orders', 'Login', () {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  })
        else if (filtered.isEmpty)
          _emptyState(Icons.inventory_2_outlined, 'No orders yet', 'Start shopping to see your orders here!',
              'Shop Now', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopPage()));
          })
        else
          ...filtered.map(_orderCard),
      ],
    );
  }

     Widget _orderCard(MyOrder o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _openOrderDetails(o),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF9F9F9),
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order ID: #${o.id}', style: const TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(o.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(o.status,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(o.status))),
                ),
              ],
            ),
            ),
          ),
          if (o.status == 'Cancelled' && o.cancelledAt.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.cancel, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text('Cancelled on ${o.cancelledAt}',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          InkWell(
            onTap: () => _openOrderDetails(o),
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                               Container(
                  width: 56,
                  height: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(10)),
                                    child: o.productImage.trim().isEmpty
                      ? const Icon(Icons.checkroom, color: AppColors.primary)
                      : Image.network(
                          o.productImage,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.checkroom, color: AppColors.primary),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.product, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 6),
                      Text('₹${o.amount.toStringAsFixed(0)}',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

           void _openOrderDetails(MyOrder o) {
    // Cancel Order is now always passed through — whether it's
    // tappable or greyed-out in the Help sheet is decided inside
    // OrderDetailsPage (see _canCancelOrder there).
    //
    // The invoice must use the address entered for THIS order, not
    // just whichever saved address is first — so build a one-off
    // SavedAddress from the order's own `delivery_address` field when
    // available, falling back to the saved address only for older
    // orders that don't have it.
    SavedAddress? orderAddress;
    if (o.deliveryAddress.trim().isNotEmpty) {
      orderAddress = SavedAddress(
        name: 'Delivery Address',
        recipient: _user.name,
        phone: _user.phone,
        door: o.deliveryAddress.trim(),
        street: '',
        city: '',
        state: '',
        pin: '',
      );
    } else if (_addresses.isNotEmpty) {
      orderAddress = _addresses.first;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsPage(
          order: o,
          savedAddress: orderAddress,
          customerName: _user.name,
          customerPhone: _user.phone,
          onCancelOrder: () => _confirmCancelOrder(o),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Processing':
        return const Color(0xFFF57F17);
      case 'Shipping':
        return const Color(0xFF6A1B9A);
      case 'Delivered':
        return const Color(0xFF1565C0);
      case 'Cancelled':
        return AppColors.danger;
      default:
        return const Color(0xFFC9820A);
    }
  }

  void _confirmCancelOrder(MyOrder o) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        const reasons = [
          'Ordered by mistake',
          'Found a better price elsewhere',
          'Delivery time is too long',
          'Want to change design/size/measurements',
          'Other reason',
        ];
        String? selected;
        final otherCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cancel this order?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                const Text("Please tell us why you're cancelling",
                    style: TextStyle(color: AppColors.textLight, fontSize: 12.5)),
                const SizedBox(height: 12),
                ...reasons.map((r) => RadioListTile<String>(
                      value: r,
                      groupValue: selected,
                      onChanged: (v) => setSheet(() => selected = v),
                      title: Text(r, style: const TextStyle(fontSize: 13.5)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                    )),
                if (selected == 'Other reason') ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: otherCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Please type your reason...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Go Back'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selected == null
                            ? null
                            : () {
                                final finalReason = selected == 'Other reason'
                                    ? (otherCtrl.text.trim().isNotEmpty ? otherCtrl.text.trim() : 'Other reason')
                                    : selected;
                                Navigator.pop(ctx, finalReason);
                              },
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                        child: const Text('Cancel Order'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (reason == null) return;
    try {
      await FirebaseFirestore.instance.collection('orders').doc(o.docId).update({
        'status': 'Cancelled',
        'cancel_reason': reason,
        'cancelled_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      // MyOrder.cancelledAt is final, so a plain setState() on the local
      // object can't pick up the new timestamp — reload from Firestore
      // instead so the freshly-set cancelled_at comes through.
      await _loadOrders();
      _showToast('Order cancelled successfully');
    } catch (e) {
      if (mounted) _showToast('Could not cancel order: $e', error: true);
    }
  }

  // ---------------------------------------------------------------
  // ---------------------------------------------------------------
  // WISHLIST PANEL — product grid; tap a product to view it
  // ---------------------------------------------------------------
  Widget _buildWishlistPanel() {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final items = AppState.instance.wishlistItems;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panelHeader('My Wishlist', Icons.favorite, back: _Panel.home),
            if (items.isEmpty)
              _emptyState(Icons.heart_broken_outlined, 'Your wishlist is empty', 'Save your favourite products here!', 'Explore Shop', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopPage()));
              })
            else
                        LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 10.0;
                  final cardWidth = (constraints.maxWidth - gap * 2) / 3;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: 12,
                      childAspectRatio: cardWidth / 175,
                    ),
                    itemBuilder: (_, index) => _wishlistCard(items[index]),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  bool _isProductInCart(Product p) {
    return AppState.instance.cartItems.any((item) => item.id == p.id);
  }

  Widget _wishlistCard(Product p) {
    final isInCart = _isProductInCart(p);

    return GestureDetector(
      onTap: () => _showWishlistProduct(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8), width: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.055),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================================================
            // PRODUCT IMAGE
            // ==================================================
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Image.network(
                      p.image,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: AppColors.gray,
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported, color: AppColors.textLight),
                        );
                      },
                    ),
                  ),

                  // ------------------------------------------------
                  // WISHLIST HEART
                  // ------------------------------------------------
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 1.5,
                      child: InkWell(
                        onTap: () => AppState.instance.toggleWishlist(p),
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 29,
                          height: 29,
                          child: Icon(Icons.favorite, size: 16, color: AppColors.danger),
                        ),
                      ),
                    ),
                  ),

                  // ------------------------------------------------
                  // RATING
                  // ------------------------------------------------
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF388E3C),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.rating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.star, size: 9, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==================================================
            // PRODUCT INFO
            // ==================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 7, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.text),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${p.price.toStringAsFixed(0)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF212121)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // ------------------------------------------------
                  // CART BUTTON
                  // ------------------------------------------------
                  Material(
                    color: isInCart ? AppColors.primaryDark : AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      onTap: () {
                        if (isInCart) {
                          _showWishlistProduct(p);
                        } else {
                          AppState.instance.addToCart(p);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${p.name} added to cart! 🛒')),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: 31,
                        height: 31,
                        child: Icon(
                          isInCart ? Icons.shopping_cart_checkout : Icons.add_shopping_cart,
                          size: 16,
                          color: isInCart ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWishlistProduct(Product p) {
    // Wishlist product now opens the same full Product Details page used by
    // the Shop/Home product cards — not a bottom-sheet preview.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(product: p),
      ),
    );
  }

  // SUPER COINS PANEL — a wallet balance up top, then a per-order
  // "+coins earned" history list below.
  // ---------------------------------------------------------------
    Widget _buildCoinsPanel() {
    final eligibleOrders = _orders.where((o) => o.status != 'Cancelled').toList();
    final canRedeem = _coinBalance >= _coinRedeemThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Super Coins', Icons.monetization_on_outlined),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.secondary, AppColors.secondaryLight]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              const Icon(Icons.monetization_on, size: 36, color: Colors.white),
              const SizedBox(height: 8),
              _loadingCoins
                  ? const SizedBox(
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    )
                  : Text('$_coinBalance',
                      style: const TextStyle(
                          fontFamily: 'PlayfairDisplay', fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
                           const Text('Sumathi Coins Available', style: TextStyle(color: Colors.white, fontSize: 13)),
              if (!_loadingCoins) ...[
                const SizedBox(height: 4),
                Text(
                  'From $_coinOrderCount completed order${_coinOrderCount == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                ),
              ],
              if (!_loadingCoins && !canRedeem) ...[
                const SizedBox(height: 8),
                Text(
                  'Redeem unlocks at $_coinRedeemThreshold coins (${_coinRedeemThreshold - _coinBalance} more to go)',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            children: [
              _coinsInfoRow(Icons.shopping_bag_outlined, 'Earn from your 6th order',
                  'Starting from your 6th order, earn 2 Sumathi Coins on every order you place.'),
              const Divider(height: 24),
              _coinsInfoRow(
                Icons.card_giftcard,
                canRedeem ? 'Redeem for discounts' : 'Redeem for discounts (locked)',
                canRedeem
                    ? 'You have enough coins! Redemption on your next custom order is coming soon.'
                    : 'Reach $_coinRedeemThreshold coins to unlock redeeming coins for a discount.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text('COINS HISTORY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textLight, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        if (_loadingOrders || _loadingCoins)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!_user.isLoggedIn)
          _emptyState(Icons.monetization_on_outlined, 'Login required', 'Login to see your Super Coins', 'Login', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
          })
        else if (eligibleOrders.isEmpty)
          _emptyState(Icons.monetization_on_outlined, 'No coins yet',
              'Place an order to start earning Super Coins!', 'Shop Now', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopPage()));
          })
        else
          ...eligibleOrders.asMap().entries.map((e) => _coinHistoryRow(e.value, e.key + 1)),
      ],
    );
  }

  Widget _coinHistoryRow(MyOrder o, int orderPosition) {
    // Coins are only earned from the 6th order onward — 2 coins per
    // order — matching the award logic run at checkout.
    final earned = orderPosition >= _coinsStartFromOrder ? 2 : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.monetization_on, size: 18, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.product, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('Order #${o.id} • ₹${o.amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
              ],
            ),
          ),
          Text(earned > 0 ? '+$earned' : '0',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.secondary)),
        ],
      ),
    );
  }

  Widget _coinsInfoRow(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // ---------------------------------------------------------------
  // ADDRESSES PANEL — form + Firestore persistence
  // ---------------------------------------------------------------
  Widget _buildAddressesPanel() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _panelHeader('Saved Addresses', Icons.location_on_outlined, back: _Panel.profile),
      if (_addresses.isEmpty && !_showAddrForm)
        _emptyState(Icons.location_off_outlined, 'No saved addresses', 'Add your delivery address for faster checkout.', 'Add New Address', () => _openAddressForm(-1))
      else
        ..._addresses.asMap().entries.map((e) => _addressCard(e.key, e.value)),
      if (_addresses.isNotEmpty)
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () => _openAddressForm(-1),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          icon: const Icon(Icons.add), label: const Text('Add New Address'),
        )),
      if (_showAddrForm) ...[const SizedBox(height: 16), _buildAddressForm()],
    ]);
  }

  Widget _buildAddressForm() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Add New Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
        IconButton(onPressed: _closeAddressForm, icon: const Icon(Icons.close)),
      ]),
      const Text('Use this address for delivery and future orders.', style: TextStyle(fontSize: 12, color: AppColors.textLight)),
      const SizedBox(height: 16),
      const Text('Address Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: ['Home', 'Work', 'Other'].map((type) => ChoiceChip(
        label: Text(type), selected: _addrType == type,
        onSelected: (_) => setState(() => _addrType = type), selectedColor: AppColors.primary,
        labelStyle: TextStyle(color: _addrType == type ? Colors.white : AppColors.primary),
        side: const BorderSide(color: AppColors.primary),
      )).toList()),
      const SizedBox(height: 14),
      _textField(_addrRecipientCtrl, 'Full Name'),
      const SizedBox(height: 10),
      _textField(_addrPhoneCtrl, 'Mobile Number', keyboardType: TextInputType.phone, maxLength: 10),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _textField(_addrDoorCtrl, 'Door / Flat No.')), const SizedBox(width: 10), Expanded(child: _textField(_addrStreetCtrl, 'Street / Road'))]),
      const SizedBox(height: 10),
      _textField(_addrAreaCtrl, 'Area / Locality'),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _textField(_addrCityCtrl, 'City')), const SizedBox(width: 10), Expanded(child: _textField(_addrStateCtrl, 'State'))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _textField(_addrPinCtrl, 'Pincode', keyboardType: TextInputType.number, maxLength: 6)), const SizedBox(width: 10), Expanded(child: _textField(_addrLandmarkCtrl, 'Landmark (optional)'))]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: ElevatedButton.icon(onPressed: _saveAddress, style: _saveBtnStyle(), icon: const Icon(Icons.check, size: 17), label: const Text('Save Address'))),
        const SizedBox(width: 10), OutlinedButton(onPressed: _closeAddressForm, child: const Text('Cancel')),
      ]),
    ]));
  }

  Widget _addressCard(int index, SavedAddress a) {
    final label = a.name.isNotEmpty ? a.name : 'Home';
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE8E8E8)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(10)), child: Icon(a.isOffice ? Icons.work_outline : Icons.home_outlined, color: AppColors.primary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            if (a.recipient.isNotEmpty) Text(a.recipient, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ])),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 19), onPressed: () => _openAddressForm(index)),
          IconButton(icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.danger), onPressed: () => _deleteAddress(index)),
        ]),
        const SizedBox(height: 10),
        Text(a.detail, style: const TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.5)),
        if (a.landmark.isNotEmpty) Text('Landmark: ${a.landmark}', style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
        if (a.phone.isNotEmpty) Text('Phone: +91 ${a.phone}', style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
      ]),
    );
  }

  void _openAddressForm(int index) {
    setState(() {
      _addrEditIndex = index; _showAddrForm = true;
      if (index >= 0) {
        final a = _addresses[index];
        _addrType = a.name.toUpperCase() == 'WORK' || a.name.toUpperCase() == 'OFFICE' ? 'Work' : (a.name.toUpperCase() == 'OTHER' ? 'Other' : 'Home');
        _addrNameCtrl.text = a.name; _addrRecipientCtrl.text = a.recipient; _addrPhoneCtrl.text = a.phone;
        _addrDoorCtrl.text = a.door; _addrStreetCtrl.text = a.street; _addrAreaCtrl.text = a.area;
        _addrCityCtrl.text = a.city; _addrStateCtrl.text = a.state; _addrPinCtrl.text = a.pin; _addrLandmarkCtrl.text = a.landmark;
      } else {
        _addrType = 'Home'; _addrNameCtrl.text = 'Home'; _addrRecipientCtrl.text = _user.name; _addrPhoneCtrl.text = _user.phone;
        _addrDoorCtrl.clear(); _addrStreetCtrl.clear(); _addrAreaCtrl.clear(); _addrCityCtrl.clear(); _addrStateCtrl.clear(); _addrPinCtrl.clear(); _addrLandmarkCtrl.clear();
      }
    });
  }

  void _closeAddressForm() { setState(() { _showAddrForm = false; _addrEditIndex = -1; }); }

  Future<void> _loadAddresses() async {
    if (!_user.isLoggedIn) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('saved_addresses').doc(_user.phone).collection('addresses').get();
      final loaded = snap.docs.map((doc) => SavedAddress.fromMap(doc.data())).toList();
      if (!mounted) return;
      setState(() {
        _addresses..clear()..addAll(loaded);
        _addressDocIds..clear()..addAll(snap.docs.map((doc) => doc.id));
      });
    } catch (e) {
      if (mounted) _showToast('Could not load saved addresses: $e', error: true);
    }
  }

  Future<void> _saveAddress() async {
    final recipient = _addrRecipientCtrl.text.trim();
    final phone = _addrPhoneCtrl.text.trim();
    final door = _addrDoorCtrl.text.trim();
    final street = _addrStreetCtrl.text.trim();
    final area = _addrAreaCtrl.text.trim();
    final city = _addrCityCtrl.text.trim();
    final state = _addrStateCtrl.text.trim();
    final pin = _addrPinCtrl.text.trim();
    if (recipient.isEmpty || phone.length != 10 || int.tryParse(phone) == null || door.isEmpty || street.isEmpty || area.isEmpty || city.isEmpty || state.isEmpty || pin.length != 6) {
      _showToast('Please fill all required address details!', error: true); return;
    }
    if (!_user.isLoggedIn) { _showToast('Please login to save your address!', error: true); return; }

    final entry = SavedAddress(name: _addrType, recipient: recipient, phone: phone, door: door, street: street, area: area, city: city, state: state, pin: pin, landmark: _addrLandmarkCtrl.text.trim());
    try {
      final ref = FirebaseFirestore.instance.collection('saved_addresses').doc(_user.phone).collection('addresses');
      if (_addrEditIndex >= 0 && _addrEditIndex < _addressDocIds.length && _addressDocIds[_addrEditIndex].isNotEmpty) {
        await ref.doc(_addressDocIds[_addrEditIndex]).set(
          {...entry.toMap(), 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      } else {
        final newDoc = await ref.add({...entry.toMap(), 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
        if (_addrEditIndex < 0) {
          _addressDocIds.add(newDoc.id);
        }
      }
      if (!mounted) return;
      setState(() {
        if (_addrEditIndex >= 0) {
          _addresses[_addrEditIndex] = entry;
        } else {
          _addresses.add(entry);
        }
        _showAddrForm = false;
        _addrEditIndex = -1;
      });
      _showToast('Address saved successfully!');
    } catch (e) { if (mounted) _showToast('Could not save address: $e', error: true); }
  }

  Future<void> _deleteAddress(int index) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete this address?'), content: const Text('This saved address will be removed from your account.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger)))],
    ));
    if (confirmed != true || !_user.isLoggedIn) return;
    try {
      final ref = FirebaseFirestore.instance.collection('saved_addresses').doc(_user.phone).collection('addresses');
      if (index < _addressDocIds.length && _addressDocIds[index].isNotEmpty) {
        await ref.doc(_addressDocIds[index]).delete();
      }
      if (!mounted) return;
      setState(() {
        _addresses.removeAt(index);
        if (index < _addressDocIds.length) _addressDocIds.removeAt(index);
      });
      _showToast('Address deleted');
    } catch (e) { if (mounted) _showToast('Could not delete address: $e', error: true); }
  }

  // NOTIFICATION SETTINGS PANEL
  // ---------------------------------------------------------------
  Widget _buildNotifPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Notification Settings', Icons.notifications_none),
        _card(
          child: Column(
            children: [
              _toggleRow('Order Updates', 'Get notified about order status', _notifOrder, (v) {
                setState(() => _notifOrder = v);
                _setNotifPref('notif_order', v);
              }),
              const Divider(height: 26),
              _toggleRow('Promotions', 'Receive offers and discounts', _notifPromo, (v) {
                setState(() => _notifPromo = v);
                _setNotifPref('notif_promo', v);
              }),
              const Divider(height: 26),
              _toggleRow('Class Reminders', 'Reminders for enrolled classes', _notifClass, (v) {
                setState(() => _notifClass = v);
                _setNotifPref('notif_class', v);
              }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'These switches control which admin announcements this device '
          'receives as a push notification, in real time.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.5),
        ),
      ],
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textLight)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
      ],
    );
  }

  // ---------------------------------------------------------------
  // MANAGE DEVICES PANEL — shows where the account is currently
  // logged in (this device). Real multi-device session tracking
  // needs a backend "sessions" collection; wire that up later and
  // populate this list from there.
  // ---------------------------------------------------------------
  Widget _buildDevicesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Manage Devices', Icons.phone_android),
        if (!_user.isLoggedIn)
          _emptyState(Icons.phone_android, 'Login required', 'Login to see your active devices', 'Login', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
          })
        else ...[
          _card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.smartphone, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('This Device', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                          child: const Text('Active now', style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('Logged in as ${_formatContact(_user.phone)}', style: const TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "You're currently logged in on 1 device. Logging out from a device will end its session immediately.",
            style: TextStyle(fontSize: 11.5, color: AppColors.textLight, height: 1.5),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------
  // PRIVACY CENTER — full Privacy Policy wording only. Request Data
  // Export, Grievance Redressal and Account Actions have been moved
  // out of this screen (Account Actions now sits under Browse FAQs /
  // Question & Answer instead). A link to the Terms, Policies &
  // Licenses page is offered at the bottom.
  // ---------------------------------------------------------------
  Widget _buildPrivacyMenuPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Privacy Center', Icons.shield_outlined),

        _plainSectionTitle('Privacy Policy'),
        const _PolicySection(
          title: '1. Introduction',
          body:
              "We value the trust you place in us and take the privacy and security of your personal information seriously. This Privacy Policy explains, in simple terms, how Sumathi's Style (\"we\", \"our\", \"us\") collects, uses, shares, stores, and otherwise handles your personal data when you use our website, mobile application, and related services (the \"Platform\"). By continuing to use the Platform, you agree to the practices described in this Policy.",
        ),
        const _PolicySection(
          title: '2. Information We Collect',
          body:
              'To serve you better, we collect basic details such as your name, phone number, email address and delivery address, along with order-specific information like body measurements, fitting notes, fabric/design preferences and any reference images you choose to upload. We also collect payment-related details (such as your UPI ID or transaction reference — we never store full card numbers), plus general browsing patterns, order history, and technical information like your IP address and device/browser type.',
        ),
        const _PolicySection(
          title: '3. How We Use Your Data',
          body:
              'Your data helps us process and fulfil your custom orders, coordinate tailoring and alteration work, arrange delivery, process payments safely, and keep you updated on your order via SMS/WhatsApp/Email. We also use it, in an aggregated and privacy-friendly way, to improve our fabric and design catalog, resolve disputes, prevent fraud, and meet our legal obligations.',
        ),
        const _PolicySection(
          title: '4. Data Sharing & Disclosure',
          body:
              'We want to be clear on one point: we never sell your personal data to anyone. We only share the minimum information needed with delivery/logistics partners (to complete delivery), payment gateway providers (to process payments securely), our internal tailoring staff (to fulfil your measurements), and legal authorities, and only when required by law.',
        ),
        const _PolicySection(
          title: '5. Your Rights',
          body:
              'You are always in control of your data. You may access, correct, or update your personal details through your profile at any time, request a full export of your data, request deletion of your account, and withdraw your consent for any specific use of your data whenever you wish.',
        ),
          ],
    );
  }

  Widget _plainSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildPrivacyPolicyPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Privacy Policy', Icons.description_outlined, back: _Panel.privacyMenu),
        const _PolicySection(
          title: '1. Introduction',
          body:
              "We value the trust you place in us and take the privacy and security of your personal information seriously. This Privacy Policy explains, in simple terms, how Sumathi's Style (\"we\", \"our\", \"us\") collects, uses, shares, stores, and otherwise handles your personal data when you use our website, mobile application, and related services (the \"Platform\"). By continuing to use the Platform, you agree to the practices described in this Policy.",
        ),
        const _PolicySection(
          title: '2. Information We Collect',
          body:
              'To serve you better, we collect basic details such as your name, phone number, email address and delivery address, along with order-specific information like body measurements, fitting notes, fabric/design preferences and any reference images you choose to upload. We also collect payment-related details (such as your UPI ID or transaction reference — we never store full card numbers), plus general browsing patterns, order history, and technical information like your IP address and device/browser type.',
        ),
        const _PolicySection(
          title: '3. How We Use Your Data',
          body:
              'Your data helps us process and fulfil your custom orders, coordinate tailoring and alteration work, arrange delivery, process payments safely, and keep you updated on your order via SMS/WhatsApp/Email. We also use it, in an aggregated and privacy-friendly way, to improve our fabric and design catalog, resolve disputes, prevent fraud, and meet our legal obligations.',
        ),
        const _PolicySection(
          title: '4. Cookies',
          body:
              'Our website uses small data files ("cookies") to remember your cart, wishlist and session preferences. Cookies never contain your payment details, and you can disable them from your browser settings at any time.',
        ),
        const _PolicySection(
          title: '5. Data Sharing & Disclosure',
          body:
              'We want to be clear on one point: we never sell your personal data to anyone. We only share the minimum information needed with delivery/logistics partners (to complete delivery), payment gateway providers (to process payments securely), our internal tailoring staff (to fulfil your measurements), and legal authorities, and only when required by law.',
        ),
        const _PolicySection(
          title: "6. Children's Information",
          body:
              'Our Platform is intended for individuals capable of entering into a binding contract. We do not knowingly collect data from children without a parent or guardian\'s involvement.',
        ),
        const _PolicySection(
          title: '7. Data Retention & Security',
          body:
              'We retain your data only as long as necessary to fulfil your order, handle alterations, or meet legal record-keeping requirements, and take reasonable technical and organisational measures to protect it from unauthorized access.',
        ),
        const _PolicySection(
          title: '8. Your Rights',
          body:
              'You are always in control of your data. You may access, correct, or update your personal details through your profile at any time, request a full export of your data, request deletion of your account (see De-activate / Delete my Account), and withdraw your consent for any specific use of your data whenever you wish.',
        ),
        const _PolicySection(
          title: '9. Choice / Opt-Out & Advertisements',
          body:
              'You can opt out of promotional communications anytime from Notification Settings. We may use limited third-party analytics to understand app usage; these tools never access your name, address, or payment details directly.',
        ),
        const _PolicySection(
          title: '10. Changes to This Policy',
          body:
              'We may update this Privacy Policy periodically to reflect changes in our practices or applicable law. Updates will be posted here with a revised date.',
        ),
        const _PolicySection(
          title: '11. Contact Us',
          body: 'For privacy questions, contact sumathisstyles@gmail.com or WhatsApp +91 86107 03658.',
        ),
      ],
    );
  }

  Widget _buildRequestDataPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Request My Data', Icons.download_outlined, back: _Panel.privacyMenu),
        const Text('Download Your Personal Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 10),
        const Text(
          'You have the right to access a full copy of the personal data we hold about you — profile info, order history, saved addresses, wishlist, and Super Coins balance.',
          style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.5),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _requestDataDownload,
          style: _saveBtnStyle(),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Request Data Export'),
        ),
      ],
    );
  }

  void _requestDataDownload() {
    if (!_user.isLoggedIn) {
      _showToast('Please login to request your data!', error: true);
      return;
    }
    // TODO: call request_data_export.php with { phone, email, name }
    // and/or generate + share a JSON export file locally.
    _showToast('Your data export request has been submitted!');
  }

  Widget _buildGrievancePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Grievance Redressal', Icons.gavel_outlined, back: _Panel.privacyMenu),
        const Text('Grievance Officer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        const Text(
          'Name: Sumathi.M\nDesignation: Proprietor, Sumathi\'s Style\nEmail: sumathisstyles@gmail.com\nPhone: +91 86107 03658',
          style: TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.7),
        ),
        const SizedBox(height: 20),
        const Text('Submit a Complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        _textField(_grievanceSubjectCtrl, 'Complaint Subject'),
        const SizedBox(height: 10),
        _textField(_grievanceOrderIdCtrl, 'Order ID (if applicable)'),
        const SizedBox(height: 10),
        TextField(
          controller: _grievanceDescCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Please describe your issue in detail...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _submitGrievance,
          style: _saveBtnStyle(),
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Submit Complaint'),
        ),
      ],
    );
  }

  void _submitGrievance() {
    final subject = _grievanceSubjectCtrl.text.trim();
    final desc = _grievanceDescCtrl.text.trim();
    if (subject.isEmpty || desc.isEmpty) {
      _showToast('Please fill in the subject and description!', error: true);
      return;
    }
    // TODO: POST to submit_grievance.php with name/phone/email/subject/order_id/description
    _showToast("Complaint submitted! We'll respond within 48 hours.");
    _grievanceSubjectCtrl.clear();
    _grievanceOrderIdCtrl.clear();
    _grievanceDescCtrl.clear();
  }

  // -----------------------------------------------------------------
  // DE-ACTIVATE ACCOUNT PANEL
  // Mirrors the "when you deactivate your account" info-list pattern,
  // followed by a phone + OTP confirmation step. This is now the ONLY
  // place this flow lives — Privacy Center just links here.
  // -----------------------------------------------------------------
  Widget _buildDeactivatePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('De-activate my Account', Icons.person_off_outlined, back: _Panel.faq),
        const Text('When you de-activate your account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        const _BulletLine('You are logged out of your Sumathi\'s Style account'),
        const _BulletLine('Your public profile is no longer visible'),
        const _BulletLine('Your reviews/ratings remain visible, while your profile information is shown as "unavailable"'),
        const _BulletLine('Your wishlist items are no longer accessible; the wishlist is shown as "unavailable"'),
        const _BulletLine('You will be unsubscribed from promotional emails and notifications'),
        const _BulletLine('Your account data is retained and is restored in case you choose to re-activate your account'),
        const SizedBox(height: 16),
        const Text('How do I re-activate my account?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        const Text(
          'Simply login again with your registered mobile number. Your account data is fully restored, and default notification settings will apply.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.6),
        ),
        const SizedBox(height: 20),
        const Text('Are you sure you want to leave?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 14),
        _textField(_deactivatePhoneCtrl, 'Registered mobile number', keyboardType: TextInputType.phone, maxLength: 10),
        const SizedBox(height: 10),
        if (_deactivateOtpSent)
          _textField(_deactivateOtpCtrl, 'Enter received OTP', keyboardType: TextInputType.number, maxLength: 6),
        const SizedBox(height: 10),
        _textField(_deactivateReasonCtrl, 'Reason for de-activation (optional)'),
        const SizedBox(height: 16),
        if (!_deactivateOtpSent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sendDeactivateOtp,
              style: _saveBtnStyle(),
              child: const Text('Send OTP'),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _deactivateAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Confirm De-activation'),
            ),
          ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => _openPanel(_Panel.faq),
            child: const Text('No, let me stay!'),
          ),
        ),
      ],
    );
  }

  void _sendDeactivateOtp() {
    final phone = _deactivatePhoneCtrl.text.trim();
    if (phone.length != 10 || int.tryParse(phone) == null) {
      _showToast('Enter a valid 10-digit mobile number!', error: true);
      return;
    }
    // TODO: call your backend/SMS provider to actually send an OTP here.
    setState(() => _deactivateOtpSent = true);
    _showToast('OTP sent to +91 $phone');
  }

  void _deactivateAccount() async {
    if (!_user.isLoggedIn) {
      _showToast('Please login first!', error: true);
      return;
    }
    if (_deactivateOtpCtrl.text.trim().length < 4) {
      _showToast('Please enter the OTP sent to your number!', error: true);
      return;
    }
    // TODO: verify OTP with your backend before proceeding.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure you want to temporarily de-activate your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('De-activate')),
        ],
      ),
    );
    if (confirmed != true) return;
    // TODO: POST to deactivate_account.php with { phone, reason }
    setState(() {
      _user = AppUser();
      _syncControllersFromUser();
      _deactivateOtpSent = false;
      _deactivatePhoneCtrl.clear();
      _deactivateOtpCtrl.clear();
    });
    widget.onUserChanged?.call(null);
    widget.onLogout?.call();
    _showToast('Account de-activated. Login anytime to re-activate.');
    _openPanel(_Panel.home);
  }

  // -----------------------------------------------------------------
  // DELETE ACCOUNT PANEL
  // Mirrors the "please ensure you have read and understood" bullet
  // list, permanent-action warning box, 3 required checkboxes, a
  // feedback box, and a red Delete Account button. This is now the
  // ONLY place this flow lives — Browse FAQs / Question and Answer
  // just links here, and the back arrow above returns cleanly there.
  // -----------------------------------------------------------------
  Widget _buildDeleteAccountPanel() {
    final allChecked = _deleteAgreeTerms && _deleteAgreeBalance && _deleteAgreeNoService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Delete my Account', Icons.delete_outline, back: _Panel.faq),
        const Text(
          'If you wish to proceed with an account deletion request, please ensure that you have read and understood the following:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 12),
        const _BulletLine(
            'There are no pending orders, cancellations, alterations or refund requests. If there are pending requests, please raise your account deletion request once they are completed.'),
        const _BulletLine('You will lose all Super Coins, gift card balance, or loyalty benefits associated with your account immediately upon deletion.'),
        const _BulletLine('You will not be able to access order history, profile, wishlist, saved addresses, previous orders and invoices immediately on deletion, and will have to create a new account to use our Platform again.'),
        const _BulletLine('We may choose to refuse deletion of your account in case you have any pending dispute or grievance relating to your orders.'),
        const _BulletLine('We may retain certain data for legitimate reasons (fraud prevention, regulatory compliance, or to comply with legal orders) even after deletion.'),
        const _BulletLine('After your account is deleted, if you log in again using the same phone number, a fresh new account will be created and your old account data will not be accessible.'),
        const _BulletLine('Please uninstall the app after your account is deleted to stop receiving any notifications, as notifications are an app-level setting.'),
        const SizedBox(height: 16),
        const Text('Deleting account is a permanent action',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 6),
        const Text(
          'Please be advised that the deletion of your account is a permanent action. Once your account is deleted, you will lose all Sumathi\'s Style data including order history & it will no longer be accessible and cannot be restored under any circumstances.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.6),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _deleteAgreeTerms,
          onChanged: (v) => setState(() => _deleteAgreeTerms = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('I have read and agreed to the Terms and Conditions.', style: TextStyle(fontSize: 13)),
        ),
        CheckboxListTile(
          value: _deleteAgreeBalance,
          onChanged: (v) => setState(() => _deleteAgreeBalance = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'I acknowledge that I do not have any Super Coin balance in my account, or I am willing to forfeit any such balance available in my account.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        CheckboxListTile(
          value: _deleteAgreeNoService,
          onChanged: (v) => setState(() => _deleteAgreeNoService = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'I acknowledge that I will not be able to return/replace or seek any service regarding any past order & transactions.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Please tell us why you\'re leaving us', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _deleteFeedbackCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Your feedback will help us improve Sumathi\'s Style.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: allChecked ? _deleteAccountFinal : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  void _deleteAccountFinal() async {
    if (!_deleteAgreeTerms || !_deleteAgreeBalance || !_deleteAgreeNoService) {
      _showToast('Please check all the boxes to confirm!', error: true);
      return;
    }
    if (!_user.isLoggedIn) {
      _showToast('Please login first!', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This is your final confirmation. Delete your account permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    // TODO: POST to delete_account.php with { phone, feedback: _deleteFeedbackCtrl.text.trim() }
    setState(() {
      _user = AppUser();
      _syncControllersFromUser();
      _addresses.clear();
      _deleteAgreeTerms = false;
      _deleteAgreeBalance = false;
      _deleteAgreeNoService = false;
      _deleteFeedbackCtrl.clear();
    });
    widget.onUserChanged?.call(null);
    widget.onLogout?.call();
    _showToast('Your account has been permanently deleted.');
    _openPanel(_Panel.home);
  }

  // ---------------------------------------------------------------
  // TERMS, POLICIES & LICENSES PANEL
  // ---------------------------------------------------------------
  Widget _buildTermsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                 _panelHeader('Privacy Policy', Icons.description_outlined, back: _Panel.home),

        // PART A — TERMS
        const Text('TERMS OF USE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
        const SizedBox(height: 12),
        const _PolicySection(
          title: 'Eligibility & Account Registration',
          body:
              'Use of our Platform is available only to persons who are competent to enter into a legally binding contract, and generally at least 18 years of age. To place orders or save your measurements, you may be required to register using your phone number. You are responsible for keeping your login credentials confidential.',
        ),
        const _PolicySection(
          title: 'Orders, Pricing & Payment',
          body:
              'Orders are confirmed once you receive an Order ID via app/SMS/email. Prices are in INR and inclusive of applicable taxes unless stated otherwise. We accept UPI, cash on delivery (where available), and other listed payment modes. Custom orders may require an advance payment.',
        ),
        const _PolicySection(
          title: 'Prohibited Conduct',
          body:
              'You agree not to use the Platform for unlawful purposes, interfere with its working (hacking, scraping, malicious code), impersonate others, or post defamatory/obscene content — without prejudice to your right to leave honest feedback about your experience.',
        ),
        const _PolicySection(
          title: 'Liability, Governing Law & Changes',
          body:
              "To the extent permitted by law, we are not liable for indirect or consequential damages beyond the order value. These Terms are governed by the laws of India, with disputes resolved amicably first, failing which subject to courts having jurisdiction over our place of business. We may revise these Terms from time to time.",
        ),

        const SizedBox(height: 16),
        // PART B — POLICIES
        const Text('POLICIES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
        const SizedBox(height: 12),
        const _PolicySection(
          title: 'Delivery Policy',
          body:
              'We aim to deliver within the timeline shown at order confirmation. Custom tailoring timelines vary with order complexity and season. We are not liable for delays caused by circumstances beyond our reasonable control.',
        ),
        const _PolicySection(
          title: 'Cancellation Policy',
          body:
              'Orders can be cancelled free of cost before stitching work begins, from the "My Orders" section. Once cutting/stitching has started, cancellation may involve a deduction for materials and labour already used.',
        ),
        const _PolicySection(
          title: 'Returns, Alteration & Refund Policy',
          body:
              'As products are custom-made, standard "return for any reason" policies do not apply. We offer free alterations within a specified period if the garment does not fit as per confirmed measurements. Refunds apply only for manufacturing defects, wrong items, or pre-stitching cancellations, credited within a reasonable number of business days.',
        ),
        const _PolicySection(
          title: 'Measurement, Fitting & Quality Assurance',
          body:
              'You are responsible for providing accurate measurements. We follow a quality check before dispatch covering stitching quality, measurement accuracy, and finishing. Report any genuine quality issue within the specified reporting window.',
        ),
        const _PolicySection(
          title: 'Grievance / Complaint Policy',
          body:
              'Raise any dissatisfaction through the Contact/Help section or our Grievance Redressal page. We aim to acknowledge and resolve complaints within a reasonable timeframe.',
        ),

        const SizedBox(height: 16),
        // PART C — LICENSES
        const Text('LICENSES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
        const SizedBox(height: 12),
        const _PolicySection(
          title: 'License to Use the Platform',
          body:
              'We grant you a limited, non-exclusive, non-transferable, revocable license to use the Platform for personal, non-commercial ordering purposes only.',
        ),
        const _PolicySection(
          title: 'Intellectual Property & Trademarks',
          body:
              'All content on the Platform — our brand name, logo, designs, photographs, text and graphics — is the property of Sumathi\'s Style. "Sumathi\'s Style" and associated branding are our trademarks; no license is granted to use them without our prior written permission.',
        ),
        const _PolicySection(
          title: 'User-Generated Content License',
          body:
              'If you upload reference images, design ideas, or reviews, you grant us a limited, non-exclusive license to use that content to process your order or — with separate consent — showcase customer feedback.',
        ),
        const _PolicySection(
          title: 'Third-Party / Open-Source & Restrictions',
          body:
              'Our app may include third-party or open-source components, each governed by their own license terms. You may not reverse-engineer the app, scrape data from the Platform, or remove proprietary notices. This license terminates automatically if you violate these restrictions.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // BROWSE FAQs PANEL — short set of email/mobile update questions.
  // ---------------------------------------------------------------
Widget _buildFaqPanel() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _panelHeader('Browse FAQs', Icons.help_outline),

      const SizedBox(height: 4),

      const Text(
        'Tap a question to view the answer.',
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.textLight,
        ),
      ),

      const SizedBox(height: 14),

      ..._faqData.asMap().entries.map((entry) {
        final index = entry.key;
        final faq = entry.value;
        final isOpen = _openFaq.contains(index);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOpen
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : const Color(0xFFE8E8E8),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() {
                  if (isOpen) {
                    _openFaq.remove(index);
                  } else {
                    _openFaq.add(index);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.help_outline,
                            size: 17,
                            color: AppColors.primary,
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            faq['q']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                              height: 1.35,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Icon(
                          isOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: isOpen
                              ? AppColors.primary
                              : AppColors.textLight,
                          size: 24,
                        ),
                      ],
                    ),

                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(
                          left: 42,
                          right: 8,
                          top: 13,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.055),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            faq['a']!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textLight,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                      crossFadeState: isOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 220),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),

      const SizedBox(height: 6),

      _plainSectionTitle('Account Actions'),

      const Text(
        'Need a break, or want to leave us for good? Choose an option below — each one explains exactly what happens before you confirm anything.',
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.textLight,
          height: 1.6,
        ),
      ),

      const SizedBox(height: 12),

      _menuCard(null, [
        _menuRow(
          Icons.person_off_outlined,
          'De-activate my Account',
          () => _openPanel(_Panel.deactivate),
          iconColor: AppColors.secondary,
        ),
        _menuRow(
          Icons.delete_outline,
          'Delete my Account',
          () => _openPanel(_Panel.deleteAccount),
          iconColor: AppColors.danger,
          labelColor: AppColors.danger,
        ),
      ]),
    ],
  );
}

  // ---------------------------------------------------------------
  // QUESTION & ANSWER PANEL — the original 10 order-related questions.
  // No Account Actions here — those live only under Browse FAQs.
  // ---------------------------------------------------------------
Widget _buildQnaPanel() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _panelHeader('Question and Answer', Icons.question_answer_outlined),

      const SizedBox(height: 4),

      const Text(
        'Tap a question to view the answer.',
        style: TextStyle(
          fontSize: 12.5,
          color: AppColors.textLight,
        ),
      ),

      const SizedBox(height: 14),

      ..._qnaData.asMap().entries.map((entry) {
        final index = entry.key;
        final faq = entry.value;
        final isOpen = _openQna.contains(index);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOpen
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : const Color(0xFFE8E8E8),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() {
                  if (isOpen) {
                    _openQna.remove(index);
                  } else {
                    _openQna.add(index);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.help_outline,
                            size: 17,
                            color: AppColors.primary,
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            faq['q']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                              height: 1.35,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Icon(
                          isOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: isOpen
                              ? AppColors.primary
                              : AppColors.textLight,
                          size: 24,
                        ),
                      ],
                    ),

                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(
                          left: 42,
                          right: 8,
                          top: 13,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.055),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            faq['a']!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textLight,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                      crossFadeState: isOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 220),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    ],
  );
}

  // ---------------------------------------------------------------
  // HELP CENTER PANEL (Drop Your Idea / Customer Support)
  // ---------------------------------------------------------------
  Widget _buildHelpPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Customer Support', Icons.support_agent),
        const SizedBox(height: 8),
        const Center(
          child: Icon(Icons.support_agent, size: 44, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        const Text(
          "We're Happy to Help!",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 10),
        const Text(
          "Have an idea to improve our app or a feature you'd like to see? "
          'Share your ideas, feedback, or suggestions with us. ' 
          'Your valuable input may help shape our future updates.',
          style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          "Whether it's about the app or our website, feel free to reach out to us here — we're happy to help either way.",
          style: TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _mailUs,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: AppColors.dark,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.email, size: 16),
            label: const Text('Mail Us'),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'divyadeveloper2025@gmail.com',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
  "Your feedback helps us make Sumathi's Style better with every update.",
  style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
  textAlign: TextAlign.center,
),
      ],
    );
  }

  // ---------------------------------------------------------------
  // MY REVIEWS PANEL — matches the Catering Reviews UI style.
  // ---------------------------------------------------------------
  double get _averageRating {
    if (_reviews.isEmpty) return 0;
    final total = _reviews.fold<int>(
      0,
      (sum, review) => sum + ((review['rating'] as num?)?.toInt() ?? 0),
    );
    return total / _reviews.length;
  }

  int _countForRating(int stars) {
    return _reviews.where((review) {
      return (review['rating'] as num?)?.toInt() == stars;
    }).length;
  }

  Widget _buildReviewsPanel() {
    final average = _averageRating;
    final ratingText = average == 0 ? '0.0' : average.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('My Reviews', Icons.star_outline),

        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!_user.isLoggedIn)
          _emptyState(
            Icons.star_outline,
            'Login required',
            'Login to see and write your reviews',
            'Login',
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          )
        else ...[
          // Rating summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      ratingText,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '★★★★★',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_reviews.length} reviews',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [5, 4, 3, 2, 1].map((stars) {
                      final count = _countForRating(stars);
                      final percent = _reviews.isEmpty
                          ? 0.0
                          : count / _reviews.length;

                      return _reviewRatingBar('$stars★', percent);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Logged-in user review prompt
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        _user.name.isNotEmpty
                            ? _user.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _user.name.isNotEmpty
                                ? 'Hi, ${_user.name}'
                                : 'Hi there',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                const Text(
                  'How was your experience?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => const Icon(
                      Icons.star_border_rounded,
                      color: AppColors.secondary,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _openReviewForm,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text(
                      'Write a review',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (_reviews.isEmpty)
            _emptyState(
              Icons.star_outline,
              'No reviews yet',
              'Share your experience about a product you ordered!',
              'Write a Review',
              _openReviewForm,
            )
          else
            ..._reviews.map(_reviewCard),
        ],
      ],
    );
  }

  Widget _reviewRatingBar(String label, double percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textLight,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 7,
                backgroundColor: AppColors.gray,
                valueColor: const AlwaysStoppedAnimation(
                  AppColors.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '${(percent * 100).round()}%',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final comment = review['comment']?.toString() ?? '';
    final rawName = review['name']?.toString().trim() ?? '';
    final displayName = rawName.isNotEmpty
        ? rawName
        : (_user.name.isNotEmpty ? _user.name : 'You');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: const Border(
          left: BorderSide(
            color: AppColors.secondary,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.primary,
                child: Text(
                  displayName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.text,
                      ),
                    ),

                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '★' * rating + '☆' * (5 - rating),
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 13,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Review options',
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: AppColors.textLight,
                ),
                onSelected: (value) {
                  if (value == 'edit') {
                    _editReview(review);
                  } else if (value == 'delete') {
                    _deleteReview(review);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                        SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textLight,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // shared empty state
  // ---------------------------------------------------------------
  Widget _emptyState(
    IconData icon,
    String title,
    String subtitle,
    String btnLabel,
    VoidCallback? onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          Icon(icon, size: 56, color: const Color(0xFFDDDDDD)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textLight,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
                   ElevatedButton(
            onPressed: onTap,
            style: _saveBtnStyle(),
            child: Text(btnLabel),
          ),
          ],
        ),
      ),
    );
  }
}
class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.6)),
        ],
      ),
    );
  }
}

/// Small reusable bullet line used across the Privacy Center panels.
class _BulletLine extends StatelessWidget {
  final String text;
  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('•  ', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// ORDER DETAILS PAGE — full order detail screen, opened when a My
/// Orders card is tapped. Shows product, order id (copyable), the same
/// status timeline used in the orders list, doorstep tips and our
/// delivery promise. Help sheet always shows 3 actions: Chat with us,
/// Cancel Order, and Download Invoice — Cancel Order and Download
/// Invoice are greyed-out / non-clickable when not currently eligible
/// (see _canCancelOrder and _canDownloadInvoice below), rather than
/// being hidden entirely.
/// ---------------------------------------------------------------------
 class OrderDetailsPage extends StatelessWidget {
  final MyOrder order;
  final SavedAddress? savedAddress;
  final String customerName;
  final String customerPhone;
  final VoidCallback? onCancelOrder;

  // Business contact/details used on the generated invoice.
  static const String _bizPhone = '+91 86107 03658';
  static const String _bizEmail = 'sumathisstyles@gmail.com';
  static const String _bizName = "Sumathi Tailoring and Fashion Designing";
  static const String _bizCategory = 'Clothing Store';
  static const String _bizAddress =
      '1/705, 9th St, Chozhamandala Devi Nagar, Devi Nagar, Cholamandalam, Injambakkam, Chennai, Tamil Nadu 600115';

  // Path to the business logo asset used on the invoice. Add the PNG
  // to your project's assets/ folder and register it in pubspec.yaml:
  //   flutter:
  //     assets:
  //       - assets/logo.png
  static const String _logoAssetPath = 'assets/logo.png';

  const OrderDetailsPage({
    super.key,
    required this.order,
    required this.savedAddress,
    this.customerName = '',
    this.customerPhone = '',
    this.onCancelOrder,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'Processing':
        return const Color(0xFFF57F17);
      case 'Shipping':
        return const Color(0xFF6A1B9A);
      case 'Delivered':
        return const Color(0xFF1565C0);
      case 'Cancelled':
        return AppColors.danger;
      default:
        return const Color(0xFFC9820A);
    }
  }

  // Cancel Order stays tappable only while the order is still in  // 'Ordered' status (admin hasn't moved it to Processing yet) AND
  // within this many days of being placed. Once either condition
  // fails, the button still shows in Help but is greyed out.
  static const int _cancelWindowDays = 5;

  bool get _canCancelOrder {
    if (order.status != 'Ordered') return false;
    final placedAt = order.orderedAtRaw;
    if (placedAt == null) return true; // older order with no saved timestamp
    return DateTime.now().difference(placedAt).inDays <= _cancelWindowDays;
  }

  // Invoice is only downloadable once admin has marked the order's
  // payment as successful (`payment_status` = 'paid'), and never for a
  // cancelled order.
     bool get _canDownloadInvoice =>
      order.paymentStatus.toLowerCase() == 'paid' && order.status != 'Cancelled';

  // Payment status pill shown on this page — 'paid' (from admin's
  // payment_status field) shows green "Paid", anything else (including
  // the default 'pending') shows amber/yellow "Payment Pending". Same
  // colour pair the admin dashboard uses for its own Pending/Paid badge,
  // so both sides read consistently.
  Widget _paymentStatusBadge() {
    final bool paid = order.paymentStatus.toLowerCase() == 'paid';
    final Color bg = paid ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final Color fg = paid ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paid ? Icons.check_circle : Icons.hourglass_top_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            paid ? 'Paid' : 'Payment Pending',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }

  void _copyOrderId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: order.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order ID copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  // -------------------------------------------------------------------
  // HELP SHEET — always shows 3 actions: Chat with us, Cancel Order,
  // Download Invoice. Cancel Order / Download Invoice are greyed-out
  // and non-clickable when not currently eligible instead of being
  // hidden.
  // -------------------------------------------------------------------
  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How can we help?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Order #${order.id}', style: const TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                const SizedBox(height: 16),
                _helpOption(
                  sheetCtx,
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat with us',
                  subtitle: 'Get instant automated answers, or type your own question',
                  enabled: true,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showChatSheet(context);
                  },
                ),
                _helpOption(
                  sheetCtx,
                  icon: Icons.cancel_outlined,
                  title: 'Cancel Order',
                  subtitle: _canCancelOrder
                      ? 'Cancel this order if stitching has not started'
                      : (order.status != 'Ordered'
                          ? 'Cancellation window closed — stitching has already started'
                          : 'Cancellation window has closed'),
                  danger: true,
                  enabled: _canCancelOrder,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    onCancelOrder?.call();
                  },
                ),
                _helpOption(
                  sheetCtx,
                  icon: Icons.receipt_long_outlined,
                  title: 'Download Invoice',
                  subtitle: _canDownloadInvoice
                      ? 'Get a PDF bill for this order'
                      : 'Available once payment is confirmed',
                  enabled: _canDownloadInvoice,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _downloadInvoice(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _helpOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
    bool enabled = true,
  }) {
    final color = !enabled ? AppColors.textLight : (danger ? AppColors.danger : AppColors.primary);
    return InkWell(
      onTap: enabled
          ? onTap
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title is not available right now'), duration: const Duration(seconds: 2)),
              );
            },
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: !enabled ? AppColors.textLight : (danger ? AppColors.danger : AppColors.text))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
                  ],
                ),
              ),
              Icon(enabled ? Icons.chevron_right : Icons.lock_outline, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // CHAT WITH US — a lightweight automated assistant. Questions are
  // shown one-by-one as a vertical list of separate cards (each with
  // its own spacing) — tap a question to instantly reveal its answer
  // in the chat below. Any custom message typed by the customer now
  // gets an automatic reply pointing them straight to Sumathi's Style
  // office contact number for direct help.
  // -------------------------------------------------------------------
  void _showChatSheet(BuildContext context) {
    final answers = <String, String>{
      'Where is my order?':
          'Your order is currently "${order.status}". You can also see the live status tracker on this page.',
      'How long does delivery take?':
          'Custom stitched orders are usually delivered within 10-15 days from order confirmation.',
      'Can I cancel my order?': _canCancelOrder
          ? "Yes, this order is still eligible for cancellation. Use the 'Cancel Order' option in Help."
          : "This order can no longer be cancelled from the app. Please call or mail us if it's urgent.",
      'I have a fitting issue':
          'For fitting issues, please contact us within 3 days of delivery — alteration is free of cost.',
      'How do I get a refund?':
          'Refunds (if applicable) are processed within 5-7 business days after a cancellation is confirmed.',
    };
    final messageCtrl = TextEditingController();
    final List<Map<String, String>> chat = [];
    final Set<String> askedQuestions = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: AppColors.primary,
                          child: Icon(Icons.support_agent, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Chat with us', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(onPressed: () => Navigator.pop(sheetCtx), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(12)),
                          child: const Text(
                            "Hi! I'm Sumathi's Style assistant. Tap a question below, one by one, or type your own.",
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Quiz-style: questions listed one per line, each in
                        // its own spaced card (not joined together) and
                        // tappable. Already-asked questions fade out.
                        ...answers.keys.map((q) {
                          final asked = askedQuestions.contains(q);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEDEDED)),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setSheet(() {
                                  askedQuestions.add(q);
                                  chat.add({'from': 'user', 'text': q});
                                  chat.add({'from': 'bot', 'text': answers[q]!});
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                child: Row(
                                  children: [
                                    Icon(
                                      asked ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 17,
                                      color: asked ? AppColors.success : AppColors.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        q,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: asked ? AppColors.textLight : AppColors.text,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 8),
                        ...chat.map((m) => Align(
                              alignment: m['from'] == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.72),
                                decoration: BoxDecoration(
                                  color: m['from'] == 'user' ? AppColors.primary : const Color(0xFFF0F0F0),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  m['text']!,
                                  style: TextStyle(fontSize: 12.5, color: m['from'] == 'user' ? Colors.white : AppColors.text),
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageCtrl,
                            decoration: InputDecoration(
                              hintText: 'Type your question...',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: AppColors.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final text = messageCtrl.text.trim();
                              if (text.isEmpty) return;
                              setSheet(() {
                                chat.add({'from': 'user', 'text': text});
                                // Any custom typed message gets an automatic
                                // reply directing the customer to call the
                                // Sumathi's Style office number directly.
                                chat.add({
                                  'from': 'bot',
                                  'text':
                                      "Thanks for your message! For a quicker response, please call our Sumathi's Style office directly at $_bizPhone and our team will assist you right away.",
                                });
                              });
                              messageCtrl.clear();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.send, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------
  // DOWNLOAD INVOICE — builds a one-page Sumathi's Style bill PDF with
  // the business logo + a small QR code (encodes the order id), our
  // business details, the customer's own delivery address, date/time,
  // order id, product details, delivery charge, product amount and
  // total, then opens the native share/print sheet.
  //
  // NOTE: the product description printed here is exactly what's saved
  // in the order's `product` field at checkout — if you want it to say
  // something like "Zari Silver Blouse" instead of just "blouse", save
  // that fuller description in the `product` field when the order is
  // placed (in your checkout code), not here.
  // -------------------------------------------------------------------
  Future<void> _downloadInvoice(BuildContext context) async {
    try {
      final doc = pw.Document();
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final ampm = now.hour >= 12 ? 'PM' : 'AM';
      final timeStr = '$hour12:${now.minute.toString().padLeft(2, '0')} $ampm';

      // Load the business logo from assets. If it isn't bundled yet,
      // fall back gracefully and just skip the logo image.
      pw.ImageProvider? logoImage;
      try {
        final logoBytes = await rootBundle.load(_logoAssetPath);
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {
        logoImage = null;
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pwContext) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoImage != null) ...[
                          pw.Container(
                            width: 34,
                            height: 34,
                            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                          ),
                          pw.SizedBox(width: 8),
                        ],
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Sumathi's Style",
                                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 2),
                            pw.Text('$_bizName — $_bizCategory',
                                style: const pw.TextStyle(fontSize: 9)),
                            pw.SizedBox(height: 2),
                            pw.Text('GSTIN: N/A', style: const pw.TextStyle(fontSize: 8.5)),
                          ],
                        ),
                      ],
                    ),
                    // Small GPay-scanner-style QR code — kept compact.
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: 'Order #${order.id}',
                      width: 42,
                      height: 42,
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.Center(
                  child: pw.Text('INVOICE / BILL OF SUPPLY',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text("Thank you for shopping with Sumathi's Style!",
                      style: const pw.TextStyle(fontSize: 10)),
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Mobile Number: $_bizPhone', style: const pw.TextStyle(fontSize: 10)),
                          pw.SizedBox(height: 3),
                          pw.Text('Email: $_bizEmail', style: const pw.TextStyle(fontSize: 10)),
                          pw.SizedBox(height: 3),
                          pw.Text('Address: $_bizAddress',
                              style: const pw.TextStyle(fontSize: 9.5)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 10)),
                          pw.SizedBox(height: 3),
                          pw.Text('Time: $timeStr', style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Text('Customer Details', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('Customer Name: ${customerName.isNotEmpty ? customerName : '-'}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 3),
                pw.Text(
                    'Customer Mobile Number: ${customerPhone.isNotEmpty ? '+91 $customerPhone' : '-'}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 3),
                pw.Text(
                    'Customer Address: ${savedAddress != null && savedAddress!.detail.isNotEmpty ? savedAddress!.detail : '-'}',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 18),
                pw.Text('Order Id: #${order.id}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 14),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(4),
                    1: pw.FlexColumnWidth(1),
                    2: pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _pdfCell('Product Details', bold: true),
                        _pdfCell('Qty', bold: true),
                        _pdfCell('Amount', bold: true),
                      ],
                    ),
                    pw.TableRow(children: [
                      _pdfCell(order.product.isNotEmpty ? order.product : '-'),
                      _pdfCell('1'),
                      _pdfCell('Rs. ${order.amount.toStringAsFixed(0)}'),
                    ]),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Product Amount: Rs. ${order.amount.toStringAsFixed(0)}',
                          style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 3),
                      pw.Text('Delivery Charge: Rs. 0', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 3),
                      pw.Text('Total: Rs. ${order.amount.toStringAsFixed(0)}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 26),
                pw.Divider(),
                pw.Center(
                  child: pw.Text("This is a computer-generated invoice from Sumathi's Style.",
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ),
              ],
            );
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'SumathiStyle_Invoice_${order.id}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate invoice: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

     Widget _cancelledTimeline() {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 14, color: AppColors.success),
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      constraints: const BoxConstraints(minHeight: 34),
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Order Confirmed',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                      const SizedBox(height: 4),
                      const Text('Your Order has been placed.',
                          style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      if (order.orderedAt.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(order.orderedAt, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.circle, size: 14, color: AppColors.danger),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cancelled',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
                    const SizedBox(height: 4),
                    const Text('Your order was cancelled as per your request.',
                        style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                    if (order.cancelledAt.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(order.cancelledAt, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeline() {
    final steps = [
      ('Order Confirmed', order.orderedAt),
      ('Processing', order.processingAt),
      ('Shipping', order.shippingAt),
      ('Delivery', order.deliveredAt),
    ];
    final reachedIndex = order.status == 'Delivered'
        ? 3
        : order.status == 'Shipping'
            ? 2
            : order.status == 'Processing'
                ? 1
                : 0;

    return Column(
      children: List.generate(steps.length, (index) {
        final label = steps[index].$1;
        final date = steps[index].$2;
        final reached = index <= reachedIndex;
        final isLast = index == steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Icon(
                    reached ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: reached ? AppColors.primary : const Color(0xFFBDBDBD),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        constraints: const BoxConstraints(minHeight: 34),
                        color: index < reachedIndex ? AppColors.primary : const Color(0xFFE0E0E0),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 34),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                          color: reached ? AppColors.text : AppColors.textLight,
                        ),
                      ),
                      if (reached && date.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(date, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0.5,
        title: const Text('Order Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.text)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: () => _showHelpSheet(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: Color(0xFFDDDDDD)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('Help', style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product row
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(10)),
                                       child: order.productImage.trim().isEmpty
                        ? const Icon(Icons.checkroom, color: AppColors.primary)
                        : Image.network(order.productImage, fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, __, ___) => const Icon(Icons.checkroom, color: AppColors.primary)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.product, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 6),
                        Text('₹${order.amount.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Order id with copy, plus the payment status badge alongside it.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _copyOrderId(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Order #${order.id}', style: const TextStyle(fontSize: 12.5, color: AppColors.textLight)),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy, size: 14, color: AppColors.textLight),
                    ],
                  ),
                ),
                _paymentStatusBadge(),
              ],
            ),
            const SizedBox(height: 14),

            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(order.status,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _statusColor(order.status))),
                      Icon(Icons.keyboard_arrow_up, color: Colors.grey.shade500),
                    ],
                  ),
                  const SizedBox(height: 14),
                                    if (order.status == 'Cancelled')
                    _cancelledTimeline()
                  else ...[
                    _timeline(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Custom stitched — delivered within 10-15 days from order confirmation.',
                              style: TextStyle(fontSize: 12, color: AppColors.textLight, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            const Text('Keep in mind at doorstep', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: AppColors.gray, borderRadius: BorderRadius.circular(8)),
                                       child: order.productImage.trim().isEmpty
                        ? const Icon(Icons.checkroom, color: AppColors.primary, size: 18)
                        : Image.network(order.productImage, fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorBuilder: (_, __, ___) => const Icon(Icons.checkroom, color: AppColors.primary, size: 18)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verify before accepting', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        SizedBox(height: 3),
                        Text('Please check your item at the doorstep before accepting the order.',
                            style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            if (savedAddress != null) ...[
              const Text('Delivery Address', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.home_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(savedAddress!.name.isNotEmpty ? savedAddress!.name : 'Home',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          const SizedBox(height: 3),
                          Text(savedAddress!.detail, style: const TextStyle(fontSize: 12.5, color: AppColors.textLight, height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
            ],

            const Text("Sumathi's Style Promise", style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEEEEE))),
              child: const Row(
                children: [
                  Icon(Icons.content_cut, size: 22, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alteration Available', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        SizedBox(height: 3),
                        Text('For fitting issues, contact us within 3 days of delivery for alteration.',
                            style: TextStyle(fontSize: 12, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}