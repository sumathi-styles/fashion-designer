import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_colors.dart';
import 'app_state.dart';
import 'api_service.dart';
import 'models.dart';

import 'location_picker_page.dart';
import 'shop_page.dart';
import 'cart_page.dart';
import 'wishlist_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'catering_page.dart';
import 'custom_order_page.dart';
import 'login_page.dart';
import 'poster_page.dart';
import 'product_details_page.dart';

import 'class_page.dart';
import 'contact.dart';

/// ---------------------------------------------------------------------
/// HOME PAGE
/// ---------------------------------------------------------------------

class HomePage extends StatefulWidget {
  final ValueChanged<Product>? onProductTap;
  final ValueChanged<String>? onCategoryTap;

  const HomePage({
    super.key,
    this.onProductTap,
    this.onCategoryTap,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>();

  final PageController _heroController = PageController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController =
      TextEditingController();

  Timer? _heroTimer;

  int _heroIndex = 0;

  bool _loadingProducts = true;

  List<Product> _featuredProducts = [];
  List<Product> _suggestedProducts = [];

  // ===============================================================
  // HOME ADDRESS
  // ===============================================================

  bool _loadingAddress = true;

  String _homeAddress = '';

  // ---------------------------------------------------------------
  // QUICK CATEGORIES
  // ---------------------------------------------------------------

  final List<QuickCategory> _quickCategories = const [
    QuickCategory(
      'Kids Wear',
      'assets/images/kids.png',
    ),
    QuickCategory(
      'Uniform',
      'assets/images/unifrom.png',
    ),
    QuickCategory(
      'Modern Wear',
      'assets/images/modern.png',
    ),
    QuickCategory(
      'Salwar',
      'assets/images/salwar.png',
    ),
    QuickCategory(
      'Blouse',
      'assets/images/Blouse.png',
    ),
    QuickCategory(
      'Aari Work',
      'assets/images/Aari wrk.png',
    ),
    QuickCategory(
      'Saree Pre-pleating',
      'assets/images/ss.jpg',
    ),
    QuickCategory(
      'Frocks',
      'assets/images/Frocks.png',
    ),
    QuickCategory(
      'Lehenga',
      'assets/images/leng.jpg',
    ),
    QuickCategory(
      'Kurthi',
      'assets/images/kurthi.png',
    ),
  ];

  // ---------------------------------------------------------------
  // HERO SLIDES
  // ---------------------------------------------------------------

  late final List<HeroSlide> _heroSlides = [
    HeroSlide(
      title: 'Traditional Elegance',
      subtitle: 'Modern Style',
      tagline: 'Custom Stitching • Bridal Wear • Aari Work',
      imageUrl: 'assets/images/model.png',
      buttonLabel: 'Shop Now',
      buttonColor: AppColors.gold,
      buttonTextColor: AppColors.dark,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ShopPage(),
          ),
        );
      },
    ),
    HeroSlide(
      title: 'Exclusive',
      subtitle: 'Bridal Package',
      tagline: 'Full Bridal Set • Aari Work • Custom Fit',
      imageUrl: 'assets/images/model.png',
      buttonLabel: 'Bridal Package',
      buttonColor: AppColors.gold,
      buttonTextColor: AppColors.dark,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PosterPage(),
          ),
        );
      },
    ),
    HeroSlide(
      title: 'Design It',
      subtitle: 'Your Way',
      tagline: 'Any Design • Any Fabric • Perfect Fit',
      imageUrl: 'assets/images/model.png',
      buttonLabel: 'Custom Order',
      buttonColor: AppColors.gold,
      buttonTextColor: AppColors.dark,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CustomOrderPage(),
          ),
        );
      },
    ),
  ];

  // ---------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _loadProducts();
    _startHeroAutoplay();

    AppState.instance.loadSavedDeliveryLocation();

    _loadHomeAddress();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    _scrollController.dispose();
    _searchController.dispose();

    super.dispose();
  }

  // ===============================================================
  // LOAD SAVED HOME ADDRESS
  // ===============================================================

  Future<void> _loadHomeAddress() async {
    final state = AppState.instance;
    final userId = state.userId;

    // If user is not logged in, use the existing location value.
    if (userId == null || userId.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        _homeAddress = state.deliveryLocation.trim();
        _loadingAddress = false;
      });

      return;
    }

    try {
      // Fetch the MOST RECENTLY UPDATED saved address (not just any
      // doc) so this always matches the latest full address the
      // customer saved — avoids showing a stale/incomplete entry
      // (e.g. one missing door/street/area) that just happens to be
      // first in the collection.
      final snapshot = await FirebaseFirestore.instance
          .collection('saved_addresses')
          .doc(userId)
          .collection('addresses')
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();

        final address = _buildFullAddress(data);

        setState(() {
          _homeAddress = address.isNotEmpty
              ? address
              : state.deliveryLocation.trim();

          _loadingAddress = false;
        });
      } else {
        setState(() {
          _homeAddress = state.deliveryLocation.trim();
          _loadingAddress = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _homeAddress = state.deliveryLocation.trim();
        _loadingAddress = false;
      });
    }
  }

  // ===============================================================
  // BUILD FULL ADDRESS FROM FIRESTORE
  // ===============================================================

  String _buildFullAddress(
    Map<String, dynamic> data,
  ) {
    final parts = <String>[];

    final door = _cleanText(data['door']);
    final street = _cleanText(data['street']);
    final area = _cleanText(data['area']);
    final city = _cleanText(data['city']);
    final state = _cleanText(data['state']);
    final pin = _cleanText(data['pin']);

    if (door.isNotEmpty) {
      parts.add(door);
    }

    if (street.isNotEmpty) {
      parts.add(street);
    }

    if (area.isNotEmpty) {
      parts.add(area);
    }

    if (city.isNotEmpty) {
      parts.add(city);
    }

    if (state.isNotEmpty) {
      parts.add(state);
    }

    if (pin.isNotEmpty) {
      parts.add(pin);
    }

    return parts.join(', ');
  }

  // ===============================================================
  // CLEAN FIRESTORE TEXT
  // ===============================================================

  String _cleanText(dynamic value) {
    if (value == null) return '';

    return value.toString().trim();
  }

  // ===============================================================
  // OPEN / CHANGE ADDRESS
  // ===============================================================

  Future<void> _changeHomeAddress() async {
    final picked = await LocationPickerSheet.show(context);

    if (picked == null) return;

    final state = AppState.instance;

    final display = picked.addressLine.trim().isNotEmpty
        ? picked.addressLine.trim()
        : (picked.label.trim().isNotEmpty
            ? picked.label.trim()
            : 'Selected location');

    await state.setDeliveryLocation(
      display,
      lat: picked.latitude,
      lng: picked.longitude,
      pincode: picked.pincode,
    );

    // Reload Firestore saved address so Home Page shows
    // complete address + phone immediately.
    await _loadHomeAddress();
  }

  // ---------------------------------------------------------------
  // HERO AUTOPLAY
  // ---------------------------------------------------------------

  void _startHeroAutoplay() {
    _heroTimer?.cancel();

    _heroTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) {
        if (!mounted ||
            !_heroController.hasClients ||
            _heroSlides.isEmpty) {
          return;
        }

        final next =
            (_heroIndex + 1) % _heroSlides.length;

        _heroController.animateToPage(
          next,
          duration: const Duration(
            milliseconds: 500,
          ),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // LOAD PRODUCTS
  // ---------------------------------------------------------------

  Future<void> _loadProducts() async {
    try {
      final products = await ApiService.fetchProducts();

      if (!mounted) return;

      setState(() {
        _splitProducts(products);
        _loadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _featuredProducts = [];
        _suggestedProducts = [];
        _loadingProducts = false;
      });
    }
  }

  void _splitProducts(List<Product> products) {
    const featuredCount = 4;

    _featuredProducts =
        products.take(featuredCount).toList();

    _suggestedProducts = products.length > featuredCount
        ? products.skip(featuredCount).toList()
        : [];
  }

  // ---------------------------------------------------------------
  // SCROLL HOME
  // ---------------------------------------------------------------

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0,
      duration: const Duration(
        milliseconds: 400,
      ),
      curve: Curves.easeInOut,
    );
  }

  // ---------------------------------------------------------------
  // SEARCH SUBMIT
  // ---------------------------------------------------------------

  void _submitSearch(String query) {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopPage(
          initialFilter: trimmed,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.light,

          drawer: _buildDrawer(context),

          body: SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: _buildAppHeader(
                    context,
                    state,
                  ),
                ),

                SliverToBoxAdapter(
                  child: _buildHeroSlider(),
                ),

                SliverToBoxAdapter(
                  child: _buildFeaturedSection(
                    state,
                  ),
                ),

                _buildSuggestedGridSection(
                  state,
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===============================================================
  // HEADER
  // ===============================================================

  Widget _buildAppHeader(
    BuildContext context,
    AppState state,
  ) {
    final hour = DateTime.now().hour;

    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        15,
        12,
        15,
        14,
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // =====================================================
          // TOP ROW
          // =====================================================

          Row(
            children: [
              Image.asset(
                'assets/images/app.png',
                width: 34,
                height: 34,
                errorBuilder: (_, __, ___) {
                  return const Icon(
                    Icons.storefront,
                    color: AppColors.primary,
                    size: 34,
                  );
                },
              ),

              const SizedBox(width: 8),

              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily:
                          'PlayfairDisplay',
                      fontSize: 16,
                      color:
                          AppColors.primary,
                      fontWeight:
                          FontWeight.w600,
                    ),
                    children: [
                      TextSpan(
                        text: "Sumathi's ",
                      ),
                      TextSpan(
                        text: 'Styles',
                        style: TextStyle(
                          color:
                              AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              _headerIcon(
                Icons.notifications_none,
                state.unreadNotifCount,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const NotificationsPage(),
                    ),
                  );
                },
              ),

              _headerIcon(
                Icons.favorite_border,
                state.wishlistCount,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const WishlistPage(),
                    ),
                  );
                },
              ),

              _headerIcon(
                Icons.shopping_cart_outlined,
                state.cartCount,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const CartPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // =====================================================
          // MENU + GREETING + LOGIN
          // =====================================================

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      _scaffoldKey.currentState
                          ?.openDrawer();
                    },
                    borderRadius:
                        BorderRadius.circular(20),
                    child: const Padding(
                      padding:
                          EdgeInsets.only(
                        right: 8,
                      ),
                      child: Icon(
                        Icons.menu,
                        size: 24,
                        color:
                            AppColors.primary,
                      ),
                    ),
                  ),

                  Text(
                    '$greeting ✨',
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.w600,
                      color:
                          AppColors.text,
                    ),
                  ),
                ],
              ),

              // LOGIN / PROFILE
              state.isLoggedIn
                  ? InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const SettingsPage(),
                          ),
                        );
                      },
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                      child: Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration:
                            BoxDecoration(
                          color: AppColors
                              .primary
                              .withValues(
                            alpha: 0.1,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            20,
                          ),
                        ),
                        child: Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person,
                              size: 14,
                              color:
                                  AppColors.primary,
                            ),
                            const SizedBox(
                              width: 6,
                            ),
                            Text(
                              state.userName
                                          ?.isNotEmpty ==
                                      true
                                  ? state.userName!
                                      .split(' ')
                                      .first
                                  : 'Account',
                              style:
                                  const TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight.w600,
                                color:
                                    AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const LoginPage(),
                          ),
                        );
                      },
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primary,
                        foregroundColor:
                            Colors.white,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            20,
                          ),
                        ),
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                      child:
                          const Text(
                        'Login',
                        style:
                            TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),
            ],
          ),

          const SizedBox(height: 10),

          // =====================================================
          // DELIVERY ADDRESS CARD
          // =====================================================

          _buildHomeAddressCard(state),

          const SizedBox(height: 10),

          // =====================================================
          // SEARCH
          // =====================================================

          _buildSearchBar(),

          const SizedBox(height: 14),

          // =====================================================
          // CATEGORIES
          // =====================================================

          _buildQuickCategories(),
        ],
      ),
    );
  }

  // ===============================================================
  // HOME ADDRESS CARD  (Flipkart-style compact single-line bar)
  // ===============================================================

  Widget _buildHomeAddressCard(
    AppState state,
  ) {
    final address = _homeAddress.trim();

    final hasAddress = address.isNotEmpty;

    return Material(
      color: const Color(0xFFF9FEFD),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _changeHomeAddress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(
                alpha: 0.12,
              ),
            ),
          ),
          child: _loadingAddress
              ? const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Locating you...',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 19,
                      color: AppColors.primary,
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        hasAddress
                            ? address
                            : 'Set your delivery location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasAddress
                              ? AppColors.text
                              : AppColors.primary,
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textLight,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ===============================================================
  // HEADER ICON
  // ===============================================================

  Widget _headerIcon(
    IconData icon,
    int count,
    VoidCallback onTap,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding:
                  const EdgeInsets.all(6),
              child: Icon(
                icon,
                size: 20,
                color: AppColors.text,
              ),
            ),
            if (count > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding:
                      const EdgeInsets.all(3),
                  decoration:
                      const BoxDecoration(
                    color:
                        AppColors.secondary,
                    shape:
                        BoxShape.circle,
                  ),
                  constraints:
                      const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      fontSize: 9,
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // SEARCH BAR
  // ===============================================================

  Widget _buildSearchBar() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.gray,
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textLight,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction:
                  TextInputAction.search,
              onSubmitted: _submitSearch,
              decoration:
                  const InputDecoration(
                hintText:
                    'Search for sarees, blouses, aari work...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color:
                      AppColors.textLight,
                ),
                border:
                    InputBorder.none,
                isDense: true,
              ),
            ),
          ),

          InkWell(
            onTap: () =>
                _submitSearch(
              _searchController.text,
            ),
            borderRadius:
                BorderRadius.circular(20),
            child: const Padding(
              padding:
                  EdgeInsets.all(4),
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color:
                    AppColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // QUICK CATEGORY ROW
  // ===============================================================

  Widget _buildQuickCategories() {
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection:
            Axis.horizontal,
        itemCount:
            _quickCategories.length,
        separatorBuilder:
            (_, __) =>
                const SizedBox(width: 16),
        itemBuilder:
            (context, i) {
          final cat =
              _quickCategories[i];

          return GestureDetector(
            onTap: () {
              widget.onCategoryTap
                  ?.call(cat.label);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShopPage(
                    initialFilter:
                        cat.label,
                  ),
                ),
              );
            },
            child: SizedBox(
              width: 62,
              child: Column(
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                      child: Container(
                        color:
                            const Color(
                          0xFFFDF1E7,
                        ),
                        child: Image.asset(
                          cat.imageUrl,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          alignment:
                              Alignment.topCenter,
                          errorBuilder:
                              (_, __, ___) {
                            return const Icon(
                              Icons.checkroom,
                              color:
                                  AppColors.primary,
                              size: 28,
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    cat.label,
                    textAlign:
                        TextAlign.center,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      fontSize: 10,
                      fontWeight:
                          FontWeight.w600,
                      color:
                          AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===============================================================
  // DRAWER
  // ===============================================================

  Widget _buildDrawer(
    BuildContext context,
  ) {
    final drawerItems =
        <_NavItem>[
      _NavItem(
        'Home',
        Icons.home_outlined,
        () {
          Navigator.pop(context);
          _scrollToTop();
        },
      ),
      _NavItem(
        'Shop',
        Icons.shopping_bag_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ShopPage(),
            ),
          );
        },
      ),
      _NavItem(
        'Classes',
        Icons.school_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ClassPage(),
            ),
          );
        },
      ),
      _NavItem(
        'Custom Order',
        Icons.design_services_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const CustomOrderPage(),
            ),
          );
        },
      ),
      _NavItem(
        'Catering',
        Icons.restaurant_menu_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const CateringPage(),
            ),
          );
        },
      ),
      _NavItem(
        'Contact',
        Icons.call_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ContactPage(),
            ),
          );
        },
      ),
      _NavItem(
        'Settings',
        Icons.settings_outlined,
        () {
          Navigator.pop(context);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const SettingsPage(),
            ),
          );
        },
      ),
    ];

    return Drawer(
      backgroundColor:
          AppColors.light,
      child: SafeArea(
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Container(
              width:
                  double.infinity,
              padding:
                  const EdgeInsets.all(20),
              color:
                  AppColors.primary,
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/app.png',
                    width: 40,
                    height: 40,
                    errorBuilder:
                        (_, __, ___) {
                      return const Icon(
                        Icons.storefront,
                        color:
                            Colors.white,
                        size: 40,
                      );
                    },
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  const Expanded(
                    child: Text(
                      "Sumathi's Styles",
                      style:
                          TextStyle(
                        fontFamily:
                            'PlayfairDisplay',
                        fontSize: 18,
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child:
                  ListView.separated(
                padding:
                    const EdgeInsets
                        .symmetric(
                  vertical: 8,
                ),
                itemCount:
                    drawerItems.length,
                separatorBuilder:
                    (_, __) =>
                        const Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                ),
                itemBuilder:
                    (context, i) {
                  final item =
                      drawerItems[i];

                  return ListTile(
                    leading: Icon(
                      item.icon,
                      color:
                          AppColors.primary,
                    ),
                    title: Text(
                      item.label,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w600,
                        color:
                            AppColors.text,
                      ),
                    ),
                    trailing:
                        const Icon(
                      Icons
                          .arrow_forward_ios,
                      size: 13,
                      color:
                          AppColors.textLight,
                    ),
                    onTap:
                        item.onTap,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // HERO SLIDER
  // ===============================================================

  Widget _buildHeroSlider() {
    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(
              bottom:
                  Radius.circular(24),
            ),
            child:
                PageView.builder(
              controller:
                  _heroController,
              itemCount:
                  _heroSlides.length,
              onPageChanged: (i) {
                setState(
                  () => _heroIndex = i,
                );
              },
              itemBuilder:
                  (context, i) {
                return _buildHeroSlide(
                  _heroSlides[i],
                );
              },
            ),
          ),

          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children:
                  List.generate(
                _heroSlides.length,
                (i) {
                  final active =
                      i == _heroIndex;

                  return AnimatedContainer(
                    duration:
                        const Duration(
                      milliseconds: 300,
                    ),
                    margin:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 4,
                    ),
                    width:
                        active ? 22 : 8,
                    height: 8,
                    decoration:
                        BoxDecoration(
                      color: active
                          ? AppColors.gold
                          : Colors.white
                              .withValues(
                              alpha: 0.55,
                            ),
                      borderRadius:
                          BorderRadius
                              .circular(4),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // HERO SLIDE
  // ===============================================================

  Widget _buildHeroSlide(
    HeroSlide slide,
  ) {
    return GestureDetector(
      onTap: slide.onTap,
      child: Container(
        decoration:
            const BoxDecoration(
          gradient:
              LinearGradient(
            begin:
                Alignment.topLeft,
            end:
                Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.dark,
            ],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 60,
              child: Padding(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .center,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      slide.title,
                      style:
                          const TextStyle(
                        fontFamily:
                            'PlayfairDisplay',
                        fontSize: 17,
                        height: 1.2,
                        color:
                            Colors.white,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),

                    Text(
                      slide.subtitle,
                      style:
                          const TextStyle(
                        fontFamily:
                            'PlayfairDisplay',
                        fontSize: 17,
                        height: 1.2,
                        color: AppColors
                            .secondaryLight,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),

                    const SizedBox(
                      height: 6,
                    ),

                    Text(
                      slide.tagline,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors
                            .white
                            .withValues(
                          alpha: 0.9,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    ElevatedButton.icon(
                      onPressed:
                          slide.onTap,
                      style:
                          ElevatedButton
                              .styleFrom(
                        backgroundColor:
                            slide
                                .buttonColor,
                        foregroundColor:
                            slide
                                .buttonTextColor,
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            20,
                          ),
                        ),
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon:
                          const Icon(
                        Icons.arrow_forward,
                        size: 14,
                      ),
                      label: Text(
                        slide
                            .buttonLabel,
                        style:
                            const TextStyle(
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              flex: 40,
              child: ClipRect(
                child: Align(
                  alignment:
                      Alignment.topCenter,
                  heightFactor: 0.92,
                  child: Image.asset(
                    slide.imageUrl,
                    fit: BoxFit.cover,
                    alignment:
                        Alignment.topCenter,
                    height:
                        double.infinity,
                    errorBuilder:
                        (_, __, ___) {
                      return Container(
                        color:
                            AppColors
                                .primaryDark,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // FEATURED COLLECTION
  // ===============================================================

  Widget _buildFeaturedSection(
    AppState state,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        15,
        24,
        15,
        12,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Center(
            child: Column(
              children: [
                Text(
                  'Featured Collection',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontFamily:
                        'PlayfairDisplay',
                    fontSize: 24,
                    color:
                        AppColors.primary,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Handpicked designs — 30 years of crafting perfection',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_loadingProducts)
            const SizedBox(
              height: 240,
              child: Center(
                child:
                    CircularProgressIndicator(),
              ),
            )
          else if (_featuredProducts.isEmpty)
            const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'No products yet — check back soon!',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        AppColors.textLight,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 232,
              child: ListView.separated(
                scrollDirection:
                    Axis.horizontal,
                physics:
                    const BouncingScrollPhysics(),
                itemCount:
                    _featuredProducts
                        .length,
                separatorBuilder:
                    (_, __) =>
                        const SizedBox(
                  width: 10,
                ),
                itemBuilder:
                    (context, i) {
                  final product =
                      _featuredProducts[i];

                  return SizedBox(
                    width: 140,
                    child: RevealOnScroll(
                      tag:
                          'featured_${product.id}_$i',
                      child:
                          _buildProductCard(
                        product,
                        state,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ===============================================================
  // PRODUCT CARD
  // ===============================================================

  Widget _buildProductCard(
    Product product,
    AppState state,
  ) {
    final isWishlisted =
        state.wishlistIds.contains(
      product.id,
    );

    final isInCart =
        state.cartItems.any(
      (p) => p.id == product.id,
    );

    return GestureDetector(
      onTap: () {
        widget.onProductTap
            ?.call(product);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProductDetailsPage(
              product: product,
            ),
          ),
        );
      },
      child: Container(
        decoration:
            BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color:
                const Color(0xFFE8E8E8),
            width: 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(
                alpha: 0.055,
              ),
              blurRadius: 7,
              offset:
                  const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior:
            Clip.antiAlias,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius
                            .vertical(
                      top:
                          Radius.circular(
                        10,
                      ),
                    ),
                    child:
                        _productImage(
                      product,
                    ),
                  ),

                  Positioned(
                    top: 7,
                    right: 7,
                    child: Material(
                      color:
                          Colors.white,
                      shape:
                          const CircleBorder(),
                      elevation: 1.5,
                      child:
                          InkWell(
                        onTap: () {
                          state
                              .toggleWishlist(
                            product,
                          );
                        },
                        customBorder:
                            const CircleBorder(),
                        child:
                            SizedBox(
                          width: 29,
                          height: 29,
                          child:
                              Icon(
                            isWishlisted
                                ? Icons
                                    .favorite
                                : Icons
                                    .favorite_border,
                            size: 16,
                            color:
                                isWishlisted
                                    ? AppColors
                                        .danger
                                    : Colors
                                        .grey
                                        .shade700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF388E3C,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          4,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Text(
                            product
                                .rating
                                .toStringAsFixed(
                              1,
                            ),
                            style:
                                const TextStyle(
                              fontSize:
                                  9.5,
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          const SizedBox(
                              width: 2),
                          const Icon(
                            Icons.star,
                            size: 9,
                            color:
                                Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                8,
                8,
                7,
                8,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize:
                                11.5,
                            fontWeight:
                                FontWeight
                                    .w500,
                            color:
                                AppColors
                                    .text,
                          ),
                        ),
                        const SizedBox(
                            height: 4),
                        Text(
                          '₹${product.price.toStringAsFixed(0)}',
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize:
                                14,
                            fontWeight:
                                FontWeight
                                    .w800,
                            color:
                                Color(
                              0xFF212121,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                      width: 5),

                  Material(
                    color: isInCart
                        ? AppColors
                            .primaryDark
                        : AppColors
                            .primary
                            .withValues(
                            alpha:
                                0.10,
                          ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      7,
                    ),
                    child: InkWell(
                      onTap: () {
                        if (isInCart) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CartPage(),
                            ),
                          );
                        } else {
                          _addToCart(
                            product,
                            state,
                          );
                        }
                      },
                      borderRadius:
                          BorderRadius
                              .circular(
                        7,
                      ),
                      child:
                          SizedBox(
                        width: 31,
                        height: 31,
                        child: Icon(
                          isInCart
                              ? Icons
                                  .shopping_cart_checkout
                              : Icons
                                  .add_shopping_cart,
                          size: 16,
                          color: isInCart
                              ? Colors
                                  .white
                              : AppColors
                                  .primary,
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

  // ===============================================================
  // PRODUCT IMAGE
  // ===============================================================

  Widget _productImage(
    Product product, {
    double? height,
  }) {
    final img =
        product.image.trim();

    if (img.isEmpty) {
      return _imageError(height);
    }

    if (product.isNetworkImage) {
      return _TimedNetworkImage(
        url: img,
        height: height,
      );
    }

        return Container(
      width: double.infinity,
      height: height,
      color: AppColors.gray,
      child: Image.asset(
        img,
        width:
            double.infinity,
        height: height,
        fit: BoxFit.contain,
        alignment:
            Alignment.center,
        errorBuilder:
            (_, __, ___) {
          return _imageError(height);
        },
      ),
    );
  }

  Widget _imageError(
    double? height,
  ) {
    return Container(
      height: height,
      color:
          AppColors.gray,
      child:
          const Center(
        child: Icon(
          Icons
              .image_not_supported,
          color:
              AppColors.textLight,
        ),
      ),
    );
  }

  // ===============================================================
  // ADD TO CART
  // ===============================================================

  void _addToCart(
    Product product,
    AppState state,
  ) {
    state.addToCart(product);

    state.addNotification(
      'Added to cart',
      '${product.name} added to your cart.',
    );

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        behavior:
            SnackBarBehavior.floating,
        backgroundColor:
            Colors.white,
        elevation: 6,
        duration:
            const Duration(
          seconds: 2,
        ),
        margin:
            const EdgeInsets
                .symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        shape:
            RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(
            14,
          ),
          side: BorderSide(
            color: AppColors
                .primary
                .withValues(
              alpha: 0.15,
            ),
          ),
        ),
        padding:
            const EdgeInsets
                .symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        content: Row(
          children: [
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
              child:
                  product.isNetworkImage
                      ? Image.network(
                          product.image,
                          width: 40,
                          height: 40,
                          fit:
                              BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) =>
                                  Container(
                            width: 40,
                            height: 40,
                            color:
                                AppColors
                                    .gray,
                            child:
                                const Icon(
                              Icons
                                  .checkroom,
                              size: 18,
                              color:
                                  AppColors
                                      .textLight,
                            ),
                          ),
                        )
                      : Image.asset(
                          product.image,
                          width: 40,
                          height: 40,
                          fit:
                              BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) =>
                                  Container(
                            width: 40,
                            height: 40,
                            color:
                                AppColors
                                    .gray,
                            child:
                                const Icon(
                              Icons
                                  .checkroom,
                              size: 18,
                              color:
                                  AppColors
                                      .textLight,
                            ),
                          ),
                        ),
            ),

            const SizedBox(
                width: 10),

            Expanded(
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons
                            .check_circle,
                        size: 15,
                        color:
                            Colors.green,
                      ),
                      const SizedBox(
                          width: 4),
                      const Text(
                        'Added to cart',
                        style:
                            TextStyle(
                          fontSize:
                              12.5,
                          fontWeight:
                              FontWeight
                                  .w700,
                          color:
                              AppColors
                                  .text,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                      height: 2),

                  Text(
                    product.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                      fontSize:
                          11.5,
                      color:
                          AppColors
                              .textLight,
                    ),
                  ),
                ],
              ),
            ),

            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(
                        context)
                    .hideCurrentSnackBar();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const CartPage(),
                  ),
                );
              },
              child:
                  const Text(
                'VIEW CART',
                style:
                    TextStyle(
                  fontSize:
                      11.5,
                  fontWeight:
                      FontWeight
                          .w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // SUGGESTED PRODUCTS
  // ===============================================================

  SliverPadding
      _buildSuggestedGridSection(
    AppState state,
  ) {
    return SliverPadding(
      padding:
          const EdgeInsets.fromLTRB(
        15,
        10,
        15,
        8,
      ),
      sliver:
          SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding:
                  EdgeInsets.only(
                bottom: 12,
              ),
              child: Text(
                'Suggested For You',
                style:
                    TextStyle(
                  fontFamily:
                      'PlayfairDisplay',
                  fontSize: 20,
                  color:
                      AppColors.primary,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ),

          if (_loadingProducts)
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 180,
                child: Center(
                  child:
                      CircularProgressIndicator(),
                ),
              ),
            )
          else if (_suggestedProducts
              .isEmpty)
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'No more products yet — check back soon!',
                    style:
                        TextStyle(
                      fontSize: 13,
                      color:
                          AppColors
                              .textLight,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverLayoutBuilder(
              builder:
                  (context, constraints) {
                const gap = 10.0;

                final availableWidth =
                    constraints
                        .crossAxisExtent;

                final cardWidth =
                    (availableWidth -
                            (gap * 2)) /
                        3;

                return SliverGrid(
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        3,
                    mainAxisSpacing:
                        12,
                    crossAxisSpacing:
                        gap,
                    childAspectRatio:
                        cardWidth / 205,
                  ),
                  delegate:
                      SliverChildBuilderDelegate(
                    (context, i) {
                      final product =
                          _suggestedProducts[
                              i];

                      return RevealOnScroll(
                        tag:
                            'suggested_${product.id}_$i',
                        child:
                            _buildGridProductCard(
                          product,
                          state,
                        ),
                      );
                    },
                    childCount:
                        _suggestedProducts
                            .length,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ===============================================================
  // GRID PRODUCT CARD
  // ===============================================================

  Widget _buildGridProductCard(
    Product product,
    AppState state,
  ) {
    final isWishlisted =
        state.wishlistIds.contains(
      product.id,
    );

    final isInCart =
        state.cartItems.any(
      (p) => p.id == product.id,
    );

    return GestureDetector(
      onTap: () {
        widget.onProductTap
            ?.call(product);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProductDetailsPage(
              product: product,
            ),
          ),
        );
      },
      child: Container(
        decoration:
            BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color:
                const Color(0xFFE8E8E8),
            width: 0.7,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(
                alpha: 0.055,
              ),
              blurRadius: 7,
              offset:
                  const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior:
            Clip.antiAlias,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Expanded(
              child: Stack(
                fit:
                    StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius
                            .vertical(
                      top:
                          Radius.circular(
                        10,
                      ),
                    ),
                    child:
                        _productImage(
                      product,
                    ),
                  ),

                  Positioned(
                    top: 7,
                    right: 7,
                    child: Material(
                      color:
                          Colors.white,
                      shape:
                          const CircleBorder(),
                      elevation: 1.5,
                      child:
                          InkWell(
                        onTap: () {
                          state
                              .toggleWishlist(
                            product,
                          );
                        },
                        customBorder:
                            const CircleBorder(),
                        child:
                            SizedBox(
                          width: 29,
                          height: 29,
                          child:
                              Icon(
                            isWishlisted
                                ? Icons
                                    .favorite
                                : Icons
                                    .favorite_border,
                            size: 16,
                            color:
                                isWishlisted
                                    ? AppColors
                                        .danger
                                    : Colors
                                        .grey
                                        .shade700,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF388E3C,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          4,
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Text(
                            product
                                .rating
                                .toStringAsFixed(
                              1,
                            ),
                            style:
                                const TextStyle(
                              fontSize:
                                  9.5,
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          const SizedBox(
                              width: 2),
                          const Icon(
                            Icons.star,
                            size: 9,
                            color:
                                Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets
                      .fromLTRB(
                8,
                8,
                7,
                8,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .center,
                children: [
                  Expanded(
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          product.name,
                          maxLines:
                              1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize:
                                11.5,
                            fontWeight:
                                FontWeight
                                    .w500,
                            color:
                                AppColors
                                    .text,
                          ),
                        ),
                        const SizedBox(
                            height: 4),
                        Text(
                          '₹${product.price.toStringAsFixed(0)}',
                          maxLines:
                              1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize:
                                14,
                            fontWeight:
                                FontWeight
                                    .w800,
                            color:
                                Color(
                              0xFF212121,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                      width: 5),

                  Material(
                    color: isInCart
                        ? AppColors
                            .primaryDark
                        : AppColors
                            .primary
                            .withValues(
                            alpha:
                                0.10,
                          ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      7,
                    ),
                    child: InkWell(
                      onTap: () {
                        if (isInCart) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CartPage(),
                            ),
                          );
                        } else {
                          _addToCart(
                            product,
                            state,
                          );
                        }
                      },
                      borderRadius:
                          BorderRadius
                              .circular(
                        7,
                      ),
                      child:
                          SizedBox(
                        width: 31,
                        height: 31,
                        child: Icon(
                          isInCart
                              ? Icons
                                  .shopping_cart_checkout
                              : Icons
                                  .add_shopping_cart,
                          size: 16,
                          color: isInCart
                              ? Colors
                                  .white
                              : AppColors
                                  .primary,
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
}

// ===============================================================
// NAV ITEM MODEL
// ===============================================================

class _NavItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _NavItem(
    this.label,
    this.icon,
    this.onTap,
  );
}

// ===============================================================
// TIMED NETWORK IMAGE
// ===============================================================

class _TimedNetworkImage
    extends StatefulWidget {
  final String url;
  final double? height;

  const _TimedNetworkImage({
    required this.url,
    this.height,
  });

  @override
  State<_TimedNetworkImage>
      createState() =>
          _TimedNetworkImageState();
}

class _TimedNetworkImageState
    extends State<_TimedNetworkImage> {
  bool _timedOut = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer(
      const Duration(seconds: 8),
      () {
        if (mounted && !_timedOut) {
          setState(
            () => _timedOut = true,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancelTimer() {
    _timer?.cancel();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_timedOut) {
      return _errorPlaceholder();
    }

        return Container(
      width: double.infinity,
      height: widget.height,
      color: AppColors.gray,
      child: Image.network(
        widget.url,
        width: double.infinity,
        height: widget.height,
        fit: BoxFit.contain,
        alignment:
            Alignment.center,
        loadingBuilder:
            (context, child, progress) {
          if (progress == null) {
            _cancelTimer();
            return child;
          }

          return Container(
            height: widget.height,
            color: AppColors.gray,
            child:
                const Center(
              child:
                  CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder:
            (_, __, ___) {
          _cancelTimer();
          return _errorPlaceholder();
        },
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      height: widget.height,
      color: AppColors.gray,
      child:
          const Center(
        child: Icon(
          Icons
              .image_not_supported,
          color:
              AppColors.textLight,
        ),
      ),
    );
  }
}

// ===============================================================
// REVEAL ON SCROLL
// ===============================================================

class RevealOnScroll
    extends StatefulWidget {
  final Widget child;
  final String tag;

  const RevealOnScroll({
    super.key,
    required this.child,
    required this.tag,
  });

  @override
  State<RevealOnScroll>
      createState() =>
          _RevealOnScrollState();
}

class _RevealOnScrollState
    extends State<RevealOnScroll> {
  bool _visible = false;

  @override
  Widget build(
    BuildContext context,
  ) {
    return VisibilityDetector(
      key: Key(widget.tag),
      onVisibilityChanged:
          (info) {
        if (!_visible &&
            info.visibleFraction >
                0.15) {
          setState(() {
            _visible = true;
          });
        }
      },
      child: AnimatedOpacity(
        opacity:
            _visible ? 1 : 0,
        duration:
            const Duration(
          milliseconds: 450,
        ),
        curve:
            Curves.easeOut,
        child: AnimatedSlide(
          offset: _visible
              ? Offset.zero
              : const Offset(
                  0,
                  0.12,
                ),
          duration:
              const Duration(
            milliseconds: 450,
          ),
          curve:
              Curves.easeOut,
          child:
              widget.child,
        ),
      ),
    );
  }
}