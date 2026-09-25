import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_state.dart';
import 'models.dart';
import 'checkout.dart';
import 'product_details_page.dart';

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
  // Routes to the SAME ProductDetailsPage used everywhere else in the
  // app (product_details_page.dart) — this is the fix. Previously
  // cart_page.dart had its own duplicate CartProductDetailsPage with a
  // different (broken) address-loading path and a fixed oversized
  // image, which is why the cart's product page looked/behaved
  // differently from the normal product page.
  // ================================================================

  void _openProductDetails(
    BuildContext context,
    Product product,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
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