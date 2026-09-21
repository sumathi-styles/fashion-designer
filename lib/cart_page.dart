import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_colors.dart';
import 'app_state.dart';
import 'models.dart';
import 'checkout.dart';
import 'login_page.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        final List<Product> items = List<Product>.from(
          state.cartItems,
        );

        final bool isEmpty = items.isEmpty;

        return Scaffold(
          backgroundColor: AppColors.light,
          appBar: AppBar(
            title: const Text(
              'My Cart',
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: isEmpty
                      ? _emptyState(context)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            12,
                            12,
                            12,
                            20,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final product = items[index];

                            return _cartTile(
                              context,
                              state,
                              product,
                            );
                          },
                        ),
                ),
                _bottomBar(
                  context,
                  state,
                  items,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================================================================
  // EMPTY CART
  // ================================================================

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 48,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your cart is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add some products to your cart and they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('Continue Shopping'),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // BOTTOM BAR
  // ================================================================

  Widget _bottomBar(
    BuildContext context,
    AppState state,
    List<Product> items,
  ) {
    final bool isEmpty = items.isEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            14,
            16,
            14,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '₹${state.cartTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckoutPage(
                                items: List<Product>.from(items),
                                fromCart: true,
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isEmpty ? AppColors.gray : AppColors.gold,
                    foregroundColor: AppColors.dark,
                    disabledForegroundColor: AppColors.textLight,
                    disabledBackgroundColor: AppColors.gray,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                    ),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: const Text(
                    'Checkout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // CART TILE
  // ================================================================

  Widget _cartTile(
    BuildContext context,
    AppState state,
    Product product,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 82,
                    height: 82,
                    color: AppColors.gray.withValues(alpha: 0.25),
                    child: product.isNetworkImage
                        ? Image.network(
                            product.image,
                            width: 82,
                            height: 82,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return _imagePlaceholder();
                            },
                          )
                        : Image.asset(
                            product.image,
                            width: 82,
                            height: 82,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return _imagePlaceholder();
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                _openProductDetails(
                                  context,
                                  product,
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 24,
                                  color: AppColors.textLight,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹${product.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _qtyBtn(
                            Icons.remove,
                            () {
                              if (product.qty > 1) {
                                state.updateQty(
                                  product.id,
                                  product.qty - 1,
                                );
                              } else {
                                state.removeFromCart(product.id);
                              }
                            },
                          ),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 36,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${product.qty}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _qtyBtn(
                            Icons.add,
                            () {
                              state.updateQty(
                                product.id,
                                product.qty + 1,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
          ),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.delete_outline,
                  label: 'Remove',
                  color: AppColors.danger,
                  onTap: () {
                    state.removeFromCart(product.id);
                  },
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: AppColors.gray,
              ),
              Expanded(
                child: _actionBtn(
                  icon: Icons.favorite_border,
                  label: 'Move to Wishlist',
                  color: AppColors.text,
                  onTap: () {
                    state.addToWishlist(product);
                    state.removeFromCart(product.id);

                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            '${product.name} moved to Wishlist',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                  },
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: AppColors.gray,
              ),
              Expanded(
                child: _actionBtn(
                  icon: Icons.flash_on,
                  label: 'Buy Now',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CheckoutPage(
                          items: [product],
                          fromCart: true,
                          quantities: {
                            product.id:
                                product.qty > 0 ? product.qty : 1,
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================
  // OPEN PRODUCT DETAILS
  // ================================================================

  void _openProductDetails(
    BuildContext context,
    Product product,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CartProductDetailsPage(
          product: product,
        ),
      ),
    );
  }

  // ================================================================
  // IMAGE PLACEHOLDER
  // ================================================================

  Widget _imagePlaceholder() {
    return Container(
      width: 82,
      height: 82,
      color: AppColors.gray,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 30,
        color: AppColors.textLight,
      ),
    );
  }

  // ================================================================
  // ACTION BUTTON
  // ================================================================

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // QUANTITY BUTTON
  // ================================================================

  Widget _qtyBtn(
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.gray,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// CART PRODUCT DETAILS PAGE
// (rebuilt to match product_details_page.dart: description/highlights
// come straight from the Product object, address is loaded from
// saved_addresses/users the same way, reviews section has the
// eligibility + edit-review flow.)
// =====================================================================

class CartProductDetailsPage extends StatefulWidget {
  final Product product;

  const CartProductDetailsPage({
    super.key,
    required this.product,
  });

  @override
  State<CartProductDetailsPage> createState() =>
      _CartProductDetailsPageState();
}

class _CartProductDetailsPageState extends State<CartProductDetailsPage> {
  int _qty = 1;

  bool _loadingAddress = true;
  String _address = '';
  String _recipient = '';
  String _addressPhone = '';

  bool _loadingReviews = true;
  List<Map<String, dynamic>> _productReviews = [];
  bool _checkingEligibility = true;
  bool _eligibleToReview = false;
  Map<String, dynamic>? _myReview;
  final _reviewCommentCtrl = TextEditingController();
  int _reviewRating = 0;

  static const String _brandName = "SUMATHI'S STYLE";

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    _loadSavedAddress();
    _loadProductReviews();
    _checkReviewEligibility();
  }

  @override
  void dispose() {
    _reviewCommentCtrl.dispose();
    super.dispose();
  }

  // ================================================================
  // LOAD SAVED ADDRESS
  // ================================================================

  Future<void> _loadSavedAddress() async {
    final phone = (AppState.instance.userId ?? '').trim();

    if (phone.isEmpty) {
      if (mounted) setState(() => _loadingAddress = false);
      return;
    }

    try {
      QuerySnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection('saved_addresses')
              .doc(phone)
              .collection('addresses')
              .orderBy('updatedAt', descending: true)
              .limit(1)
              .get();

      // Backward-compatible fallback for addresses saved by the
      // ApiService address flow under users/{userId}/addresses.
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(phone)
            .collection('addresses')
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .get();
      }

      if (!mounted) return;

      if (snap.docs.isEmpty) {
        setState(() {
          _address = '';
          _recipient = '';
          _addressPhone = '';
          _loadingAddress = false;
        });
        return;
      }

      final data = snap.docs.first.data();

      final parts = <String>[
        '${data['door'] ?? ''}'.trim(),
        '${data['street'] ?? ''}'.trim(),
        '${data['area'] ?? ''}'.trim(),
        '${data['city'] ?? ''}'.trim(),
        '${data['state'] ?? ''}'.trim(),
        '${data['pin'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).toList();

      setState(() {
        _recipient = '${data['recipient'] ?? ''}'.trim();
        _addressPhone = '${data['phone'] ?? ''}'.trim();
        _address = parts.join(', ');
        _loadingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAddress = false);
    }
  }

  // ================================================================
  // REVIEWS
  // ================================================================

  Future<void> _loadProductReviews() async {
    setState(() => _loadingReviews = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('product', isEqualTo: product.name)
          .get();
      final loaded = snap.docs.map((doc) {
        final m = doc.data();
        return {
          'id': doc.id,
          'mobile': '${m['mobile'] ?? ''}',
          'name': '${m['name'] ?? ''}',
          'rating': (num.tryParse('${m['rating'] ?? 5}') ?? 5).toInt(),
          'comment': '${m['comment'] ?? ''}',
        };
      }).toList();
      if (!mounted) return;
      setState(() => _productReviews = loaded);
    } catch (_) {
      // reviews are supplementary — fail silently
    } finally {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _checkReviewEligibility() async {
    final phone = (AppState.instance.userId ?? '').trim();
    if (phone.isEmpty) {
      if (mounted) setState(() => _checkingEligibility = false);
      return;
    }
    try {
      final orderSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('mobile', isEqualTo: phone)
          .where('product', isEqualTo: product.name)
          .where('status', isEqualTo: 'Delivered')
          .limit(1)
          .get();
      final reviewSnap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('mobile', isEqualTo: phone)
          .where('product', isEqualTo: product.name)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        _eligibleToReview = orderSnap.docs.isNotEmpty;
        _myReview = reviewSnap.docs.isNotEmpty
            ? {'id': reviewSnap.docs.first.id, ...reviewSnap.docs.first.data()}
            : null;
      });
    } catch (_) {
      // ignore — treat as not eligible
    } finally {
      if (mounted) setState(() => _checkingEligibility = false);
    }
  }

  double get _averageRating {
    if (_productReviews.isEmpty) return product.rating;
    final total = _productReviews.fold<int>(
      0,
      (s, r) => s + ((r['rating'] as num?)?.toInt() ?? 0),
    );
    return total / _productReviews.length;
  }

  Future<void> _submitProductReview() async {
    final phone = (AppState.instance.userId ?? '').trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to write a review!')),
      );
      return;
    }
    try {
      final data = {
        'mobile': phone,
        'name': AppState.instance.userName ?? '',
        'product': product.name,
        'productImage': product.image,
        'rating': _reviewRating,
        'comment': _reviewCommentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existingId = _myReview?['id']?.toString() ?? '';
      if (existingId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('reviews')
            .doc(existingId)
            .update(data);
      } else {
        await FirebaseFirestore.instance.collection('reviews').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your review!')),
      );
      await _loadProductReviews();
      await _checkReviewEligibility();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit review: $e')),
        );
      }
    }
  }

  void _openWriteReviewSheet() {
    _reviewCommentCtrl.text = _myReview?['comment']?.toString() ?? '';
    _reviewRating = (_myReview?['rating'] as num?)?.toInt() ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _myReview != null ? 'Edit Your Review' : 'Rate this Product',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        final selected = star <= _reviewRating;
                        return IconButton(
                          onPressed: () => setSheet(() => _reviewRating = star),
                          iconSize: 34,
                          icon: Icon(
                            selected ? Icons.star_rounded : Icons.star_border_rounded,
                            color: selected ? AppColors.gold : Colors.grey.shade400,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reviewCommentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Tell others about this product...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_reviewRating == 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please select a star rating!')),
                            );
                            return;
                          }
                          _submitProductReview();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Submit Review',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
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

  // ================================================================
  // CART HELPERS
  // ================================================================

  bool get _isWishlisted =>
      AppState.instance.wishlistIds.contains(product.id);

  bool get _isInCart =>
      AppState.instance.cartItems.any((p) => p.id == product.id);

  Product _productWithQty(int qty) {
    return product.copyWith(qty: qty);
  }

  void _addToCart() {
    AppState.instance.addToCart(_productWithQty(_qty));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to cart! 🛒'),
        action: SnackBarAction(label: 'VIEW CART', onPressed: _goToCart),
      ),
    );
  }

  void _goToCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartPage()),
    );
  }

  void _buyNow() {
    final item = _productWithQty(_qty);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          items: [item],
          fromCart: true,
          quantities: {item.id: _qty},
        ),
      ),
    );
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.light,
          appBar: AppBar(
            title: const Text(
              'Product Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(
                  _isWishlisted ? Icons.favorite : Icons.favorite_border,
                  color: _isWishlisted ? Colors.red : Colors.white,
                ),
                onPressed: () {
                  AppState.instance.toggleWishlist(product);
                },
              ),
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                onPressed: _goToCart,
              ),
            ],
          ),
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadSavedAddress,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductImage(),
                  _buildProductInfo(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ================================================================
  // PRODUCT IMAGE
  // Uses BoxFit.contain (instead of cover) inside a taller frame so the
  // ENTIRE portrait photo — including the model's face at the top — is
  // always visible, never cropped.
  // ================================================================

  Widget _buildProductImage() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 320, maxHeight: 480),
      color: Colors.white,
      alignment: Alignment.center,
      child: product.isNetworkImage
          ? Image.network(
              product.image,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _imagePlaceholder(),
            )
          : Image.asset(
              product.image,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _imagePlaceholder(),
            ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.gray,
      alignment: Alignment.center,
      height: 320,
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 44,
        color: AppColors.textLight,
      ),
    );
  }

  // ================================================================
  // PRODUCT INFORMATION
  // Order: name -> rating -> price -> quantity -> delivery card ->
  //        add to cart/buy now -> description -> highlights -> reviews
  // ================================================================

  Widget _buildProductInfo() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            _brandName,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF35A853),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _averageRating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.star, color: Colors.white, size: 11),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_productReviews.length} review${_productReviews.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.textLight, fontSize: 12),
              ),
            ],
          ),
          const Divider(height: 26),
          Text(
            '₹${product.price.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 16),

          // QUANTITY
          _buildQuantity(),
          const SizedBox(height: 22),
          const Divider(height: 1),
          const SizedBox(height: 18),

          // DELIVERY CARD
          _buildDeliveryCard(),
          const SizedBox(height: 18),

          // ADD TO CART / BUY NOW
          _buildActionButtons(),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // DESCRIPTION + HIGHLIGHTS
          _buildDescription(),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 18),

          // RATINGS & REVIEWS
          _buildReviewsSection(),
        ],
      ),
    );
  }

  // ================================================================
  // DELIVERY CARD
  // ================================================================

  Widget _buildDeliveryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.home_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(child: _buildAddressContent()),
              if (!_loadingAddress && _address.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, size: 18, color: AppColors.textLight),
                ),
            ],
          ),
          const Divider(height: 20),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_shipping_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Custom stitched — delivered within 10–15 days',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================================
  // ADDRESS CONTENT
  // ================================================================

  Widget _buildAddressContent() {
    if (_loadingAddress) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
          SizedBox(width: 10),
          Text(
            'Loading saved address...',
            style: TextStyle(color: AppColors.textLight, fontSize: 12.5),
          ),
        ],
      );
    }

    if (_address.isEmpty) {
      return const Text(
        'Add a delivery address in your profile',
        style: TextStyle(color: AppColors.textLight, fontSize: 13, height: 1.35),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recipient.isNotEmpty)
          Text(
            _recipient,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        const SizedBox(height: 3),
        Text(
          _address,
          style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.text),
        ),
        if (_addressPhone.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            'Phone: +91 $_addressPhone',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textLight),
          ),
        ],
      ],
    );
  }

  // ================================================================
  // QUANTITY
  // ================================================================

  Widget _buildQuantity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quantity',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gray),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () {
                  if (_qty > 1) setState(() => _qty--);
                },
                icon: const Icon(Icons.remove, size: 16),
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$_qty',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_qty < 10) setState(() => _qty++);
                },
                icon: const Icon(Icons.add, size: 16),
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================
  // ACTION BUTTONS
  // ================================================================

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_isInCart) {
                  _goToCart();
                } else {
                  _addToCart();
                }
              },
              icon: Icon(
                _isInCart ? Icons.shopping_cart_checkout : Icons.shopping_cart,
                size: 16,
              ),
              label: Text(
                _isInCart ? 'View Cart' : 'Add to Cart',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _buyNow,
              icon: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('Buy Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.dark,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ================================================================
  // DESCRIPTION
  // ================================================================

  Widget _buildDescription() {
    final description = product.description.trim();
    final highlights = product.highlights
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList();

    final hasDescription = description.isNotEmpty;
    final hasHighlights = highlights.isNotEmpty;

    // Do not show a Description/Highlights area at all when the admin
    // has not entered either field — same rule as product_details_page.dart.
    if (!hasDescription && !hasHighlights) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDescription) ...[
          const Text(
            'Description',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.5),
          ),
        ],
        if (hasDescription && hasHighlights) const SizedBox(height: 18),
        if (hasHighlights) ...[
          const Text(
            'Product Highlights',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            highlights.map((h) => '• $h').join('\n'),
            style: const TextStyle(fontSize: 13, color: AppColors.textLight, height: 1.5),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  // ================================================================
  // RATINGS & REVIEWS SECTION
  // ================================================================

  Widget _buildReviewsSection() {
    final avg = _averageRating;
    final phone = (AppState.instance.userId ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Ratings & Reviews', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (!_checkingEligibility)
              TextButton.icon(
                onPressed: phone.isEmpty
                    ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()))
                    : (_eligibleToReview ? _openWriteReviewSheet : null),
                icon: Icon(_myReview != null ? Icons.edit_outlined : Icons.star_border_rounded, size: 17),
                label: Text(
                  phone.isEmpty ? 'Login to Review' : (_myReview != null ? 'Edit Review' : 'Write a Review'),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
          ],
        ),
        if (phone.isNotEmpty && !_checkingEligibility && !_eligibleToReview && _myReview == null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              'Buy this product and once it is delivered, you can write a review.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.star_rounded, color: AppColors.gold, size: 20),
            const SizedBox(width: 4),
            Text(avg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              '(${_productReviews.length} review${_productReviews.length == 1 ? '' : 's'})',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textLight),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else if (_productReviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No reviews yet. Be the first to review this product!',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          )
        else
          ..._productReviews.map((r) => _productReviewCard(r, phone)),
      ],
    );
  }

  Widget _productReviewCard(Map<String, dynamic> review, String myPhone) {
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final comment = review['comment']?.toString() ?? '';
    final rawName = review['name']?.toString().trim() ?? '';
    final name = rawName.isNotEmpty ? rawName : 'Customer';
    final isMine = myPhone.isNotEmpty && review['mobile'] == myPhone;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isMine ? '$name (You)' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text('★' * rating + '☆' * (5 - rating), style: const TextStyle(color: AppColors.gold, fontSize: 13)),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment, style: const TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.5)),
          ],
        ],
      ),
    );
  }
}