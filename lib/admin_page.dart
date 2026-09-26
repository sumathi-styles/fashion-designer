import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:public_file_saver/public_file_saver.dart';
import 'services/onesignal_service.dart';

/// Sumathi's Styles — Admin Dashboard (Flutter + Firebase)
///
/// Firestore collections used:
///   products            — product catalogue
///   orders              — normal + customized orders (`source` field)
///   contacts            — boutique + catering contact form submissions
///   notifications       — admin broadcast notifications
///   reviews             — customer reviews
///   customer_requests   — data-export / grievance / deactivated /
///                         deleted-account requests (`type` field)
///   admin_tokens        — admin device FCM tokens
///
/// Put this file at: lib/admin_page.dart

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const String adminEmail = 'admin@sumathi.com';
  static const String adminPass = 'sumathi@1980';
  // ignore: unused_field
  static const String waNumber = '919876543210';

  final Color teal = const Color(0xFF00897B);
  final Color tealDark = const Color(0xFF00695C);
  final Color tealLight = const Color(0xFFE0F2F1);
  final Color copper = const Color(0xFFB87333);
  final Color copperLight = const Color(0xFFFFF8E1);
  final Color pageBg = const Color(0xFFF5F7FA);
  final Color sidebar = const Color(0xFF004D40);
  final Color danger = const Color(0xFFE53935);
  final Color success = const Color(0xFF43A047);
  final Color warning = const Color(0xFFFB8C00);
  final Color border = const Color(0xFFE0E0E0);
  final Color muted = const Color(0xFF757575);
  final Color loginBlue = const Color(0xFF2400F5);
  // ignore: unused_field
  final Color loginBlueDark = const Color(0xFF1A00C9);

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------- Admin push-alert (new order / contact) ----------------

  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _notifSetupDone = false;

  // Admin FCM device token
  String? _adminFcmToken;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersWatchSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsWatchSub;
  Set<String> _seenOrderIds = {};
  Set<String> _seenContactIds = {};
  int _newOrdersBadge = 0;
  int _newContactsBadge = 0;

  // ---------------- Voice-note playback (admin side) ----------------
  // Orders from the customer app store the voice note as a Base64 string
  // in Firestore (`voice_note_base64`), NOT as a URL — so it is decoded
  // and played from memory instead of being opened with url_launcher.
  final AudioPlayer _voicePlayer = AudioPlayer();
  String? _playingOrderId;
  bool _voiceLoading = false;

  bool loggedIn = false;
  bool loading = false;
  bool _obscurePassword = true;
  bool mobilePageMode = false;
  String currentPage = 'dashboard';
  String loginError = '';
  String toastMessage = '';
  DateTime? toastUntil;

  // ---------------- Revenue dashboard: period filter + PDF ----------------
  String revenuePeriod = 'month'; // 'week' | 'month' | 'year'
  bool pdfGenerating = false;

  // Which sub-section is showing inside the merged "Contact Form" hub.
  String contactHubTab = 'catering'; // 'catering' | 'custom'

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> contacts = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> reviews = [];
  List<Map<String, dynamic>> dataRequests = [];
  List<Map<String, dynamic>> grievances = [];
  List<Map<String, dynamic>> deactivated = [];
  List<Map<String, dynamic>> deletedAccounts = [];

  final TextEditingController productSearch = TextEditingController();
  final TextEditingController orderSearch = TextEditingController();
  final TextEditingController customSearch = TextEditingController();
  final TextEditingController customerListSearch = TextEditingController();
  final TextEditingController boutiqueSearch = TextEditingController();
  final TextEditingController cateringSearch = TextEditingController();
  final TextEditingController dataSearch = TextEditingController();
  final TextEditingController grievanceSearch = TextEditingController();
  final TextEditingController cancellationSearch = TextEditingController();
  final TextEditingController reviewSearch = TextEditingController();

  String productCategory = '';
  String productStock = '';
  String orderStatus = '';
  String grievanceStatus = '';

  final TextEditingController pName = TextEditingController();
  final TextEditingController pPrice = TextEditingController();
  final TextEditingController pDesc = TextEditingController();
  String pCategory = '';
  String pStock = 'Available';
  String pVisible = 'yes';
  List<XFile> uploadedPhotos = [];
  final TextEditingController pImageUrl = TextEditingController();
  List<TextEditingController> highlightControllers = [TextEditingController()];
  List<TextEditingController> priceTagControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  final TextEditingController notificationTitle = TextEditingController();
  final TextEditingController notificationMessage = TextEditingController();
  String notificationType = 'general';

  @override
  void initState() {
    super.initState();
    _restoreLogin();
    // Reset the playing-row indicator once a voice note finishes so the
    // icon flips back from "pause" to "play" automatically.
    _voicePlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playingOrderId = null);
    });
  }

  @override
  void dispose() {
    for (final c in [
      emailController,
      passwordController,
      productSearch,
      orderSearch,
      customSearch,
      customerListSearch,
      boutiqueSearch,
      cateringSearch,
      dataSearch,
      grievanceSearch,
      cancellationSearch,
      reviewSearch,
      pName,
      pPrice,
      pDesc,
      pImageUrl,
      notificationTitle,
      notificationMessage,
    ]) {
      c.dispose();
    }
    for (final c in highlightControllers) {
      c.dispose();
    }
    for (final c in priceTagControllers) {
      c.dispose();
    }
    _ordersWatchSub?.cancel();
    _contactsWatchSub?.cancel();
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _restoreLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ss_admin_logged') == true) {
      setState(() => loggedIn = true);
      await initDashboard();
      await _setupNotifications();
    }
  }

  Future<void> doLogin() async {
    final e = emailController.text.trim();
    final p = passwordController.text.trim();

    if (e == adminEmail && p == adminPass) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ss_admin_logged', true);
      setState(() {
        loggedIn = true;
        loginError = '';
      });
      await initDashboard();
      await _setupNotifications();
    } else {
      setState(() => loginError = '❌ Wrong email or password');
    }
  }

  Future<void> doLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ss_admin_logged');
    await _ordersWatchSub?.cancel();
    await _contactsWatchSub?.cancel();
    _ordersWatchSub = null;
    _contactsWatchSub = null;
    _notifSetupDone = false;
    setState(() {
      loggedIn = false;
      currentPage = 'dashboard';
      mobilePageMode = false;
      emailController.clear();
      passwordController.clear();
      _newOrdersBadge = 0;
      _newContactsBadge = 0;
    });
  }

  // ---------------- Admin push-alert setup ----------------

  Future<void> _setupNotifications() async {
    if (_notifSetupDone) return;
    _notifSetupDone = true;

    _localNotifications = FlutterLocalNotificationsPlugin();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _localNotifications!.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Ask notification permission for the ADMIN device.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

          // 🔑 Tag this device as "admin" so OneSignal pushes targeting the
    // admin role reach it — this is what makes the notification sound
    // work even when the app is fully closed.
    OneSignalService.instance.setRoleTag('admin');

    // Save the current token once.
    _adminFcmToken = await FirebaseMessaging.instance.getToken();
    debugPrint('ADMIN FCM TOKEN: $_adminFcmToken');
    await _saveAdminFcmToken();

    // Keep token updated if Firebase refreshes it.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      _adminFcmToken = token;
      debugPrint('ADMIN FCM TOKEN REFRESHED: $token');
      await _saveAdminFcmToken();
    });

    _watchOrders();
    _watchContacts();
  }

  /// Stores this admin device's FCM token in Firestore so a server / cloud
  /// function can push alerts to it later.
  Future<void> _saveAdminFcmToken() async {
    final token = _adminFcmToken;
    if (token == null || token.isEmpty) return;
    try {
      await _db.collection('admin_tokens').doc(token).set({
        'token': token,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Could not save admin FCM token: $e');
    }
  }

  void _watchOrders() {
    bool isFirstSnapshot = true;

    _ordersWatchSub = _db.collection('orders').snapshots().listen((snap) {
      if (isFirstSnapshot) {
        isFirstSnapshot = false;
        _seenOrderIds = snap.docs.map((d) => d.id).toSet();
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added &&
            !_seenOrderIds.contains(change.doc.id)) {
          _seenOrderIds.add(change.doc.id);

          final m = change.doc.data() ?? {};
          final isCustom =
              '${m['source'] ?? ''}'.toLowerCase() == 'custom-order';

          _showLocalNotification(
            title: isCustom
                ? '✂️ New Customized Order'
                : '🛒 New Order Received',
            body:
                '${m['name'] ?? 'Customer'} — ${m['product'] ?? ''}'
                '${isCustom ? '' : ' (₹${m['amount'] ?? 0})'}',
          );

          if (mounted) setState(() => _newOrdersBadge++);
        }
      }
    });
  }

  void _watchContacts() {
    bool isFirstSnapshot = true;

    _contactsWatchSub = _db.collection('contacts').snapshots().listen((snap) {
      if (isFirstSnapshot) {
        isFirstSnapshot = false;
        _seenContactIds = snap.docs.map((d) => d.id).toSet();
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added &&
            !_seenContactIds.contains(change.doc.id)) {
          _seenContactIds.add(change.doc.id);

          final m = change.doc.data() ?? {};

          _showLocalNotification(
            title: '📨 New Contact Form Submission',
            body:
                '${m['name'] ?? 'Someone'} — ${m['service'] ?? m['message'] ?? ''}',
          );

          if (mounted) setState(() => _newContactsBadge++);
        }
      }
    });
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (_localNotifications == null) return;

    const androidDetails = AndroidNotificationDetails(
      'sumathi_admin_channel',
      'Sumathi Styles Admin Alerts',
      channelDescription: 'New order and contact form alerts',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications!.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  Future<void> initDashboard() async {
    await refreshDashboard();
    await loadContacts();
    await loadNotifications();
    await loadReviews();
    await loadCustomerRequests();
  }

  Future<void> refreshDashboard() async {
    final loadedProducts = await loadProductsFromServer();
    final loadedOrders = await loadOrdersFromServer();
    if (!mounted) return;
    setState(() {
      products = loadedProducts;
      orders = loadedOrders;
    });
  }

  // ---------------- FIRESTORE READS ----------------

  Future<List<Map<String, dynamic>>> loadOrdersFromServer() async {
    try {
      final snap = await _db.collection('orders').get();
      final mapped = snap.docs.map<Map<String, dynamic>>((doc) {
        final m = doc.data();
        final createdAt = m['created_at'];
        DateTime? created;
        if (createdAt is Timestamp) created = createdAt.toDate();

        String statusDate(String key) {
          final ts = m[key];
          if (ts is Timestamp) {
            return formatDateTime(ts.toDate().toIso8601String());
          }
          return '';
        }

        return {
          'id': doc.id,
          'orderId': '#${m['order_id'] ?? doc.id.toUpperCase()}',
          'name': m['name'] ?? '',
          'mobile': m['mobile'] ?? '',
          'alternateMobile': m['alternate_mobile'] ?? '',
          'product': m['product'] ?? '',
          'amount': num.tryParse('${m['amount'] ?? 0}') ?? 0,
          'status': m['status'] ?? 'Ordered',
          'date': created != null ? formatDate(created.toIso8601String()) : '',
          // Raw creation instant (date + time), kept only for sorting —
          // the 'date' field above is display-only (dd/MM/yyyy) and loses
          // ordering information for orders placed on the same day.
          '_createdAtRaw': created,
          'orderedAt': statusDate('ordered_at'),
          'processingAt': statusDate('processing_at'),
          'deliveredAt': statusDate('delivered_at'),
          'cancelledAt': statusDate('cancelled_at'),
          'source': m['source'] ?? 'website',
          'measurement': m['measurement'] ?? '',
          // The customer app stores the recorded voice note as a Base64
          // string under `voice_note_base64`. Older records (or another
          // source) may still have a plain URL under `voice_note`, so
          // fall back to that if present.
          'voiceNote': m['voice_note_base64'] ?? m['voice_note'] ?? '',
          'notes': m['notes'] ?? '',
          'cancelReason': m['cancel_reason'] ?? '',
          'paymentMethod': m['payment_method'] ?? 'N/A',
          'paymentStatus': m['payment_status'] ?? 'Pending',
          'address': m['address'] ?? '',
          'distanceKm': m['distance_km'] ?? '',
          'deliveryCharge': m['delivery_charge'] ?? '',
          'rating': m['rating'] ?? '',
          'feedback': m['feedback_text'] ?? '',
        };
      }).toList();

      // Keep a stable order — oldest first, using the actual creation
      // timestamp (not the display-only dd/MM/yyyy string, which cannot
      // tell apart same-day orders). `.reversed` (used all over this
      // file) then shows the newest order first, in true chronological
      // (and matching order-ID) sequence.
      mapped.sort((a, b) {
        final da = a['_createdAtRaw'] as DateTime?;
        final db = b['_createdAtRaw'] as DateTime?;
        if (da == null && db == null) return 0;
        if (da == null) return -1;
        if (db == null) return 1;
        return da.compareTo(db);
      });
      return mapped;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> loadProductsFromServer() async {
    try {
      final snap = await _db.collection('products').get();
      return snap.docs.map<Map<String, dynamic>>((doc) {
        final m = doc.data();
        final photos = m['photos'] is List
            ? List<dynamic>.from(m['photos'])
            : (m['image_url'] != null && '${m['image_url']}'.isNotEmpty
                  ? [m['image_url']]
                  : <dynamic>[]);
        return {
          'id': doc.id,
          'name': m['name'] ?? '',
          'cat': m['category'] ?? m['cat'] ?? 'Other',
          'category': m['category'] ?? m['cat'] ?? 'Other',
          'price': num.tryParse('${m['price'] ?? 0}') ?? 0,
          'desc': m['description'] ?? '',
          'description': m['description'] ?? '',
          'stock': m['stock'] ?? 'Available',
          'visible': (m['visible'] == 'yes' || m['visible'] == true)
              ? 'yes'
              : 'no',
          'photos': photos,
          'photo': photos.isNotEmpty ? photos.first : '',
          'highlights': m['highlights'] is List
              ? List<dynamic>.from(m['highlights'])
              : [],
          'priceTags': m['price_tags'] is List
              ? List<dynamic>.from(m['price_tags'])
              : [],
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> loadContacts() async {
    try {
      final snap = await _db.collection('contacts').get();
      contacts = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        final createdAt = m['created_at'];
        if (createdAt is Timestamp) {
          m['created_at'] = createdAt.toDate().toIso8601String();
        }
        return m;
      }).toList();
    } catch (_) {
      contacts = [];
    }
    if (mounted) setState(() {});
  }

  Future<void> loadNotifications() async {
    try {
      final snap = await _db.collection('notifications').get();
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        final createdAt = m['created_at'];
        if (createdAt is Timestamp) {
          m['created_at'] = createdAt.toDate().toIso8601String();
        }
        return m;
      }).toList();
      list.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      notifications = list;
    } catch (_) {
      notifications = [];
    }
    if (mounted) setState(() {});
  }

  /// Loads customer reviews (Firestore collection `reviews`: name, mobile,
  /// rating, comment, createdAt). Sorted newest-first.
  Future<void> loadReviews() async {
    try {
      final snap = await _db.collection('reviews').get();
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        final createdAt = m['createdAt'] ?? m['created_at'];
        if (createdAt is Timestamp) {
          m['createdAt'] = createdAt.toDate().toIso8601String();
        } else if (createdAt != null) {
          m['createdAt'] = '$createdAt';
        }
        return m;
      }).toList();
      list.sort(
        (a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'),
      );
      reviews = list;
    } catch (_) {
      reviews = [];
    }
    if (mounted) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _customerRequestsByType(
    String type,
    String dateField,
  ) async {
    try {
      final snap = await _db
          .collection('customer_requests')
          .where('type', isEqualTo: type)
          .get();
      return snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        final ts = m[dateField];
        if (ts is Timestamp) m[dateField] = ts.toDate().toIso8601String();
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> loadCustomerRequests() async {
    dataRequests = await _customerRequestsByType('data_export', 'requested_at');
    grievances = await _customerRequestsByType('grievance', 'created_at');
    deactivated = await _customerRequestsByType(
      'deactivated',
      'deactivated_at',
    );
    deletedAccounts = await _customerRequestsByType(
      'deleted_account',
      'deleted_at',
    );
    if (mounted) setState(() {});
  }

  String formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return '';
    try {
      final d = DateTime.parse(value.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return value.toString();
    }
  }

  String formatDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) return '';
    try {
      final d = DateTime.parse(value.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}, '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  void showToast(String msg) {
    setState(() {
      toastMessage = msg;
      toastUntil = DateTime.now().add(const Duration(seconds: 3));
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (toastUntil != null && DateTime.now().isAfter(toastUntil!)) {
        setState(() => toastMessage = '');
      }
    });
  }

  // ---------------- Shared blue AppBar + swipe-back navigation ----------------

  PreferredSizeWidget _blueAppBar(String title) {
    return AppBar(
      backgroundColor: loginBlue,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Pushes a full page with the blue app bar + real swipe-back gesture.
  Future<void> _pushPage(String title, Widget body) {
    return Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: pageBg,
          appBar: _blueAppBar(title),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  void showPage(String id) {
    setState(() {
      currentPage = id;
    });
    if (id == 'dashboard') refreshDashboard();
    if (id == 'products') loadProductsAndSet();
    if (id == 'ordersmgmt') loadOrdersAndSet();
    if (id == 'customers') loadOrdersAndSet();
    if (id == 'contactformhub') {
      loadContacts();
      loadOrdersAndSet();
    }
    if (id == 'notifications') loadNotifications();
    if (id == 'reviews') loadReviews();
    if (id == 'datarequests') loadCustomerRequests();
    if (id == 'grievances') loadCustomerRequests();
    if (id == 'revenue' || id == 'analysis') loadOrdersAndSet();
  }

  Future<void> loadProductsAndSet() async {
    final p = await loadProductsFromServer();
    if (mounted) setState(() => products = p);
  }

  Future<void> loadOrdersAndSet() async {
    final o = await loadOrdersFromServer();
    if (mounted) setState(() => orders = o);
  }

  bool isCatering(Map<String, dynamic> c) {
    final service = '${c['service'] ?? ''}'.toLowerCase();
    final formType =
        '${c['form_type'] ?? c['type'] ?? c['page'] ?? c['source'] ?? ''}'
            .toLowerCase();
    if (formType.contains('boutique') || service.contains('boutique')) {
      return false;
    }
    if (formType.contains('catering') || service.contains('catering')) {
      return true;
    }
    const keys = [
      'catering',
      'food',
      'meal',
      'lunch',
      'dinner',
      'breakfast',
      'tiffin',
      'party food',
      'wedding food',
    ];
    final combined = '$service $formType';
    return keys.any(combined.contains);
  }

  List<Map<String, dynamic>> get boutiqueContacts =>
      contacts.where((c) => !isCatering(c)).toList();

  List<Map<String, dynamic>> get cateringContacts =>
      contacts.where(isCatering).toList();

  List<Map<String, dynamic>> get pendingOrders => orders
      .where(
        (o) =>
            o['status'] == 'Ordered' ||
            o['status'] == 'Processing' ||
            o['status'] == 'Shipping',
      )
      .toList();

  List<Map<String, dynamic>> get deliveredOrders =>
      orders.where((o) => o['status'] == 'Delivered').toList();

  num get revenue =>
      deliveredOrders.fold<num>(0, (s, o) => s + (o['amount'] ?? 0));

  /// Orders created TODAY only — resets automatically next day.
  int get todaysOrdersCount {
    final today = formatDate(DateTime.now().toIso8601String());
    return orders.where((o) => '${o['date']}' == today).length;
  }

  /// Total ₹ value of orders placed TODAY (any status).
  num get todaysRevenue {
    final today = formatDate(DateTime.now().toIso8601String());
    return orders
        .where((o) => '${o['date']}' == today)
        .fold<num>(0, (s, o) => s + (o['amount'] ?? 0));
  }

  // ---------------- SALES COMPARISON ----------------

  /// Revenue from DELIVERED orders placed today only.
  num get salesToday {
    final today = formatDate(DateTime.now().toIso8601String());
    return deliveredOrders
        .where((o) => '${o['date']}' == today)
        .fold<num>(0, (s, o) => s + (o['amount'] ?? 0));
  }

  num get salesThisWeek =>
      ordersForPeriod('week').fold<num>(0, (s, o) => s + (o['amount'] ?? 0));

  num get salesThisMonth =>
      ordersForPeriod('month').fold<num>(0, (s, o) => s + (o['amount'] ?? 0));

  num get salesThisYear =>
      ordersForPeriod('year').fold<num>(0, (s, o) => s + (o['amount'] ?? 0));

  /// "Sales Comparison" box — Today / This Week / This Month / This Year.
  Widget _salesComparisonBox() {
    final rows = [
      ('Today', salesToday, const Color(0xFFFB8C00)),
      ('This Week', salesThisWeek, const Color(0xFF1976D2)),
      ('This Month', salesThisMonth, const Color(0xFF43A047)),
      ('This Year', salesThisYear, const Color(0xFF8E24AA)),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.show_chart, size: 18, color: Color(0xFF616161)),
              SizedBox(width: 8),
              Text(
                'Sales Comparison',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: pageBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: row.$3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₹${row.$2.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: row.$3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "Day" summary box — today's order count + today's order value.
  Widget _dayBox() {
    final today = DateTime.now();
    final label = '${today.day} ${monthName(today.month)} ${today.year}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tealDark, teal]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAY — $label',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$todaysOrdersCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Orders Today',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${todaysRevenue.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Amount Today',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Revenue period filter helpers ----------------

  /// Parses the 'dd/MM/yyyy' strings produced by formatDate().
  DateTime? _parseOrderDate(String s) {
    final parts = s.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  /// Delivered orders inside the selected period.
  List<Map<String, dynamic>> ordersForPeriod(String period) {
    final now = DateTime.now();
    return deliveredOrders.where((o) {
      final d = _parseOrderDate('${o['date']}');
      if (d == null) return false;
      switch (period) {
        case 'week':
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final weekStart = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          return !d.isBefore(weekStart) && !d.isAfter(now);
        case 'year':
          return d.year == now.year;
        case 'month':
        default:
          return d.year == now.year && d.month == now.month;
      }
    }).toList();
  }

  String periodLabel(String period) {
    switch (period) {
      case 'week':
        return 'THIS WEEK';
      case 'year':
        return 'THIS YEAR';
      case 'month':
      default:
        return 'THIS MONTH';
    }
  }

  // ---------------- PDF export ----------------

  Future<void> downloadRevenuePdf() async {
    final periodOrders = ordersForPeriod(revenuePeriod)
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    if (periodOrders.isEmpty) {
      showToast('⚠️ No delivered orders in this period to export');
      return;
    }
    setState(() => pdfGenerating = true);
    try {
      final total = periodOrders.fold<num>(0, (s, o) => s + (o['amount'] ?? 0));
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Text(
              "Sumathi's Styles — Revenue Report",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Period: ${periodLabel(revenuePeriod)}   |   '
              'Generated: ${formatDate(DateTime.now().toIso8601String())}',
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: ['Order ID', 'Customer', 'Product', 'Amount (₹)', 'Date'],
              data: periodOrders
                  .map(
                    (o) => [
                      '${o['orderId']}',
                      '${o['name']}',
                      '${o['product']}',
                      '${o['amount']}',
                      '${o['date']}',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Orders: ${periodOrders.length}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Total Revenue: ₹${total.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final bytes = await doc.save();

      final fileName =
          'revenue_${revenuePeriod}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final fileSaver = PublicFileSaver();

      final result = await fileSaver.saveBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'application/pdf',
        subDir: 'Sumathis Styles',
      );

      if (result != null && result.isSuccess) {
        showToast('✅ PDF downloaded successfully');
      } else {
        showToast('❌ PDF download failed');
      }
    } catch (e) {
      showToast('❌ Could not generate PDF: $e');
    } finally {
      if (mounted) setState(() => pdfGenerating = false);
    }
  }

  // ---------------- Product purchase analysis ----------------

  /// How many DELIVERED orders each product name appears in.
  Map<String, int> productPurchaseCounts(List<Map<String, dynamic>> source) {
    final map = <String, int>{};
    for (final o in source) {
      final name = '${o['product'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      map[name] = (map[name] ?? 0) + 1;
    }
    return map;
  }

  String titleFor(String id) {
    const map = {
      'dashboard': 'Dashboard',
      'upload': 'Product Upload',
      'products': 'All Products',
      'ordersmgmt': 'Orders',
      'customers': 'Customers',
      'contactformhub': 'Contact Form',
      'notifications': 'Send Notification',
      'reviews': 'Customer Reviews',
      'datarequests': 'Cancellation Msg',
      'grievances': 'Complaints',
      'revenue': 'Revenue',
      'analysis': 'Product Analysis',
    };
    return map[id] ?? 'Dashboard';
  }

  Color _statusSolidColor(String status) {
    switch (status) {
      case 'Ordered':
        return const Color(0xFF1565C0);
      case 'Processing':
        return const Color(0xFF6A1B9A);
      case 'Shipping':
        return const Color(0xFF0277BD);
      case 'Delivered':
        return success;
      case 'Cancelled':
        return danger;
      default:
        return warning;
    }
  }

  /// Small pastel pill — same look as `StatusBadge` — used as the visible
  /// face of the status-change control. Fixed size, never grows.
  Widget _statusPillLikeBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Ordered':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        break;
      case 'Processing':
        bg = const Color(0xFFEDE7F6);
        fg = const Color(0xFF4527A0);
        break;
      case 'Shipping':
        bg = const Color(0xFFE1F5FE);
        fg = const Color(0xFF0277BD);
        break;
      case 'Delivered':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case 'Cancelled':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFE53935);
        break;
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 14, color: fg),
        ],
      ),
    );
  }

  /// Reusable status-change control — a small fixed-size pill wrapped in a
  /// PopupMenuButton (not a DropdownButton, which forced a ~48dp minimum
  /// height and bloated rows on mobile).
  Widget _statusChangeControl(String orderId, String currentStatus) {
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      padding: EdgeInsets.zero,
      onSelected: (v) => updateStatus(orderId, v),
      itemBuilder: (context) => [
        'Ordered',
        'Processing',
        'Shipping',
        'Delivered',
        'Cancelled',
      ]
          .map(
            (s) => PopupMenuItem(
              value: s,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _statusSolidColor(s),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(s, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          )
          .toList(),
      child: _statusPillLikeBadge(currentStatus),
    );
  }

  // ---------------- IMAGE URL HELPER ----------------

  /// Converts a Google Drive "share" link into a direct-viewable image URL.
  /// Any other URL (Imgur, Firebase Storage, etc.) is returned unchanged.
  String _normalizeImageUrl(String url) {
    final m1 = RegExp(
      r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)',
    ).firstMatch(url);
    if (m1 != null) {
      return 'https://drive.google.com/uc?export=view&id=${m1.group(1)}';
    }
    final m2 = RegExp(
      r'drive\.google\.com/open\?id=([a-zA-Z0-9_-]+)',
    ).firstMatch(url);
    if (m2 != null) {
      return 'https://drive.google.com/uc?export=view&id=${m2.group(1)}';
    }
    return url;
  }

  String _productImageFor(String productName) {
    final match = products.firstWhere(
      (p) => '${p['name']}' == productName,
      orElse: () => {},
    );
    final photos = match['photos'] is List
        ? List.from(match['photos'])
        : <dynamic>[];
    final raw = photos.isNotEmpty
        ? '${photos.first}'
        : '${match['photo'] ?? ''}';
    return raw.isNotEmpty ? _normalizeImageUrl(raw) : '';
  }

  // ---------------- VOICE NOTE PLAYBACK HELPER ----------------

  /// Plays (or pauses) a voice note stored as a Base64 string, straight
  /// from memory — no temp file, no URL needed.
  Future<void> _toggleVoicePlayback(String orderId, String base64Data) async {
    if (base64Data.trim().isEmpty) {
      showToast('⚠️ No voice note for this order');
      return;
    }

    if (_playingOrderId == orderId) {
      await _voicePlayer.stop();
      if (mounted) setState(() => _playingOrderId = null);
      return;
    }

    try {
      setState(() => _voiceLoading = true);
      await _voicePlayer.stop();
      final bytes = Uint8List.fromList(base64Decode(base64Data));
      await _voicePlayer.play(BytesSource(bytes));
      if (!mounted) return;
      setState(() {
        _playingOrderId = orderId;
        _voiceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingOrderId = null;
        _voiceLoading = false;
      });
      showToast('❌ Could not play voice note: $e');
    }
  }

  /// Small reusable Play/Pause button for a Voice Note table cell.
  Widget voiceNoteButton(String orderId, String base64Data) {
    if (base64Data.trim().isEmpty) {
      return Text('—', style: TextStyle(color: muted));
    }
    final isThisPlaying = _playingOrderId == orderId;
    return TextButton.icon(
      onPressed: () => _toggleVoicePlayback(orderId, base64Data),
      icon: (isThisPlaying && _voiceLoading)
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isThisPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 18,
              color: teal,
            ),
      label: Text(
        isThisPlaying ? 'Pause' : 'Play',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  // ---------------- PRODUCT UPLOAD (Firestore + Storage) ----------------

  Future<void> uploadProduct() async {
    final name = pName.text.trim();
    final price = pPrice.text.trim();
    if (name.isEmpty || pCategory.isEmpty || price.isEmpty) {
      showToast('⚠️ Name, Category & Price are required!');
      return;
    }

    final highlights = highlightControllers
        .map((c) => c.text.trim())
        .where((x) => x.isNotEmpty)
        .toList();

    final priceTags = <Map<String, dynamic>>[];
    for (int i = 0; i + 1 < priceTagControllers.length; i += 2) {
      final label = priceTagControllers[i].text.trim();
      final value = priceTagControllers[i + 1].text.trim();
      if (label.isNotEmpty && value.isNotEmpty) {
        priceTags.add({'label': label, 'price': value});
      }
    }

    setState(() => loading = true);
    try {
      // Photo URLs come from TWO sources: files picked with the picker
      // (uploaded to Firebase Storage) and a pasted image link (free).
      final List<String> photoUrls = [];

      for (final photo in uploadedPhotos) {
        try {
          final bytes = await photo.readAsBytes();
          final ref = FirebaseStorage.instance.ref(
            'product_photos/${DateTime.now().millisecondsSinceEpoch}_${photo.name}',
          );
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
          photoUrls.add(await ref.getDownloadURL());
        } catch (e) {
          debugPrint('❌ Firebase Storage upload failed: $e');
          showToast('❌ Image upload failed: $e');
        }
      }

      final pastedUrl = pImageUrl.text.trim();
      if (pastedUrl.isNotEmpty) {
        photoUrls.add(_normalizeImageUrl(pastedUrl));
      }

      await _db.collection('products').add({
        'name': name,
        'category': pCategory,
        'cat': pCategory,
        'price': num.tryParse(price) ?? 0,
        'description': pDesc.text.trim(),
        'stock': pStock,
        'visible': pVisible,
        'highlights': highlights,
        'price_tags': priceTags,
        'photos': photoUrls,
        'image_url': photoUrls.isNotEmpty ? photoUrls.first : '',
        'created_at': FieldValue.serverTimestamp(),
      });

      products = await loadProductsFromServer();
      resetUploadForm();
      showToast('✅ Product uploaded successfully!');
    } catch (e) {
      showToast('❌ Upload failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pickPhotos() async {
    final files = await picker.pickMultiImage(
      imageQuality: 60,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (files.isNotEmpty) {
      setState(() => uploadedPhotos.addAll(files));
    }
  }

  void resetUploadForm() {
    pName.clear();
    pPrice.clear();
    pDesc.clear();
    pImageUrl.clear();
    setState(() {
      pCategory = '';
      pStock = 'Available';
      pVisible = 'yes';
      uploadedPhotos.clear();
      for (final c in highlightControllers) {
        c.dispose();
      }
      for (final c in priceTagControllers) {
        c.dispose();
      }
      highlightControllers = [TextEditingController()];
      priceTagControllers = [TextEditingController(), TextEditingController()];
    });
  }

  void showProductDetail(Map<String, dynamic> product) {
    final photos = product['photos'] is List
        ? List.from(product['photos'])
        : <dynamic>[];
    final image = photos.isNotEmpty
        ? _normalizeImageUrl('${photos.first}')
        : '${product['photo'] ?? ''}';
    final highlights = product['highlights'] is List
        ? List<dynamic>.from(product['highlights'])
        : <dynamic>[];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${product['name']}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (image.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      color: tealLight,
                      // FIX: was BoxFit.cover, which cropped the top of
                      // the photo (the model's face). contain + top
                      // alignment keeps the full photo visible.
                      child: Image.network(
                        image,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '₹${product['price']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tealDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${product['category'] ?? product['cat']}',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
                Text('${product['description'] ?? product['desc'] ?? ''}'),
                if (highlights.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...highlights.map((h) => Text('✨ $h')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---------------- EDIT PRODUCT ----------------

  Future<void> editProduct(Map<String, dynamic> product) async {
    final nameController = TextEditingController(
      text: '${product['name'] ?? ''}',
    );
    final priceController = TextEditingController(
      text: '${product['price'] ?? ''}',
    );
    final descController = TextEditingController(
      text: '${product['description'] ?? product['desc'] ?? ''}',
    );

    String editCategory = '${product['category'] ?? product['cat'] ?? ''}';
    String editStock = '${product['stock'] ?? 'Available'}';
    String editVisible = '${product['visible'] ?? 'yes'}';

    final existingHighlights = product['highlights'] is List
        ? List<dynamic>.from(product['highlights'])
        : <dynamic>[];
    final highlightEdits = existingHighlights
        .map((e) => TextEditingController(text: '$e'))
        .toList();
    if (highlightEdits.isEmpty) {
      highlightEdits.add(TextEditingController());
    }

    final existingPriceTags = product['priceTags'] is List
        ? List<dynamic>.from(product['priceTags'])
        : <dynamic>[];
    final priceTagEdits = <TextEditingController>[];

    for (final tag in existingPriceTags) {
      if (tag is Map) {
        priceTagEdits.add(TextEditingController(text: '${tag['label'] ?? ''}'));
        priceTagEdits.add(TextEditingController(text: '${tag['price'] ?? ''}'));
      }
    }
    if (priceTagEdits.isEmpty) {
      priceTagEdits.add(TextEditingController());
      priceTagEdits.add(TextEditingController());
    }

    bool saving = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, dialogSetState) {
              final categories = [
                'All',
                'Kids',
                'Uniform',
                'Modern',
                'Salwar',
                'Blouse',
                'Aari',
                'Saree',
                'Frock',
                'Lehenga',
                'Kurthi',
              ];

              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.edit_outlined, color: teal),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Edit Product',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        field(
                          'Product Name *',
                          nameController,
                          hint: 'Product name',
                        ),
                        const SizedBox(height: 14),
                        dropdownField(
                          'Category *',
                          editCategory,
                          categories,
                          (v) => dialogSetState(() => editCategory = v ?? ''),
                        ),
                        const SizedBox(height: 14),
                        field(
                          'Amount / Price (₹) *',
                          priceController,
                          hint: 'e.g. 1500',
                          keyboard: TextInputType.number,
                        ),
                        const SizedBox(height: 14),
                        field(
                          'Description',
                          descController,
                          hint: 'Product description...',
                          maxLines: 4,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '✨ PRODUCT HIGHLIGHTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(highlightEdits.length, (i) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: field(
                                    '',
                                    highlightEdits[i],
                                    hint: 'e.g. Premium quality fabric',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove highlight',
                                  color: danger,
                                  onPressed: highlightEdits.length > 1
                                      ? () {
                                          dialogSetState(() {
                                            highlightEdits[i].dispose();
                                            highlightEdits.removeAt(i);
                                          });
                                        }
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () {
                            dialogSetState(
                              () => highlightEdits.add(TextEditingController()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Highlight'),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '🏷️ PRICE TAGS (size/type variations)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(priceTagEdits.length ~/ 2, (i) {
                          final labelController = priceTagEdits[i * 2];
                          final valueController = priceTagEdits[i * 2 + 1];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: field(
                                    '',
                                    labelController,
                                    hint: 'Tag (e.g. Simple)',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: field(
                                    '',
                                    valueController,
                                    hint: 'Price ₹',
                                    keyboard: TextInputType.number,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove price tag',
                                  color: danger,
                                  onPressed: priceTagEdits.length > 2
                                      ? () {
                                          dialogSetState(() {
                                            labelController.dispose();
                                            valueController.dispose();
                                            priceTagEdits.removeRange(
                                              i * 2,
                                              i * 2 + 2,
                                            );
                                          });
                                        }
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () {
                            dialogSetState(() {
                              priceTagEdits.add(TextEditingController());
                              priceTagEdits.add(TextEditingController());
                            });
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Price Tag'),
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (_, c) {
                            final stockField = dropdownField(
                              'Stock Status',
                              editStock,
                              ['Available', 'Limited', 'Out of Stock'],
                              (v) => dialogSetState(
                                () => editStock = v ?? 'Available',
                              ),
                            );
                            final visibleField = dropdownField(
                              'Visible on Website',
                              editVisible,
                              ['yes', 'no'],
                              (v) =>
                                  dialogSetState(() => editVisible = v ?? 'yes'),
                            );

                            if (c.maxWidth < 520) {
                              return Column(
                                children: [
                                  stockField,
                                  const SizedBox(height: 14),
                                  visibleField,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: stockField),
                                const SizedBox(width: 14),
                                Expanded(child: visibleField),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            final priceText = priceController.text.trim();

                            if (name.isEmpty ||
                                editCategory.isEmpty ||
                                priceText.isEmpty) {
                              showToast(
                                '⚠️ Name, Category & Price are required!',
                              );
                              return;
                            }

                            final price = num.tryParse(priceText);
                            if (price == null) {
                              showToast('⚠️ Enter a valid price');
                              return;
                            }

                            final highlights = highlightEdits
                                .map((c) => c.text.trim())
                                .where((x) => x.isNotEmpty)
                                .toList();

                            final priceTags = <Map<String, dynamic>>[];
                            for (
                              int i = 0;
                              i + 1 < priceTagEdits.length;
                              i += 2
                            ) {
                              final label = priceTagEdits[i].text.trim();
                              final value = priceTagEdits[i + 1].text.trim();

                              if (label.isNotEmpty && value.isNotEmpty) {
                                priceTags.add({'label': label, 'price': value});
                              }
                            }

                            dialogSetState(() => saving = true);

                            try {
                              await _db
                                  .collection('products')
                                  .doc('${product['id']}')
                                  .update({
                                    'name': name,
                                    'category': editCategory,
                                    'cat': editCategory,
                                    'price': price,
                                    'description': descController.text.trim(),
                                    'stock': editStock,
                                    'visible': editVisible,
                                    'highlights': highlights,
                                    'price_tags': priceTags,
                                    'updated_at': FieldValue.serverTimestamp(),
                                  });

                              final updated = await loadProductsFromServer();

                              if (mounted) {
                                setState(() => products = updated);
                              }

                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }

                              showToast('✅ Product updated successfully!');
                            } catch (e) {
                              dialogSetState(() => saving = false);
                              showToast('❌ Product update failed: $e');
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(saving ? 'Saving...' : 'Save Changes'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      priceController.dispose();
      descController.dispose();
      for (final c in highlightEdits) {
        c.dispose();
      }
      for (final c in priceTagEdits) {
        c.dispose();
      }
    }
  }

  // ---------------- PRODUCT ACTIONS ----------------

  Future<void> toggleVisible(String id, String visible) async {
    try {
      await _db.collection('products').doc(id).update({'visible': visible});
      products = await loadProductsFromServer();
      setState(() {});
      showToast('✅ Visibility updated');
    } catch (_) {
      showToast('❌ Server error');
    }
  }

  Future<void> deleteProduct(String id) async {
    final ok = await confirmDialog('Delete this product?');
    if (!ok) return;
    try {
      await _db.collection('products').doc(id).delete();
      products = await loadProductsFromServer();
      setState(() {});
      showToast('🗑️ Product deleted');
    } catch (_) {
      showToast('❌ Server error');
    }
  }

  // ---------------- ORDER ACTIONS ----------------

  Future<void> updateStatus(String id, String status) async {
    try {
      showToast('⏳ Updating status...');
      // Records a separate timestamp field per status (ordered_at,
      // processing_at, delivered_at, cancelled_at) so the customer app can
      // show a Flipkart-style timeline on the My Orders page.
      final statusKey = status.toLowerCase().replaceAll(' ', '_');
      await _db.collection('orders').doc(id).set({
        'status': status,
        '${statusKey}_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      orders = await loadOrdersFromServer();
      setState(() {});
      showToast('✅ Status → $status');
    } catch (_) {
      showToast('❌ Server error while updating status');
    }
  }

  /// Updates the order's Firestore `payment_status` field.
  Future<void> updatePaymentStatus(String id, String status) async {
    try {
      showToast('⏳ Updating payment status...');
      await _db.collection('orders').doc(id).set({
        'payment_status': status,
      }, SetOptions(merge: true));
      orders = await loadOrdersFromServer();
      setState(() {});
      showToast('✅ Payment → $status');
    } catch (_) {
      showToast('❌ Server error while updating payment status');
    }
  }

  /// Small pastel pill for the payment-status dropdown.
  Widget _paymentStatusPillLikeBadge(String status) {
    final bool paid = status == 'Paid';
    final Color bg = paid ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0);
    final Color fg = paid ? const Color(0xFF2E7D32) : const Color(0xFFE65100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 14, color: fg),
        ],
      ),
    );
  }

  /// Payment-status control — Pending / Paid. Any legacy value (e.g. old
  /// "Not Required" records) is treated as Pending.
  Widget _paymentStatusControl(String orderId, String currentStatus) {
    final normalized = currentStatus == 'Paid' ? 'Paid' : 'Pending';
    return PopupMenuButton<String>(
      tooltip: 'Change payment status',
      padding: EdgeInsets.zero,
      onSelected: (v) => updatePaymentStatus(orderId, v),
      itemBuilder: (context) => ['Pending', 'Paid']
          .map(
            (s) => PopupMenuItem(
              value: s,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: s == 'Paid' ? success : warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(s, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          )
          .toList(),
      child: _paymentStatusPillLikeBadge(normalized),
    );
  }

  // ---------------- NOTIFICATIONS ----------------

  Future<void> sendNotification() async {
    final title = notificationTitle.text.trim();
    final message = notificationMessage.text.trim();
    if (title.isEmpty || message.isEmpty) {
      showToast('⚠️ Title & Message are required!');
      return;
    }
    try {
      showToast('⏳ Sending...');
            await _db.collection('notifications').add({
        'title': title,
        'message': message,
        'type': notificationType,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 🔑 Actually push it to customer devices via OneSignal — the
      // Firestore write above alone does NOT deliver a push.
      OneSignalService.instance.sendPushToRole('customer', title, message);

      notificationTitle.clear();
      notificationMessage.clear();
      notificationType = 'general';
      await loadNotifications();
      showToast('✅ Notification sent to all customers!');
    } catch (_) {
      showToast('❌ Server error while sending notification');
    }
  }

  Future<void> deleteNotification(dynamic id) async {
    final ok = await confirmDialog('Delete this notification?');
    if (!ok) return;
    try {
      await _db.collection('notifications').doc('$id').delete();
      await loadNotifications();
      showToast('🗑️ Notification deleted');
    } catch (_) {
      showToast('❌ Server error');
    }
  }

  // ---------------- REVIEWS ----------------

  Future<void> deleteReview(dynamic id) async {
    final ok = await confirmDialog('Delete this review?');
    if (!ok) return;
    try {
      await _db.collection('reviews').doc('$id').delete();
      await loadReviews();
      showToast('🗑️ Review deleted');
    } catch (_) {
      showToast('❌ Server error');
    }
  }

  // ---------------- GRIEVANCES ----------------

  Future<void> markGrievance(dynamic id, String status) async {
    try {
      await _db.collection('customer_requests').doc('$id').update({
        'status': status,
      });
      await loadCustomerRequests();
      showToast('✅ Complaint status → $status');
    } catch (_) {
      showToast('❌ Server error while updating complaint');
    }
  }

  // ---------------- CLEAR DATA (batched Firestore deletes) ----------------

  Future<void> _deleteAllInQuery(Query<Map<String, dynamic>> query) async {
    final snap = await query.get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> clearData(String target, String message) async {
    final ok = await confirmDialog(message);
    if (!ok) return;
    try {
      showToast('⏳ Clearing...');
      switch (target) {
        case 'all_demo_data':
          await _deleteAllInQuery(_db.collection('orders'));
          await _deleteAllInQuery(_db.collection('contacts'));
          break;
        case 'orders_all':
          await _deleteAllInQuery(_db.collection('orders'));
          break;
        case 'orders_custom':
          await _deleteAllInQuery(
            _db.collection('orders').where('source', isEqualTo: 'custom-order'),
          );
          break;
        case 'contacts_boutique':
          {
            final snap = await _db.collection('contacts').get();
            final batch = _db.batch();
            for (final doc in snap.docs) {
              if (!isCatering(doc.data())) batch.delete(doc.reference);
            }
            await batch.commit();
          }
          break;
        case 'contacts_catering':
          {
            final snap = await _db.collection('contacts').get();
            final batch = _db.batch();
            for (final doc in snap.docs) {
              if (isCatering(doc.data())) batch.delete(doc.reference);
            }
            await batch.commit();
          }
          break;
        case 'notifications_all':
          await _deleteAllInQuery(_db.collection('notifications'));
          break;
        case 'reviews_all':
          await _deleteAllInQuery(_db.collection('reviews'));
          break;
        case 'data_requests_all':
          await _deleteAllInQuery(
            _db
                .collection('customer_requests')
                .where('type', isEqualTo: 'data_export'),
          );
          break;
        case 'grievances_all':
          await _deleteAllInQuery(
            _db
                .collection('customer_requests')
                .where('type', isEqualTo: 'grievance'),
          );
          break;
        case 'deactivated_all':
          await _deleteAllInQuery(
            _db
                .collection('customer_requests')
                .where('type', isEqualTo: 'deactivated'),
          );
          break;
        case 'deleted_accounts_all':
          await _deleteAllInQuery(
            _db
                .collection('customer_requests')
                .where('type', isEqualTo: 'deleted_account'),
          );
          break;
      }
      await refreshDashboard();
      await loadContacts();
      await loadNotifications();
      await loadReviews();
      await loadCustomerRequests();
      showToast('🗑️ Cleared successfully');
    } catch (e) {
      showToast('❌ Server error while clearing data: $e');
    }
  }

  Future<bool> confirmDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result == true;
  }

  List<Map<String, dynamic>> filteredProducts() {
    final s = productSearch.text.trim().toLowerCase();
    return products.where((p) {
      final okSearch =
          s.isEmpty ||
          '${p['name']}'.toLowerCase().contains(s) ||
          '${p['cat']}'.toLowerCase().contains(s);
      // "All" means no category filter.
      final okCat =
          productCategory.isEmpty ||
          productCategory == 'All' ||
          p['cat'] == productCategory;
      final okStock = productStock.isEmpty || p['stock'] == productStock;
      return okSearch && okCat && okStock;
    }).toList();
  }

  List<Map<String, dynamic>> filteredOrders() {
    final s = orderSearch.text.trim().toLowerCase().replaceFirst('#', '');
    return orders.where((o) {
      // Customized-order requests live only under "Customized Order".
      if ('${o['source']}'.toLowerCase() == 'custom-order') return false;
      final okSearch =
          s.isEmpty ||
          '${o['name']}'.toLowerCase().contains(s) ||
          '${o['mobile']}'.contains(s) ||
          '${o['product']}'.toLowerCase().contains(s) ||
          '${o['orderId']}'.toLowerCase().replaceFirst('#', '').contains(s);
      final okStatus = orderStatus.isEmpty || o['status'] == orderStatus;
      return okSearch && okStatus;
    }).toList();
  }

  List<Map<String, dynamic>> customOrders() {
    final s = customSearch.text.trim().toLowerCase();
    return orders.where((o) {
      final source = '${o['source']}'.toLowerCase();
      final matchSource = source == 'custom-order';
      final matchSearch =
          s.isEmpty ||
          '${o['name']}'.toLowerCase().contains(s) ||
          '${o['mobile']}'.contains(s);
      return matchSource && matchSearch;
    }).toList();
  }

  List<Map<String, dynamic>> filteredContacts(bool catering) {
    final s = (catering ? cateringSearch.text : boutiqueSearch.text)
        .trim()
        .toLowerCase();
    final source = catering ? cateringContacts : boutiqueContacts;
    return source.where((c) {
      return s.isEmpty ||
          '${c['name'] ?? ''}'.toLowerCase().contains(s) ||
          '${c['phone'] ?? ''}'.contains(s) ||
          '${c['email'] ?? ''}'.toLowerCase().contains(s);
    }).toList();
  }

  /// Filters the reviews list by customer name or mobile number.
  List<Map<String, dynamic>> filteredReviews() {
    final s = reviewSearch.text.trim().toLowerCase();
    if (s.isEmpty) return reviews;
    return reviews.where((r) {
      return '${r['name'] ?? ''}'.toLowerCase().contains(s) ||
          '${r['mobile'] ?? ''}'.contains(s);
    }).toList();
  }

  Widget statCard(String value, String label, IconData icon, Color iconBg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: iconBg,
            child: Icon(icon, color: tealDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget mobileStatCard(String value, String label, String emoji, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: bg,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Full-width version of the stat card, used for Pending Orders.
  Widget mobileWideStatCard(
    String value,
    String label,
    String emoji,
    Color bg,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: bg,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionCard(String title, Widget child, {Widget? action}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tealDark,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget actionButton(
    String text,
    VoidCallback onPressed, {
    Color? color,
    Color? textColor,
    bool outline = false,
  }) {
    return SizedBox(
      height: 40,
      child: outline
          ? OutlinedButton(onPressed: onPressed, child: Text(text))
          : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color ?? teal,
                foregroundColor: textColor ?? Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: onPressed,
              child: Text(
                text,
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  Widget field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 5),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: teal, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  /// `emptyLabel` makes the empty ('') option show a clearly visible label
  /// (e.g. "All") instead of appearing blank.
  Widget dropdownField(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    String emptyLabel = '',
  }) {
    String labelFor(String v) =>
        v.isEmpty && emptyLabel.isNotEmpty ? emptyLabel : v;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: values.contains(value) ? value : null,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: muted),
          dropdownColor: Colors.white,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          selectedItemBuilder: (context) => values.map((v) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                labelFor(v),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
          items: values
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(
                    labelFor(v),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Notification "Type" dropdown with friendly display labels while still
  /// saving the lowercase values the customer app expects.
  Widget notificationTypeField(String value, ValueChanged<String?> onChanged) {
    const options = {
      'general': 'General',
      'promotion': 'Promotions',
      'class': 'Class Reminder',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: options.containsKey(value) ? value : 'general',
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: muted),
          dropdownColor: Colors.white,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget dashboardPage(bool mobile) {
    final pending = pendingOrders.length;
    final rev = revenue.toStringAsFixed(0);

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: actionButton(
            '🗑️ Clear All Demo Data',
            () => clearData(
              'all_demo_data',
              '⚠️ This will delete ALL Orders + Boutique + Catering contact '
                  'submissions (Products will not be touched). Continue?',
            ),
            color: danger,
          ),
        ),
        const SizedBox(height: 14),
        if (mobile) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.0,
            children: [
              mobileStatCard(
                '$todaysOrdersCount',
                "Today's Orders",
                '🛒',
                const Color(0xFFFFF3E0),
              ),
              mobileStatCard(
                '₹${num.tryParse(rev)?.toStringAsFixed(0) ?? rev}',
                'Revenue',
                '₹',
                const Color(0xFFE8F5E9),
              ),
              mobileStatCard('${products.length}', 'Products', '📦', tealLight),
              mobileStatCard(
                '${deliveredOrders.length}',
                'Delivered',
                '👥',
                const Color(0xFFE3F2FD),
              ),
            ],
          ),
          const SizedBox(height: 14),
          mobileWideStatCard(
            '$pending',
            'Pending Orders',
            '⏳',
            const Color(0xFFFFEBEE),
          ),
          const SizedBox(height: 14),
        ],
        if (!mobile) ...[
          LayoutBuilder(
            builder: (_, c) {
              final cols = c.maxWidth > 1100 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 2.8,
                children: [
                  statCard(
                    '$todaysOrdersCount',
                    "Today's Orders",
                    Icons.shopping_cart,
                    const Color(0xFFFFF3E0),
                  ),
                  statCard(
                    '₹${revenue.toStringAsFixed(0)}',
                    'Revenue',
                    Icons.currency_rupee,
                    const Color(0xFFE8F5E9),
                  ),
                  statCard(
                    '${products.length}',
                    'Products',
                    Icons.inventory_2,
                    tealLight,
                  ),
                  statCard(
                    '$pending',
                    'Pending',
                    Icons.hourglass_empty,
                    const Color(0xFFFFEBEE),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
        ],
        if (mobile) ...[
          sectionCard(
            '📈 Monthly Orders Chart',
            SizedBox(
              height: 200,
              child: SimpleChart(
                data: monthlyCounts(orders),
                bar: true,
                color: teal,
              ),
            ),
          ),
          sectionCard(
            '🍩 Order Status',
            SizedBox(height: 220, child: StatusChart(orders: orders)),
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: sectionCard(
                  '📈 Monthly Orders Chart',
                  SizedBox(
                    height: 260,
                    child: SimpleChart(
                      data: monthlyCounts(orders),
                      bar: true,
                      color: teal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: sectionCard(
                  '🍩 Order Status',
                  SizedBox(height: 260, child: StatusChart(orders: orders)),
                ),
              ),
            ],
          ),
        sectionCard(
          '📋 Recent Orders',
          orderTable(orders.reversed.take(8).toList(), compact: true),
        ),
      ],
    );
  }

  List<int> monthlyCounts(List<Map<String, dynamic>> source) {
    final counts = List<int>.filled(12, 0);
    for (final o in source) {
      final d = '${o['date'] ?? ''}'.split('/');
      if (d.length >= 2) {
        final m = int.tryParse(d[1]);
        if (m != null && m >= 1 && m <= 12) counts[m - 1]++;
      }
    }
    return counts;
  }

  Widget uploadPage() {
    return sectionCard(
      '📤 Upload New Product',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRODUCT PHOTOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: pickPhotos,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                border: Border.all(color: teal, width: 2),
                borderRadius: BorderRadius.circular(10),
                color: tealLight,
              ),
              child: Column(
                children: [
                  const Text('🖼️', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 6),
                  Text(
                    'Click to Upload Photos',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: teal,
                    ),
                  ),
                  Text(
                    'JPG, PNG, WEBP – Multiple files allowed',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
          if (uploadedPhotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(uploadedPhotos.length, (i) {
                return Stack(
                  children: [
                    FutureBuilder<Uint8List>(
                      future: uploadedPhotos[i].readAsBytes(),
                      builder: (_, snap) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: border, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: snap.hasData
                            ? Image.memory(snap.data!, fit: BoxFit.cover)
                            : const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => setState(() => uploadedPhotos.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 9,
                          backgroundColor: Colors.black54,
                          child: Text(
                            '✕',
                            style: TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'OR',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 10),
          field(
            '🔗 Paste Image Link (e.g. from Imgur, Google Drive share link)',
            pImageUrl,
            hint: 'https://i.imgur.com/example.jpg',
            onChanged: (v) => setState(() {}),
          ),
          if (pImageUrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                _normalizeImageUrl(pImageUrl.text.trim()),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: tealLight,
                  child: const Center(
                    child: Text(
                      '❌ Invalid link',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (_, c) {
              final two = c.maxWidth > 650;
              final nameField = field(
                'Product Name *',
                pName,
                hint: 'e.g. Bridal Blouse Stitching',
              );
              final categoryField = dropdownField('Category *', pCategory, [
                'All',
                'Kids',
                'Uniform',
                'Modern',
                'Salwar',
                'Blouse',
                'Aari',
                'Saree',
                'Frock',
                'Lehenga',
                'Kurthi',
              ], (v) => setState(() => pCategory = v ?? ''));
              final priceField = field(
                'Price (₹) *',
                pPrice,
                hint: 'e.g. 1500',
                keyboard: TextInputType.number,
              );
              final descField = field(
                'Description',
                pDesc,
                hint: 'Short product description...',
                maxLines: 3,
              );

              if (!two) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nameField,
                    const SizedBox(height: 14),
                    categoryField,
                    const SizedBox(height: 14),
                    priceField,
                    const SizedBox(height: 14),
                    descField,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: nameField),
                      const SizedBox(width: 14),
                      Expanded(child: categoryField),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: priceField),
                      const SizedBox(width: 14),
                      Expanded(child: descField),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            '✨ PRODUCT HIGHLIGHTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(highlightControllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: field(
                      '',
                      highlightControllers[i],
                      hint: 'e.g. Premium quality fabric',
                    ),
                  ),
                  IconButton(
                    color: danger,
                    onPressed: () {
                      if (highlightControllers.length > 1) {
                        setState(() {
                          highlightControllers[i].dispose();
                          highlightControllers.removeAt(i);
                        });
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
          OutlinedButton(
            onPressed: () => setState(
              () => highlightControllers.add(TextEditingController()),
            ),
            child: const Text('+ Add Highlight'),
          ),
          const SizedBox(height: 18),
          Text(
            '🏷️ PRICE TAGS (size/type variations)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(priceTagControllers.length ~/ 2, (i) {
            final a = priceTagControllers[i * 2];
            final b = priceTagControllers[i * 2 + 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: field('', a, hint: 'Tag (e.g. Simple)')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: field(
                      '',
                      b,
                      hint: 'Price ₹',
                      keyboard: TextInputType.number,
                    ),
                  ),
                  IconButton(
                    color: danger,
                    onPressed: () {
                      if (priceTagControllers.length > 2) {
                        setState(() {
                          a.dispose();
                          b.dispose();
                          priceTagControllers.removeRange(i * 2, i * 2 + 2);
                        });
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
          OutlinedButton(
            onPressed: () => setState(() {
              priceTagControllers.add(TextEditingController());
              priceTagControllers.add(TextEditingController());
            }),
            child: const Text('+ Add Price Tag'),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (_, c) {
              final two = c.maxWidth > 650;
              final stockField = dropdownField(
                'Stock Status',
                pStock,
                ['Available', 'Limited', 'Out of Stock'],
                (v) => setState(() => pStock = v ?? 'Available'),
              );
              final visibleField = dropdownField(
                'Visible on Website',
                pVisible,
                ['yes', 'no'],
                (v) => setState(() => pVisible = v ?? 'yes'),
              );

              if (!two) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stockField,
                    const SizedBox(height: 14),
                    visibleField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: stockField),
                  const SizedBox(width: 14),
                  Expanded(child: visibleField),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              actionButton(
                loading ? '⏳ Uploading...' : '✅ Upload Product',
                loading ? () {} : uploadProduct,
              ),
              const SizedBox(width: 12),
              actionButton('🔄 Reset', resetUploadForm, outline: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget productsPage() {
    final list = filteredProducts();
    return sectionCard(
      '👗 All Products',
      Column(
        children: [
          LayoutBuilder(
            builder: (_, c) {
              final narrow = c.maxWidth < 560;
              final searchField = field(
                '',
                productSearch,
                hint: '🔍 Search products...',
                onChanged: (v) => setState(() {}),
              );
              final categoryField = dropdownField(
                'Category',
                productCategory,
                [
                  '',
                  'All',
                  'Kids',
                  'Uniform',
                  'Modern',
                  'Salwar',
                  'Blouse',
                  'Aari',
                  'Saree',
                  'Frock',
                  'Lehenga',
                  'Kurthi',
                ],
                (v) => setState(() => productCategory = v ?? ''),
                emptyLabel: 'All',
              );
              final stockField = dropdownField(
                'Stock',
                productStock,
                ['', 'Available', 'Limited', 'Out of Stock'],
                (v) => setState(() => productStock = v ?? ''),
                emptyLabel: 'All',
              );

              if (narrow) {
                return Column(
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: categoryField),
                        const SizedBox(width: 10),
                        Expanded(child: stockField),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 10),
                  SizedBox(width: 180, child: categoryField),
                  const SizedBox(width: 10),
                  SizedBox(width: 160, child: stockField),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const EmptyState(icon: '📦', text: 'No products found')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width > 950 ? 4 : 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: .72,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                final photos = p['photos'] is List
                    ? List.from(p['photos'])
                    : <dynamic>[];
                final rawImage = photos.isNotEmpty
                    ? '${photos.first}'
                    : '${p['photo'] ?? ''}';
                final image = rawImage.isNotEmpty
                    ? _normalizeImageUrl(rawImage)
                    : '';
                final stockColor = p['stock'] == 'Available'
                    ? success
                    : p['stock'] == 'Limited'
                        ? warning
                        : danger;

                return InkWell(
                  onTap: () => showProductDetail(p),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                      boxShadow: const [
                        BoxShadow(color: Color(0x10000000), blurRadius: 8),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          // FIX: this used `BoxFit.cover`, which forces the
                          // photo to fill the frame and crops off the top
                          // of the image — cutting the model's face out of
                          // the "All Products" cards. `contain` + top
                          // alignment (on a background-filled Container)
                          // keeps the whole photo, face included, visible.
                          child: image.isNotEmpty
                              ? Container(
                                  width: double.infinity,
                                  color: tealLight,
                                  child: Image.network(
                                    image,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.topCenter,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        color: tealLight,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      color: tealLight,
                                      child: const Center(
                                        child: Text(
                                          '👗',
                                          style: TextStyle(fontSize: 36),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: tealLight,
                                  child: const Center(
                                    child: Text(
                                      '👗',
                                      style: TextStyle(fontSize: 36),
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p['cat']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tealDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${p['name']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '₹${p['price']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: tealDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${p['stock']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: stockColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Website: '
                                '${p['visible'] == 'yes' ? '✅ Visible' : '❌ Hidden'}',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => editProduct(p),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: tealDark,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 10,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Center(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => toggleVisible(
                                          p['id'] as String,
                                          p['visible'] == 'yes' ? 'no' : 'yes',
                                        ),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: border),
                                          ),
                                          child: Text(
                                            p['visible'] == 'yes' ? '🙈' : '👁',
                                            style: const TextStyle(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: danger,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 10,
                                        ),
                                      ),
                                      onPressed: () =>
                                          deleteProduct(p['id'] as String),
                                      child: const Text(
                                        '🗑️ Delete',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget orderTable(List<Map<String, dynamic>> list, {bool compact = false}) {
    if (list.isEmpty) {
      return const EmptyState(icon: '📭', text: 'No orders yet');
    }

    final columns = compact
        ? [
            'Order ID',
            'Customer',
            'Mobile',
            'Product',
            'Amount',
            'Status',
            'Date',
            'WhatsApp',
          ]
        : [
            'Order ID',
            'Customer',
            'Mobile',
            'Product',
            'Amount',
            'Payment',
            'Measurement',
            'Message',
            'Voice Note',
            'Status',
            'Date',
            'Update',
            'WhatsApp',
          ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(tealLight),
        columns: columns
            .map(
              (c) => DataColumn(
                label: Text(
                  c,
                  style: TextStyle(
                    fontSize: 11,
                    color: tealDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
        rows: list.map((o) {
          final cells = compact
              ? [
                  DataCell(Text('${o['orderId']}')),
                  DataCell(Text('${o['name']}')),
                  DataCell(Text('📞 ${o['mobile']}')),
                  DataCell(Text('${o['product']}')),
                  DataCell(Text('₹${o['amount']}')),
                  DataCell(StatusBadge(status: '${o['status']}')),
                  DataCell(Text('${o['date']}')),
                  DataCell(
                    TextButton(
                      onPressed: () =>
                          openWhatsApp('${o['mobile']}', '${o['name']}'),
                      child: const Text('💬'),
                    ),
                  ),
                ]
              : [
                  DataCell(Text('${o['orderId']}')),
                  DataCell(Text('${o['name']}')),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${o['mobile']}'),
                        if ('${o['alternateMobile'] ?? ''}'.trim().isNotEmpty)
                          Text(
                            'Alt: ${o['alternateMobile']}',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                      ],
                    ),
                  ),
                  DataCell(Text('${o['product']}')),
                  DataCell(Text('₹${o['amount']}')),
                  // Payment cell — method text on top, Pending/Paid pill
                  // underneath so admin can mark COD orders as paid.
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${o['paymentMethod']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        _paymentStatusControl(
                          '${o['id']}',
                          '${o['paymentStatus']}',
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text('${o['measurement'] ?? '—'}')),
                  // Message cell also shows the cancellation reason (red)
                  // under the customer's notes when the order is Cancelled.
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            '${o['notes'] ?? '—'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ('${o['status']}' == 'Cancelled' &&
                            '${o['cancelReason'] ?? ''}'.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                '❌ ${o['cancelReason']}',
                                style: TextStyle(fontSize: 10, color: danger),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Voice note is Base64 audio, not a URL — play it in
                  // place from memory instead of launching it.
                  DataCell(
                    voiceNoteButton('${o['id']}', '${o['voiceNote'] ?? ''}'),
                  ),
                  DataCell(StatusBadge(status: '${o['status']}')),
                  DataCell(Text('${o['date']}')),
                  DataCell(
                    _statusChangeControl('${o['id']}', '${o['status']}'),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: () =>
                          openWhatsApp('${o['mobile']}', '${o['name']}'),
                      child: const Text('💬'),
                    ),
                  ),
                ];

          return DataRow(
            // Tapping a row pushes the full-screen order detail page.
            onSelectChanged: (_) =>
                _pushPage('${o['orderId']}', _orderDetailBody(o)),
            cells: cells,
          );
        }).toList(),
      ),
    );
  }

  /// Full-screen order detail body — pushed via _pushPage() when an order
  /// row is tapped. Fields with no value render as "—".
  Widget _orderDetailBody(Map<String, dynamic> o) {
    Widget row(String label, String value) {
      if (value.trim().isEmpty || value == 'null') value = '—';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order ID : ${o['orderId']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          row('Customer', '${o['name']}'),
          row('Mobile No :', '${o['mobile']}'),
          row('Alternate Mobile No :', '${o['alternateMobile'] ?? ''}'),
          row('Product', '${o['product']}'),
          row('Amount', '₹${o['amount']}'),
          // Payment row — method on the left, tappable Pending/Paid pill.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Payment',
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        '${o['paymentMethod']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      _paymentStatusControl(
                        '${o['id']}',
                        '${o['paymentStatus']}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          row('Address', '${o['address'] ?? ''}'),
          row('Measurement', '${o['measurement'] ?? ''}'),
          row('Notes', '${o['notes'] ?? ''}'),
          row('Date', '${o['date']}'),
          if ('${o['orderedAt'] ?? ''}'.trim().isNotEmpty)
            row('Ordered On', '${o['orderedAt']}'),
          if ('${o['processingAt'] ?? ''}'.trim().isNotEmpty)
            row('Processing On', '${o['processingAt']}'),
          if ('${o['deliveredAt'] ?? ''}'.trim().isNotEmpty)
            row('Delivered On', '${o['deliveredAt']}'),
          // Cancel reason as a highlighted red box.
          if ('${o['status']}' == 'Cancelled') ...[
            if ('${o['cancelledAt'] ?? ''}'.trim().isNotEmpty)
              row('Cancelled On', '${o['cancelledAt']}'),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: danger.withValues(alpha: .3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '❌ Cancellation Reason',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: danger,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${o['cancelReason'] ?? ''}'.trim().isEmpty
                        ? '—'
                        : '${o['cancelReason']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if ('${o['source']}'.toLowerCase() != 'custom-order') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                _statusChangeControl('${o['id']}', '${o['status']}'),
              ],
            ),
            const SizedBox(height: 16),
          ],
          voiceNoteButton('${o['id']}', '${o['voiceNote'] ?? ''}'),
          const SizedBox(height: 16),
          if ('${o['rating'] ?? ''}'.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: copperLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⭐ Customer Feedback — ${o['rating']}/5',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if ('${o['feedback'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${o['feedback']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          actionButton(
            '💬 WhatsApp',
            () => openWhatsApp('${o['mobile']}', '${o['name']}'),
          ),
        ],
      ),
    );
  }

  Widget ordersPage() {
    final list = filteredOrders().reversed.toList();
    return sectionCard(
      '🧾 Orders Management',
      Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: actionButton(
              '🗑️ Clear All Orders',
              () => clearData(
                'orders_all',
                '⚠️ This will delete ALL Orders (Customized Orders too, since '
                    'they are in the same collection). Continue?',
              ),
              color: danger,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tealLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '➕ Add New Order',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tealDark,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Orders are normally created from the customer website.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: field(
                  '',
                  orderSearch,
                  hint: '🔍 Search by Order ID / name / mobile / product...',
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: dropdownField(
                  'Status',
                  orderStatus,
                  [
                    '',
                    'Ordered',
                    'Processing',
                    'Shipping',
                    'Delivered',
                    'Cancelled',
                  ],
                  (v) => setState(() => orderStatus = v ?? ''),
                  emptyLabel: 'All',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          orderTable(list),
        ],
      ),
    );
  }

  Widget customOrdersPage() {
    final list = customOrders().reversed.toList();
    return sectionCard(
      '✂️ Customized Order Requests',
      Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: actionButton(
              '🗑️ Clear Custom Orders',
              () => clearData(
                'orders_custom',
                '⚠️ This will delete ALL Customized Orders. Continue?',
              ),
              color: danger,
            ),
          ),
          const SizedBox(height: 16),
          field(
            '',
            customSearch,
            hint: '🔍 Search by name / mobile...',
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const EmptyState(icon: '✂️', text: 'No customized orders yet')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(tealLight),
                columns: const [
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Mobile')),
                  DataColumn(label: Text('Order Type')),
                  DataColumn(label: Text('Measurements')),
                  DataColumn(label: Text('Notes')),
                  DataColumn(label: Text('Voice Note')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('WhatsApp')),
                ],
                rows: list
                    .map(
                      (o) => DataRow(
                        onSelectChanged: (_) => _pushPage(
                          '${o['name']} — Custom Order',
                          _orderDetailBody(o),
                        ),
                        cells: [
                          DataCell(Text('${o['name']}')),
                          DataCell(Text('📞 ${o['mobile']}')),
                          DataCell(Text('${o['product']}')),
                          DataCell(Text('${o['measurement'] ?? '—'}')),
                          DataCell(Text('${o['notes'] ?? '—'}')),
                          DataCell(
                            voiceNoteButton(
                              '${o['id']}',
                              '${o['voiceNote'] ?? ''}',
                            ),
                          ),
                          DataCell(Text('${o['date']}')),
                          DataCell(
                            TextButton(
                              onPressed: () =>
                                  openWhatsApp('${o['mobile']}', '${o['name']}'),
                              child: const Text('💬'),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  List<Map<String, String>> get uniqueCustomers {
    final seen = <String, Map<String, String>>{};
    for (final o in orders) {
      final phone = normalizePhone('${o['mobile'] ?? ''}');
      if (phone.isEmpty) continue;
      seen[phone] = {
        'name': '${o['name'] ?? 'Guest'}',
        'phone': '${o['mobile'] ?? ''}',
      };
    }
    return seen.values.toList();
  }

  List<Map<String, String>> get filteredUniqueCustomers {
    final q = customerListSearch.text.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    if (q.isEmpty) return uniqueCustomers;
    return uniqueCustomers.where((c) {
      final name = (c['name'] ?? '').toLowerCase();
      final phone = normalizePhone(c['phone'] ?? '');
      final matchesName = name.contains(q);
      final matchesPhone = qDigits.isNotEmpty && phone.contains(qDigits);
      return matchesName || matchesPhone;
    }).toList();
  }

  List<Map<String, dynamic>> ordersForPhone(String phone) {
    final norm = normalizePhone(phone);
    if (norm.isEmpty) return [];
    return orders
        .where((o) => normalizePhone('${o['mobile'] ?? ''}') == norm)
        .toList();
  }

  num spentByPhone(String phone) => ordersForPhone(phone)
      .where((o) => o['status'] == 'Delivered')
      .fold<num>(0, (s, o) => s + (o['amount'] ?? 0));

  /// Merged "Contact Form" hub — Catering / Customized Order.
  Widget contactFormHubPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x10000000), blurRadius: 10),
            ],
          ),
          child: Row(
            children: [
              Expanded(child: _hubTabButton('🍽️ Catering', 'catering')),
              Expanded(child: _hubTabButton('✂️ Customized Order', 'custom')),
            ],
          ),
        ),
        Builder(
          builder: (_) {
            switch (contactHubTab) {
              case 'custom':
                return customOrdersPage();
              case 'catering':
              default:
                return contactPage(true);
            }
          },
        ),
      ],
    );
  }

  Widget _hubTabButton(String label, String tabId) {
    final selected = contactHubTab == tabId;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => contactHubTab = tabId);
        // Make sure the right data is loaded when switching tabs.
        if (tabId == 'catering') loadContacts();
        if (tabId == 'custom') loadOrdersAndSet();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? teal : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : muted,
          ),
        ),
      ),
    );
  }

  /// Standalone "Customers" page. Tapping a card pushes a new route, so
  /// swipe-back works.
  Widget customersPage() {
    final list = filteredUniqueCustomers;
    return sectionCard(
      '👤 Customers',
      Column(
        children: [
          field(
            '',
            customerListSearch,
            hint: '🔍 Search customer...',
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const EmptyState(icon: '👤', text: 'No customers found')
          else
            ...list.map((c) {
              final orderCount = ordersForPhone(c['phone']!).length;
              final spent = spentByPhone(c['phone']!);
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: pageBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0xFFFCE4EC),
                          child: Icon(Icons.person, color: Color(0xFFE57373)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c['name']!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c['phone']!,
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: muted),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.shopping_bag,
                                color: Color(0xFFFF9800),
                                size: 22,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$orderCount',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Orders',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.currency_rupee,
                                color: Color(0xFF43A047),
                                size: 22,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₹${spent.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Spent',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _pushPage(
                          c['name']!,
                          _customerHistoryBody(c['phone']!, c['name']!),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('View Order History'),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Body pushed when "View Order History" is tapped.
  Widget _customerHistoryBody(String phone, String name) {
    final custOrders = ordersForPhone(phone).reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('📞 $phone', style: TextStyle(fontSize: 13, color: muted)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => openWhatsApp(phone, name),
              icon: const Icon(Icons.chat, size: 16),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (custOrders.isEmpty)
          const EmptyState(icon: '📦', text: 'No products ordered yet')
        else
          ...custOrders.map((o) {
            final image = _productImageFor('${o['product']}');
            return InkWell(
              onTap: () => _pushPage('${o['orderId']}', _orderDetailBody(o)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: image.isNotEmpty
                          ? Container(
                              width: 48,
                              height: 48,
                              color: tealLight,
                              child: Image.network(
                                image,
                                width: 48,
                                height: 48,
                                fit: BoxFit.contain,
                                alignment: Alignment.topCenter,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Text('👗'),
                                ),
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: tealLight,
                              child: const Center(child: Text('👗')),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${o['product']}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '₹${o['amount']}  •  ${o['date']}',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if ('${o['source']}'.toLowerCase() != 'custom-order')
                      StatusBadge(status: '${o['status']}'),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, color: muted),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget contactPage(bool catering) {
    final list = filteredContacts(catering).reversed.toList();
    final controller = catering ? cateringSearch : boutiqueSearch;
    return sectionCard(
      catering
          ? '🍽️ Catering Contact Form Submissions'
          : '📨 Boutique Contact Form Submissions',
      Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: actionButton(
              catering
                  ? '🗑️ Clear Catering Contacts'
                  : '🗑️ Clear Boutique Contacts',
              () => clearData(
                catering ? 'contacts_catering' : 'contacts_boutique',
                catering
                    ? '⚠️ This will delete ALL Catering contact submissions. Continue?'
                    : '⚠️ This will delete ALL Boutique contact submissions. Continue?',
              ),
              color: danger,
            ),
          ),
          const SizedBox(height: 16),
          field(
            '',
            controller,
            hint: '🔍 Search by name / phone / email...',
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            EmptyState(
              icon: catering ? '🍽️' : '📨',
              text: catering
                  ? 'No catering contact form submissions yet'
                  : 'No contact form submissions yet',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(tealLight),
                columns: const [
                  DataColumn(label: Text('Name')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Service')),
                  DataColumn(label: Text('Message')),
                  DataColumn(label: Text('Date')),
                ],
                rows: list
                    .map(
                      (c) => DataRow(
                        cells: [
                          DataCell(Text('${c['name'] ?? ''}')),
                          DataCell(Text('${c['phone'] ?? '—'}')),
                          DataCell(Text('${c['email'] ?? '—'}')),
                          DataCell(Text('${c['service'] ?? '—'}')),
                          DataCell(Text('${c['message'] ?? ''}')),
                          DataCell(Text(formatDate(c['created_at']))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget notificationsPage() {
    return Column(
      children: [
        sectionCard(
          '🔔 Send Notification to All Customers',
          Column(
            children: [
              field(
                'Title *',
                notificationTitle,
                hint: 'e.g. New Arrivals in Store!',
              ),
              const SizedBox(height: 14),
              field(
                'Message *',
                notificationMessage,
                hint: 'e.g. Check out our latest saree collection...',
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              notificationTypeField(
                notificationType,
                (v) => setState(() => notificationType = v ?? 'general'),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: actionButton('📢 Send Notification', sendNotification),
              ),
            ],
          ),
        ),
        sectionCard(
          '📋 Sent Notifications',
          Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: actionButton(
                  '🗑️ Clear All Notifications',
                  () => clearData(
                    'notifications_all',
                    '⚠️ This will delete ALL sent notifications. Continue?',
                  ),
                  color: danger,
                ),
              ),
              const SizedBox(height: 14),
              if (notifications.isEmpty)
                const EmptyState(icon: '🔔', text: 'No notifications sent yet')
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(tealLight),
                    columns: const [
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Message')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Sent On')),
                      DataColumn(label: Text('Action')),
                    ],
                    rows: notifications.reversed
                        .map(
                          (n) => DataRow(
                            cells: [
                              DataCell(Text('${n['title'] ?? ''}')),
                              DataCell(Text('${n['message'] ?? ''}')),
                              DataCell(Text('${n['type'] ?? ''}')),
                              DataCell(Text(formatDateTime(n['created_at']))),
                              DataCell(
                                TextButton(
                                  onPressed: () => deleteNotification(n['id']),
                                  child: Text(
                                    '🗑️ Delete',
                                    style: TextStyle(color: danger),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Reviews" page — one card per customer review.
  Widget reviewsPage() {
    final list = filteredReviews();
    return sectionCard(
      '⭐ Customer Reviews',
      Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: actionButton(
              '🗑️ Clear All Reviews',
              () => clearData(
                'reviews_all',
                '⚠️ This will delete ALL customer reviews. Continue?',
              ),
              color: danger,
            ),
          ),
          const SizedBox(height: 16),
          field(
            '',
            reviewSearch,
            hint: '🔍 Search by name / mobile...',
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const EmptyState(icon: '⭐', text: 'No reviews yet')
          else
            ...list.map((r) {
              final rating = (num.tryParse('${r['rating'] ?? 0}') ?? 0).toInt();
              final name = '${r['name'] ?? 'Guest'}';
              final mobile = '${r['mobile'] ?? r['phone'] ?? '—'}';
              final comment = '${r['comment'] ?? r['review'] ?? ''}';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: pageBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: tealLight,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: tealDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '📞 $mobile',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '★' * rating + '☆' * (5 - rating),
                          style: const TextStyle(
                            color: Color(0xFFFB8C00),
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete review',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => deleteReview(r['id']),
                          icon: Icon(
                            Icons.delete_outline,
                            color: danger,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    if (comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        comment,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                    if ('${r['createdAt'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        formatDateTime(r['createdAt']),
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget cancellationTable(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return const EmptyState(icon: '❌', text: 'No cancellations yet');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(tealLight),
        columns: const [
          DataColumn(label: Text('Order ID')),
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Mobile')),
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Reason')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('WhatsApp')),
        ],
        rows: list.map((o) {
          return DataRow(
            cells: [
              DataCell(Text('${o['orderId']}')),
              DataCell(Text('${o['name']}')),
              DataCell(Text('📞 ${o['mobile']}')),
              DataCell(Text('${o['product']}')),
              DataCell(Text('₹${o['amount']}')),
              DataCell(Text('${o['cancelReason'] ?? '—'}')),
              DataCell(Text('${o['date']}')),
              DataCell(
                TextButton(
                  onPressed: () =>
                      openWhatsApp('${o['mobile']}', '${o['name']}'),
                  child: const Text('💬'),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget dataRequestsPage() {
    return Column(
      children: [
        sectionCard(
          '❌ Recent Cancellations',
          Column(
            children: [
              field(
                '',
                cancellationSearch,
                hint: '🔍 Search by Order ID / name / mobile / product...',
                onChanged: (v) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Builder(
                builder: (_) {
                  final s = cancellationSearch.text.trim().toLowerCase();
                  final cancelled = orders.where((o) {
                    if (o['status'] != 'Cancelled') return false;
                    return s.isEmpty ||
                        '${o['name']}'.toLowerCase().contains(s) ||
                        '${o['mobile']}'.contains(s) ||
                        '${o['product']}'.toLowerCase().contains(s) ||
                        '${o['orderId']}'.toLowerCase().contains(s);
                  }).toList();
                  if (cancelled.isEmpty) {
                    return const EmptyState(
                      icon: '❌',
                      text: 'No cancellations yet',
                    );
                  }
                  return cancellationTable(cancelled.reversed.toList());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Complaints" page.
  Widget grievancesPage() {
    return sectionCard(
      '⚖️ Customer Complaints',
      Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: actionButton(
              '🗑️ Clear All Complaints',
              () => clearData(
                'grievances_all',
                '⚠️ This will delete ALL customer complaints. Continue?',
              ),
              color: danger,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: field(
                  '',
                  grievanceSearch,
                  hint: '🔍 Search by name / phone / subject...',
                  onChanged: (v) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: dropdownField(
                  'Status',
                  grievanceStatus,
                  ['', 'Open', 'Resolved'],
                  (v) => setState(() => grievanceStatus = v ?? ''),
                  emptyLabel: 'All',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _grievanceTable(),
        ],
      ),
    );
  }

  Widget _grievanceTable() {
    final s = grievanceSearch.text.trim().toLowerCase();
    final list = grievances.where((g) {
      final matchSearch =
          s.isEmpty ||
          '${g['name'] ?? ''}'.toLowerCase().contains(s) ||
          '${g['phone'] ?? ''}'.contains(s) ||
          '${g['subject'] ?? ''}'.toLowerCase().contains(s);
      final matchStatus =
          grievanceStatus.isEmpty || g['status'] == grievanceStatus;
      return matchSearch && matchStatus;
    }).toList();

    if (list.isEmpty) {
      return const EmptyState(icon: '⚖️', text: 'No complaints yet');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(tealLight),
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Phone')),
          DataColumn(label: Text('Subject')),
          DataColumn(label: Text('Order ID')),
          DataColumn(label: Text('Description')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Action')),
          DataColumn(label: Text('WhatsApp')),
        ],
        rows: list.reversed.map((g) {
          final resolved = '${g['status']}' == 'Resolved';
          return DataRow(
            cells: [
              DataCell(Text('${g['name'] ?? 'Guest'}')),
              DataCell(Text('${g['phone'] ?? '—'}')),
              DataCell(Text('${g['subject'] ?? ''}')),
              DataCell(Text('${g['order_id'] ?? '—'}')),
              DataCell(Text('${g['description'] ?? ''}')),
              DataCell(StatusBadge(status: '${g['status'] ?? 'Open'}')),
              DataCell(Text(formatDateTime(g['created_at']))),
              DataCell(
                TextButton(
                  onPressed: () =>
                      markGrievance(g['id'], resolved ? 'Open' : 'Resolved'),
                  child: Text(resolved ? '↩️ Reopen' : '✅ Mark Resolved'),
                ),
              ),
              DataCell(
                TextButton(
                  onPressed: () =>
                      openWhatsApp('${g['phone']}', '${g['name'] ?? 'Customer'}'),
                  child: const Text('💬'),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget revenuePage() {
    final periodOrders = ordersForPeriod(revenuePeriod);
    final total = revenue;
    final periodTotal = periodOrders.fold<num>(
      0,
      (s, o) => s + (o['amount'] ?? 0),
    );
    final avg = deliveredOrders.isEmpty ? 0 : total / deliveredOrders.length;

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: actionButton(
            '🗑️ Clear Orders (resets Revenue)',
            () => clearData(
              'orders_all',
              '⚠️ This will delete ALL Orders, and Revenue will reset to ₹0. Continue?',
            ),
            color: danger,
          ),
        ),
        const SizedBox(height: 14),

        // ---------------- Week / Month / Year filter ----------------
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final entry in {
              'week': '📅 Week',
              'month': '🗓️ Month',
              'year': '📆 Year',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: revenuePeriod == entry.key,
                selectedColor: teal,
                labelStyle: TextStyle(
                  color: revenuePeriod == entry.key ? Colors.white : tealDark,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: tealLight,
                onSelected: (_) => setState(() => revenuePeriod = entry.key),
              ),
            actionButton(
              pdfGenerating ? '⏳ Generating...' : '📄 Download PDF',
              pdfGenerating ? () {} : downloadRevenuePdf,
              color: copper,
            ),
            actionButton(
              '📊 Analysis',
              () => showPage('analysis'),
              color: tealDark,
            ),
          ],
        ),

        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (_, c) {
            final cols = c.maxWidth > 700 ? 3 : 1;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 2.8,
              children: [
                RevenueCard(
                  label: 'TOTAL REVENUE',
                  value: '₹${total.toStringAsFixed(0)}',
                  sub: 'All delivered orders',
                  color1: tealDark,
                  color2: teal,
                ),
                RevenueCard(
                  label: periodLabel(revenuePeriod),
                  value: '₹${periodTotal.toStringAsFixed(0)}',
                  sub: '${periodOrders.length} delivered orders',
                  color1: const Color(0xFF9C6024),
                  color2: copper,
                ),
                RevenueCard(
                  label: 'AVG ORDER VALUE',
                  value: '₹${avg.toStringAsFixed(0)}',
                  sub: 'Per delivered order',
                  color1: const Color(0xFF2E7D32),
                  color2: success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: sectionCard(
                '📊 ${periodLabel(revenuePeriod)} Revenue Chart',
                SizedBox(
                  height: 260,
                  child: SimpleChart(
                    // Scoped to the current year so the 12 month buckets
                    // don't mix data from previous years.
                    data: monthlyRevenue(ordersForPeriod('year')),
                    bar: false,
                    color: teal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: sectionCard(
                '🏆 Top Products by Revenue',
                topProducts(periodOrders),
              ),
            ),
          ],
        ),
        sectionCard(
          '📋 ${periodLabel(revenuePeriod)} Delivered Orders',
          orderTable(periodOrders.reversed.toList(), compact: true),
        ),
      ],
    );
  }

  /// Product-purchase-percentage page, opened via "📊 Analysis".
  Widget analysisPage() {
    final periodOrders = ordersForPeriod(revenuePeriod);
    final counts = productPurchaseCounts(periodOrders);
    final totalOrders = counts.values.fold<int>(0, (a, b) => a + b);
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sectionCard(
      '📊 Most Bought Products — ${periodLabel(revenuePeriod)}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in {
                'week': 'Week',
                'month': 'Month',
                'year': 'Year',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: revenuePeriod == entry.key,
                  selectedColor: teal,
                  labelStyle: TextStyle(
                    color: revenuePeriod == entry.key ? Colors.white : tealDark,
                    fontSize: 12,
                  ),
                  backgroundColor: tealLight,
                  onSelected: (_) => setState(() => revenuePeriod = entry.key),
                ),
              actionButton(
                pdfGenerating ? '⏳ Generating...' : '📄 Download PDF',
                pdfGenerating ? () {} : downloadRevenuePdf,
                color: copper,
              ),
            ],
          ),
          const SizedBox(height: 18),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pushPage(
              'Sales Comparison',
              Column(children: [_salesComparisonBox(), _dayBox()]),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x10000000), blurRadius: 10),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.show_chart,
                    size: 20,
                    color: Color(0xFF616161),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Sales Comparison — Today / Week / Month / Year',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
          if (totalOrders == 0)
            const EmptyState(
              icon: '📊',
              text: 'No delivered orders in this period yet',
            )
          else
            ...List.generate(sorted.length, (i) {
              final e = sorted[i];
              final pct = (e.value / totalOrders) * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i + 1}. ${e.key}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(1)}%  (${e.value} orders)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tealDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: pct / 100,
                        backgroundColor: const Color(0xFFE0E0E0),
                        valueColor: AlwaysStoppedAnimation(teal),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  List<num> monthlyRevenue(List<Map<String, dynamic>> source) {
    final data = List<num>.filled(12, 0);
    for (final o in source) {
      final d = '${o['date']}'.split('/');
      if (d.length >= 2) {
        final m = int.tryParse(d[1]);
        if (m != null && m >= 1 && m <= 12) data[m - 1] += (o['amount'] ?? 0);
      }
    }
    return data;
  }

  Widget topProducts(List<Map<String, dynamic>> delivered) {
    final map = <String, num>{};
    for (final o in delivered) {
      final name = '${o['product'] ?? ''}';
      map[name] = (map[name] ?? 0) + (o['amount'] ?? 0);
    }
    final list = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = list.take(5).toList();
    if (top.isEmpty) {
      return const EmptyState(icon: '📊', text: 'No delivered orders yet');
    }
    final maxValue = top.first.value == 0 ? 1 : top.first.value;
    return Column(
      children: List.generate(top.length, (i) {
        final e = top[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${i + 1}. ${e.key}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₹${e.value.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: e.value / maxValue,
                  backgroundColor: const Color(0xFFE0E0E0),
                  valueColor: AlwaysStoppedAnimation(teal),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> openWhatsApp(String mobile, String name) async {
    final numText = mobile.replaceAll(RegExp(r'\D'), '');
    final msg = Uri.encodeComponent(
      "Hi $name! 👗 Thank you for choosing Sumathi's Styles, Injambakkam. "
      "How can we help you today?",
    );
    final uri = Uri.parse('https://wa.me/91$numText?text=$msg');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) showToast('❌ Could not open WhatsApp');
    } catch (e) {
      showToast('❌ WhatsApp error: $e');
    }
  }

  Widget currentContent(bool mobile) {
    switch (currentPage) {
      case 'upload':
        return uploadPage();
      case 'products':
        return productsPage();
      case 'ordersmgmt':
        return ordersPage();
      case 'customers':
        return customersPage();
      case 'contactformhub':
        return contactFormHubPage();
      case 'notifications':
        return notificationsPage();
      case 'reviews':
        return reviewsPage();
      case 'datarequests':
        return dataRequestsPage();
      case 'grievances':
        return grievancesPage();
      case 'revenue':
        return revenuePage();
      case 'analysis':
        return analysisPage();
      case 'dashboard':
      default:
        return dashboardPage(mobile);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) return loginScreen();

    final width = MediaQuery.sizeOf(context).width;
    final mobile = width <= 700;

    if (mobile && !mobilePageMode) {
      return mobileMenu();
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Row(
          children: [
            if (!mobile) sidebarWidget(),
            Expanded(
              child: Column(
                children: [
                  topbarWidget(mobile),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(mobile ? 12 : 28),
                      child: currentContent(mobile),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: toastMessage.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: tealDark,
              onPressed: () {},
              label: Text(
                toastMessage,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            )
          : null,
    );
  }

  /// Login screen — black top bar with "Admin Login", blue shield icon with
  /// person badge, "Admin Panel" title, bordered fields, blue pill button.
  Widget loginScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back',
                    ),
                  ),
                  const Text(
                    'Admin Login',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 88,
                          height: 88,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CustomPaint(
                                size: const Size(88, 88),
                                painter: ShieldPainter(color: loginBlue),
                              ),
                              Positioned(
                                bottom: -2,
                                right: -6,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: loginBlue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x26000000),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Admin Panel',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 28),
                        loginField(
                          icon: Icons.mail_outline,
                          controller: emailController,
                          hint: 'Email',
                          keyboard: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        loginField(
                          icon: Icons.lock_outline,
                          controller: passwordController,
                          hint: 'Password',
                          isPassword: true,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: loginBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 0,
                            ),
                            onPressed: doLogin,
                            child: const Text(
                              'LOGIN',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                        ),
                        if (loginError.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            loginError,
                            style: TextStyle(color: danger, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget loginField({
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboard,
    bool obscure = false,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8D8D8), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black.withValues(alpha: .55)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboard,
              obscureText: isPassword ? _obscurePassword : obscure,
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF999999)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (isPassword)
            IconButton(
              splashRadius: 18,
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 19,
                color: Colors.black.withValues(alpha: .5),
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
        ],
      ),
    );
  }

  /// Used by every tile/button on the mobile dashboard home screen.
  void _openMobilePage(String id, {String? contactTab}) {
    showPage(id);
    setState(() => mobilePageMode = true);
    if (contactTab != null) {
      setState(() => contactHubTab = contactTab);
    }
  }

  /// One of the 4 stat cards at the top of the mobile home screen.
  Widget _homeStatCard(
    IconData icon,
    Color iconColor,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }

  /// One tile in the "Management" grid.
  Widget _managementTile(
    IconData icon,
    Color iconColor,
    Color circleBg,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: circleBg,
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget mobileMenu() {
    final pending = pendingOrders.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F7),
      body: SafeArea(
        child: Column(
          children: [
            // ---------------- TOP APP BAR ----------------
                  Container(
              width: double.infinity,
              color: loginBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back',
                    ),
                  ),
                  const Text(
                    'Admin Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          setState(() {
                            _newOrdersBadge = 0;
                            _newContactsBadge = 0;
                          });
                          _openMobilePage('ordersmgmt');
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white24,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '🔔',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                            if (_newOrdersBadge + _newContactsBadge > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: danger,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '${_newOrdersBadge + _newContactsBadge}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Dashboard',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),

                  // ---------------- 4 STAT CARDS ----------------
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.05,
                    children: [
                      _homeStatCard(
                        Icons.shopping_cart,
                        const Color(0xFFFF9800),
                        '$todaysOrdersCount',
                        'Orders',
                      ),
                      _homeStatCard(
                        Icons.currency_rupee,
                        const Color(0xFF43A047),
                        '₹${revenue.toStringAsFixed(0)}',
                        'Revenue',
                      ),
                      _homeStatCard(
                        Icons.location_on,
                        const Color(0xFFE53935),
                        '${products.length}',
                        'Product',
                      ),
                      _homeStatCard(
                        Icons.people,
                        const Color(0xFF2196F3),
                        '${uniqueCustomers.length}',
                        'Customers',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Management',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),

                  // ---------------- MANAGEMENT GRID ----------------
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.05,
                    children: [
                      _managementTile(
                        Icons.receipt_long,
                        const Color(0xFFFF9800),
                        const Color(0xFFFFE0B2),
                        'Manage Orders',
                        () => _openMobilePage('ordersmgmt'),
                      ),
                      _managementTile(
                        Icons.people,
                        const Color(0xFF2196F3),
                        const Color(0xFFBBDEFB),
                        'Customers',
                        () => _openMobilePage('customers'),
                      ),
                      _managementTile(
                        Icons.add,
                        const Color(0xFF4CAF50),
                        const Color(0xFFC8E6C9),
                        'Product Upload',
                        () => _openMobilePage('upload'),
                      ),
                      _managementTile(
                        Icons.edit_note,
                        const Color(0xFF2196F3),
                        const Color(0xFFBBDEFB),
                        'All Products',
                        () => _openMobilePage('products'),
                      ),
                      _managementTile(
                        Icons.bar_chart,
                        const Color(0xFF9C27B0),
                        const Color(0xFFE1BEE7),
                        'Analytics',
                        () => _openMobilePage('analysis'),
                      ),
                      _managementTile(
                        Icons.forum,
                        teal,
                        tealLight,
                        'Contact Form',
                        () => _openMobilePage(
                          'contactformhub',
                          contactTab: 'catering',
                        ),
                      ),
                      _managementTile(
                        Icons.notifications_active,
                        const Color(0xFFFF5722),
                        const Color(0xFFFFCCBC),
                        'Notifications',
                        () => _openMobilePage('notifications'),
                      ),
                      _managementTile(
                        Icons.star_rate,
                        const Color(0xFFFBC02D),
                        const Color(0xFFFFF9C4),
                        'Reviews',
                        () => _openMobilePage('reviews'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),

                  // ---------------- QUICK ACTIONS ----------------
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B0FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _openMobilePage('upload'),
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Add New Product',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD500F9),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _openMobilePage('ordersmgmt'),
                      icon: const Icon(Icons.shopping_bag),
                      label: Text(
                        pending > 0
                            ? 'View Orders ($pending pending)'
                            : 'View Orders',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    "Today's Overview",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),

                  // ---------------- TODAY'S OVERVIEW ----------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.trending_up, color: Color(0xFF43A047)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '🟢 Live sync — orders & revenue\n'
                            'update automatically in real time.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: doLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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

  Widget sidebarWidget() {
    final groups = [
      ('Overview', [('dashboard', '📊', 'Dashboard')]),
      (
        'Catalogue',
        [
          ('upload', '📦', 'Product Upload'),
          ('products', '👗', 'All Products'),
        ],
      ),
      (
        'Sales',
        [
          ('ordersmgmt', '🧾', 'Orders'),
          ('customers', '👤', 'Customers'),
          ('contactformhub', '📨', 'Contact Form'),
          ('datarequests', '❌', 'Cancellation Msg'),
        ],
      ),
      (
        'Engagement',
        [
          ('reviews', '⭐', 'Reviews'),
          ('grievances', '⚖️', 'Complaints'),
        ],
      ),
      (
        'Finance',
        [
          ('revenue', '💰', 'Revenue'),
          ('analysis', '📊', 'Analysis'),
          ('notifications', '🔔', 'Send Notification'),
        ],
      ),
    ];

    return Container(
      width: 240,
      color: sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Row(
              children: [
                const Text('👗', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Sumathi's Styles",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Admin Dashboard',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .55),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(
                      group.$1.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .35),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  for (final item in group.$2)
                    InkWell(
                      onTap: () => showPage(item.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: currentPage == item.$1
                              ? const Color(0xFF00695C)
                              : Colors.transparent,
                          border: Border(
                            left: BorderSide(
                              color: currentPage == item.$1
                                  ? copper
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(item.$2, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.$3,
                                style: TextStyle(
                                  color: currentPage == item.$1
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: .75),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: doLogout,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: .1)),
                ),
              ),
              child: Row(
                children: [
                  const Text('🚪', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .65),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget topbarWidget(bool mobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 28, vertical: 12),
      decoration: BoxDecoration(
        color: loginBlue,
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8)],
      ),
      child: Row(
        children: [
          if (mobile)
            InkWell(
              onTap: () => setState(() => mobilePageMode = false),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 6),
                  ],
                ),
                child: Icon(Icons.arrow_back, color: loginBlue, size: 20),
              ),
            )
          else
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('← Back', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titleFor(currentPage),
              style: TextStyle(
                fontSize: mobile ? 16 : 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          if (!mobile) ...[
            Text(
              '${DateTime.now().weekday.weekdayName()}, '
              '${DateTime.now().day} ${monthName(DateTime.now().month)} '
              '${DateTime.now().year}',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(width: 14),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _newOrdersBadge = 0;
                  _newContactsBadge = 0;
                });
                showPage('ordersmgmt');
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('🔔'),
                  ),
                  if (_newOrdersBadge + _newContactsBadge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Text(
                          '${_newOrdersBadge + _newContactsBadge}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              onPressed: () => showPage('ordersmgmt'),
              child: const Text(
                '🧾 Go to Orders',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

extension on int {
  String weekdayName() {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[this - 1];
  }
}

/// Draws the shield used on the login screen — a port of the admin.html SVG:
/// M50 4 L92 18 V48 C92 74 74 92 50 98 C26 92 8 74 8 48 V18 Z
class ShieldPainter extends CustomPainter {
  ShieldPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 100;
    final sy = size.height / 100;
    final path = Path()
      ..moveTo(50 * sx, 4 * sy)
      ..lineTo(92 * sx, 18 * sy)
      ..lineTo(92 * sx, 48 * sy)
      ..cubicTo(92 * sx, 74 * sy, 74 * sx, 92 * sy, 50 * sx, 98 * sy)
      ..cubicTo(26 * sx, 92 * sy, 8 * sx, 74 * sy, 8 * sx, 48 * sy)
      ..lineTo(8 * sx, 18 * sy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant ShieldPainter oldDelegate) =>
      oldDelegate.color != color;
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF757575)),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Ordered':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        break;
      case 'Processing':
        bg = const Color(0xFFEDE7F6);
        fg = const Color(0xFF4527A0);
        break;
      case 'Shipping':
        bg = const Color(0xFFE1F5FE);
        fg = const Color(0xFF0277BD);
        break;
      case 'Delivered':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case 'Cancelled':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFE53935);
        break;
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class RevenueCard extends StatelessWidget {
  const RevenueCard({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    required this.color1,
    required this.color2,
  });
  final String label;
  final String value;
  final String sub;
  final Color color1;
  final Color color2;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color1, color2]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SimpleChart extends StatelessWidget {
  const SimpleChart({
    super.key,
    required this.data,
    required this.bar,
    required this.color,
  });
  final List<num> data;
  final bool bar;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ChartPainter(data: data, bar: bar, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.data, required this.bar, required this.color});
  final List<num> data;
  final bool bar;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final maxValue = math.max(1, data.fold<num>(0, (a, b) => math.max(a, b)));
    final bottom = size.height - 28;
    const top = 12.0;
    final chartHeight = bottom - top;

    if (bar) {
      final gap = size.width / data.length;
      for (int i = 0; i < data.length; i++) {
        final h = (data[i] / maxValue) * chartHeight;
        final rect = Rect.fromLTWH(
          i * gap + gap * .18,
          bottom - h,
          gap * .64,
          h,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = color.withValues(alpha: .7),
        );
      }
    } else {
      final path = Path();
      for (int i = 0; i < data.length; i++) {
        final x = data.length == 1
            ? size.width / 2
            : i * size.width / (data.length - 1);
        final y = bottom - (data[i] / maxValue) * chartHeight;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
      for (int i = 0; i < data.length; i++) {
        final x = data.length == 1
            ? size.width / 2
            : i * size.width / (data.length - 1);
        final y = bottom - (data[i] / maxValue) * chartHeight;
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.bar != bar ||
      oldDelegate.color != color;
}

class StatusChart extends StatelessWidget {
  const StatusChart({super.key, required this.orders});
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'Ordered': 0,
      'Processing': 0,
      'Shipping': 0,
      'Delivered': 0,
      'Cancelled': 0,
    };
    for (final o in orders) {
      final s = '${o['status']}';
      if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
    }
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Center(
      child: SizedBox(
        width: 190,
        height: 190,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(190, 190),
              painter: _DonutPainter(values: counts.values.toList()),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'Orders',
                  style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values});
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF4527A0),
      const Color(0xFF2E7D32),
      const Color(0xFFE53935),
      const Color(0xFFE65100),
    ];
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.width / 2 - 12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..color = const Color(0xFFE0E0E0),
      );
      return;
    }
    var start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(
          center: size.center(Offset.zero),
          radius: size.width / 2 - 12,
        ),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24
          ..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}