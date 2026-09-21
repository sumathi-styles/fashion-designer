import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_state.dart';
import '../models.dart';
import '../product_details_page.dart';


class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final items = state.wishlistItems;

        return Scaffold(
          backgroundColor: AppColors.light,

          // ==========================================================
          // APP BAR
          // ==========================================================
          appBar: AppBar(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                size: 28,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: const Text(
              'My Wishlist',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // ==========================================================
          // BODY
          // ==========================================================
          body: items.isEmpty
              ? _buildEmptyWishlist()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    // ------------------------------------------------
                    // RESPONSIVE GRID
                    // ------------------------------------------------
                    // Mobile  -> 3 columns
                    // Tablet  -> 4 columns
                    // Desktop -> 5 columns
                    final int crossAxisCount;

                    if (width >= 1100) {
                      crossAxisCount = 5;
                    } else if (width >= 700) {
                      crossAxisCount = 4;
                    } else {
                      crossAxisCount = 3;
                    }

                    final horizontalPadding =
                        width >= 700 ? 18.0 : 10.0;

                    final spacing =
                        width >= 700 ? 12.0 : 8.0;

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        20,
                      ),
                      physics:
                          const BouncingScrollPhysics(),

                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            crossAxisCount,

                        crossAxisSpacing:
                            spacing,

                        mainAxisSpacing:
                            spacing,

                        // ------------------------------------------------
                        // COMPACT HOME-STYLE CARD
                        // ------------------------------------------------
                        childAspectRatio:
                            width >= 700 ? 0.72 : 0.56,
                      ),

                      itemCount: items.length,

                      itemBuilder: (context, index) {
                        final product = items[index];

                        return _WishlistProductCard(
                          product: product,

                          onTap: () {
                            _openProductDetails(
                              context,
                              product,
                            );
                          },

                          onWishlistTap: () {
                            state.toggleWishlist(
                              product,
                            );
                          },

                          onCartTap: () {
                            _addToCart(
                              context,
                              state,
                              product,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  // ==========================================================
  // EMPTY WISHLIST
  // ==========================================================
  Widget _buildEmptyWishlist() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 42,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Your Wishlist is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),

            const SizedBox(height: 7),

            const Text(
              'Save your favourite styles here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // OPEN FULL PRODUCT DETAILS
  // ==========================================================
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

  // ==========================================================
  // ADD TO CART
  // ==========================================================
  void _addToCart(
    BuildContext context,
    AppState state,
    Product product,
  ) {
    state.addToCart(product);

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${product.name} added to cart 🛒',
        ),
        duration:
            const Duration(seconds: 1),
      ),
    );
  }
}

// ==================================================================
// WISHLIST PRODUCT CARD
// Compact Home Page Style
// ==================================================================

class _WishlistProductCard
    extends StatelessWidget {
  final Product product;

  final VoidCallback onTap;
  final VoidCallback onWishlistTap;
  final VoidCallback onCartTap;

  const _WishlistProductCard({
    required this.product,
    required this.onTap,
    required this.onWishlistTap,
    required this.onCartTap,
  });

  // ==========================================================
  // CHECK CART
  // ==========================================================
  bool _isAlreadyInCart() {
    return AppState.instance.cartItems.any(
      (item) => item.id == product.id,
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final isInCart = _isAlreadyInCart();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(10),

          border: Border.all(
            color: const Color(0xFFE8E8E8),
            width: 0.7,
          ),

          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(
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
              CrossAxisAlignment.start,
          children: [

            // ======================================================
            // PRODUCT IMAGE
            // ======================================================
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [

                  // ------------------------------------------------
                  // IMAGE
                  // ------------------------------------------------
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(
                      top:
                          Radius.circular(10),
                    ),
                    child: _ProductImage(
                      product: product,
                    ),
                  ),

                  // ------------------------------------------------
                  // WISHLIST HEART
                  // ------------------------------------------------
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white,
                      shape:
                          const CircleBorder(),
                      elevation: 1.5,
                      child: InkWell(
                        onTap:
                            onWishlistTap,
                        customBorder:
                            const CircleBorder(),
                        child: const SizedBox(
                          width: 29,
                          height: 29,
                          child: Icon(
                            Icons.favorite,
                            size: 16,
                            color:
                                AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ------------------------------------------------
                  // RATING
                  // ------------------------------------------------
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),

                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF388E3C,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          4,
                        ),
                      ),

                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Text(
                            product.rating
                                .toStringAsFixed(
                              1,
                            ),
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 9.5,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(
                            width: 2,
                          ),

                          const Icon(
                            Icons.star,
                            color:
                                Colors.white,
                            size: 9,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ======================================================
            // PRODUCT INFO
            // ======================================================
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                7,
                6,
                6,
                6,
              ),

              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.center,

                children: [

                  // ------------------------------------------------
                  // NAME + PRICE
                  // ------------------------------------------------
                  Expanded(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,

                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        Text(
                          product.name,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            fontSize: 10.5,
                            fontWeight:
                                FontWeight.w500,
                            color:
                                AppColors.text,
                          ),
                        ),

                        const SizedBox(
                          height: 3,
                        ),

                        Text(
                          '₹${product.price.toStringAsFixed(0)}',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            fontSize: 14,
                            fontWeight:
                                FontWeight.w800,
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
                    width: 4,
                  ),

                  // ------------------------------------------------
                  // CART BUTTON
                  // ------------------------------------------------
                  Material(
                    color: isInCart
                        ? AppColors.primaryDark
                        : AppColors.primary
                            .withValues(
                            alpha: 0.10,
                          ),

                    borderRadius:
                        BorderRadius.circular(
                      7,
                    ),

                    child: InkWell(
                      onTap:
                          onCartTap,

                      borderRadius:
                          BorderRadius.circular(
                        7,
                      ),

                      child: SizedBox(
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
                              ? Colors.white
                              : AppColors.primary,
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

// ==================================================================
// PRODUCT IMAGE
// ==================================================================

class _ProductImage
    extends StatelessWidget {
  final Product product;

  const _ProductImage({
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    if (product.image
        .trim()
        .isEmpty) {
      return _placeholder();
    }

    // --------------------------------------------------------------
    // NETWORK IMAGE
    // --------------------------------------------------------------
    if (product.isNetworkImage) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.light,
        child: Image.network(
          product.image,
          width: double.infinity,
          height: double.infinity,

          // FIX: `cover` was force-filling the frame and cropping
          // off the top of the photo (the model's face). `contain`
          // shows the full image, anchored to the top so the face
          // is always visible — same as the home page cards.
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,

          errorBuilder:
              (_, __, ___) {
            return _placeholder();
          },

          loadingBuilder: (
            context,
            child,
            loadingProgress,
          ) {
            if (loadingProgress ==
                null) {
              return child;
            }

            return Container(
              color:
                  AppColors.light,
              alignment:
                  Alignment.center,
              child:
                  const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color:
                      AppColors.primary,
                ),
              ),
            );
          },
        ),
      );
    }

    // --------------------------------------------------------------
    // ASSET IMAGE
    // --------------------------------------------------------------
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.light,
      child: Image.asset(
        product.image,
        width: double.infinity,
        height: double.infinity,

        // FIX: same crop issue as the network image branch above —
        // `contain` + top alignment keeps the full photo (face
        // included) visible instead of `cover` cutting it off.
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,

        errorBuilder:
            (_, __, ___) {
          return _placeholder();
        },
      ),
    );
  }

  // ==========================================================
  // IMAGE PLACEHOLDER
  // ==========================================================
  Widget _placeholder() {
    return Container(
      color: AppColors.light,
      alignment: Alignment.center,
      child: const Icon(
        Icons.checkroom,
        size: 30,
        color: AppColors.primary,
      ),
    );
  }
}