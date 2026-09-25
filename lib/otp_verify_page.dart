import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

class OtpVerifyPage extends StatefulWidget {
  final String phoneNumber;
  final String reqId;
  final VoidCallback onVerified;

  const OtpVerifyPage({
    super.key,
    required this.phoneNumber,
    required this.reqId,
    required this.onVerified,
  });

  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage>
    with TickerProviderStateMixin {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? errorText;
  bool isVerifying = false;
  bool isVerified = false;

  late AnimationController _mainAnimationController;
  late AnimationController _scissorController;
  late AnimationController _glowController;
  late AnimationController _particleController;
  late AnimationController _successController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ------------------------------------------------------------
  // SUMATHI STYLES COLORS
  // ------------------------------------------------------------

  static const Color background = Color(0xFF061312);
  static const Color cardColor = Color(0xFF0F1D1C);
  static const Color teal = Color(0xFF18C7B7);
  static const Color gold = Color(0xFFFFC44D);
  static const Color cream = Color(0xFFF7F3EA);
  static const Color greyText = Color(0xFFA9B8B6);

  // ------------------------------------------------------------
  // LOGO ASSET PATH
  // ------------------------------------------------------------
  static const String logoAsset = 'assets/images/app.png';

  @override
  void initState() {
    super.initState();

    // ----------------------------------------------------------
    // MAIN PAGE ANIMATION
    // ----------------------------------------------------------

    _mainAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _mainAnimationController,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // ----------------------------------------------------------
    // SCISSOR ANIMATION
    // ----------------------------------------------------------

    _scissorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // ----------------------------------------------------------
    // GOLD GLOW
    // ----------------------------------------------------------

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // ----------------------------------------------------------
    // BACKGROUND PARTICLES
    // ----------------------------------------------------------

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();

    // ----------------------------------------------------------
    // SUCCESS ANIMATION
    // ----------------------------------------------------------

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _mainAnimationController.forward();

    // Demo OTP popup removed — real SMS is sent by MSG91 now.
  }

  // ------------------------------------------------------------
  // VERIFY OTP
  // ------------------------------------------------------------

  Future<void> _verifyOtp() async {
    if (isVerifying) return;

    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() {
        errorText = "Please enter the 6-digit OTP";
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      isVerifying = true;
      errorText = null;
    });

    try {
      final data = {'reqId': widget.reqId, 'otp': otp};
      final response = await OTPWidget.verifyOTP(data);
      debugPrint('verifyOTP response: $response');

      if (!mounted) return;

      if (response != null && response['type'] == 'success') {
        setState(() {
          isVerified = true;
        });

        _successController.forward();

        await Future.delayed(const Duration(milliseconds: 1200));

        if (!mounted) return;

        widget.onVerified();
      } else {
        setState(() {
          errorText = "Incorrect OTP. Please try again.";
        });
      }
    } catch (e) {
      debugPrint('verifyOTP error: $e');
      if (!mounted) return;
      setState(() {
        errorText = "Something went wrong. Please try again.";
      });
    } finally {
      if (mounted) {
        setState(() {
          isVerifying = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // FASHION BACKGROUND
  // ------------------------------------------------------------

  Widget _fashionBackground(Size size) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _scissorController,
            _particleController,
            _glowController,
          ]),
          builder: (context, child) {
            return CustomPaint(
              painter: _FashionBackgroundPainter(
                scissorProgress: _scissorController.value,
                particleProgress: _particleController.value,
                glowProgress: _glowController.value,
              ),
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ROUND LOGO BADGE
  // ------------------------------------------------------------

  Widget _logoBadge({double size = 84}) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          height: size,
          width: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cardColor,
            border: Border.all(
              color: gold.withValues(
                alpha: 0.45 + (_glowController.value * 0.25),
              ),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: teal.withValues(
                  alpha: 0.10 + (_glowController.value * 0.10),
                ),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              logoAsset,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: cardColor,
                  alignment: Alignment.center,
                  child: Text(
                    "S",
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.bold,
                      fontSize: size * 0.42,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // OTP BOXES
  // ------------------------------------------------------------

  Widget _otpBoxes() {
    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
      },
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          return Stack(
            children: [
              SizedBox(
                height: 1,
                width: 1,
                child: TextField(
                  controller: _otpController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: false,
                  style: const TextStyle(
                    color: Colors.transparent,
                  ),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setState(() {
                        errorText = null;
                      });
                    }

                    setState(() {});
                  },
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) {
                    final text = _otpController.text;
                    final filled = index < text.length;

                    final active =
                        index == text.length &&
                        _focusNode.hasFocus;

                    final glow = 0.10 +
                        (_glowController.value * 0.12);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 47,
                      height: 58,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: errorText != null
                              ? Colors.redAccent
                              : active
                                  ? gold
                                  : filled
                                      ? gold.withValues(
                                          alpha: 0.45,
                                        )
                                      : const Color(0xFF3D4050),
                          width: active ? 2 : 1,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: teal.withValues(
                                    alpha: glow,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                ),
                              ]
                            : filled
                                ? [
                                    BoxShadow(
                                      color: gold.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(
                            milliseconds: 180,
                          ),
                          child: filled
                              ? const Text(
                                  "●",
                                  key: ValueKey("filled"),
                                  style: TextStyle(
                                    color: gold,
                                    fontSize: 17,
                                  ),
                                )
                              : const SizedBox(
                                  key: ValueKey("empty"),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------
  // VERIFY BUTTON
  // ------------------------------------------------------------

  Widget _verifyButton() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: isVerifying ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              disabledBackgroundColor: gold.withValues(
                alpha: 0.55,
              ),
              elevation: 4,
              shadowColor: teal.withValues(
                alpha: 0.14 + (_glowController.value * 0.18),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: isVerifying
                ? const SizedBox(
                    height: 23,
                    width: 23,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: background,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "VERIFY",
                        style: TextStyle(
                          color: background,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedBuilder(
                        animation: _scissorController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              math.sin(
                                    _scissorController.value *
                                        math.pi *
                                        2,
                                  ) *
                                  4,
                              0,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: background,
                              size: 24,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // SUCCESS VIEW
  // ------------------------------------------------------------

  Widget _successView() {
    return AnimatedBuilder(
      animation: _successController,
      builder: (context, child) {
        final scale = Curves.elasticOut.transform(
          _successController.value,
        );

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  height: 115,
                  width: 115,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gold,
                    boxShadow: [
                      BoxShadow(
                        color: gold.withValues(alpha: 0.30),
                        blurRadius: 35,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 68,
                    color: background,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                "OTP Verified!",
                style: TextStyle(
                  color: cream,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Your account has been verified",
                style: TextStyle(
                  color: greyText,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 25),

              _logoBadge(size: 76),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final horizontalPadding =
        size.width < 380 ? 18.0 : 28.0;

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: true,

      body: Stack(
        children: [
          _fashionBackground(size),

          Positioned(
            top: -160,
            right: -130,
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, child) {
                return Container(
                  width: 370,
                  height: 370,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: teal.withValues(
                      alpha:
                          0.025 +
                          (_glowController.value * 0.035),
                    ),
                  ),
                );
              },
            ),
          ),

          Positioned(
            bottom: -190,
            left: -160,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0B2926)
                    .withValues(alpha: 0.88),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: cardColor.withValues(
                              alpha: 0.88,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF30323E),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: cream,
                            size: 19,
                          ),
                        ),
                      ),

                      const Spacer(),

                      const Text(
                        "SUMATHI",
                        style: TextStyle(
                          color: cream,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.5,
                        ),
                      ),

                      const SizedBox(width: 5),

                      const Text(
                        "STYLES",
                        style: TextStyle(
                          color: gold,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.5,
                        ),
                      ),

                      const Spacer(),

                      const SizedBox(width: 44),
                    ],
                  ),
                ),

                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior
                                .onDrag,
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 500,
                          ),
                          child: isVerified
                              ? SizedBox(
                                  height: size.height * 0.78,
                                  child: _successView(),
                                )
                              : Column(
                                  children: [
                                    SizedBox(
                                      height: size.height < 700
                                          ? 25
                                          : 48,
                                    ),

                                    _logoBadge(size: 92),

                                    const SizedBox(height: 18),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 1,
                                            color: teal.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets
                                                  .symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Icon(
                                            Icons
                                                .checkroom_rounded,
                                            color: gold.withValues(
                                              alpha: 0.70,
                                            ),
                                            size: 20,
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 1,
                                            color: teal.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 25),

                                    const Text(
                                      "Verify Your Account",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: cream,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    const Text(
                                      "We've sent a 6-digit OTP to",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: greyText,
                                        fontSize: 15,
                                      ),
                                    ),

                                    const SizedBox(height: 6),

                                    Text(
                                      widget.phoneNumber,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: gold,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),

                                    const SizedBox(height: 35),

                                    const Align(
                                      alignment:
                                          Alignment.centerLeft,
                                      child: Text(
                                        "ENTER 6-DIGIT OTP",
                                        style: TextStyle(
                                          color: greyText,
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    _otpBoxes(),

                                    if (errorText != null) ...[
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment:
                                            Alignment.centerLeft,
                                        child: Text(
                                          errorText!,
                                          style:
                                              const TextStyle(
                                            color:
                                                Colors.redAccent,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 30),

                                    _verifyButton(),

                                    const SizedBox(height: 23),

                                    TextButton(
                                      onPressed: () {
                                        _otpController.clear();

                                        setState(() {
                                          errorText = null;
                                        });

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            backgroundColor:
                                                cardColor,
                                            behavior:
                                                SnackBarBehavior
                                                    .floating,
                                            shape:
                                                RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                14,
                                              ),
                                            ),
                                            content: const Row(
                                              children: [
                                                Icon(
                                                  Icons
                                                      .check_circle_outline,
                                                  color: gold,
                                                ),
                                                SizedBox(width: 10),
                                                Text(
                                                  "OTP sent again",
                                                  style: TextStyle(
                                                    color: cream,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        "Didn't receive the OTP?  Resend",
                                        style: TextStyle(
                                          color: gold,
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w500,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 35),

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons
                                              .content_cut_rounded,
                                          color: teal.withValues(
                                            alpha: 0.65,
                                          ),
                                          size: 14,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          "SUMATHI'S STYLES",
                                          style: TextStyle(
                                            color: greyText,
                                            fontSize: 11,
                                            letterSpacing: 3,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons
                                              .content_cut_rounded,
                                          color: teal.withValues(
                                            alpha: 0.65,
                                          ),
                                          size: 14,
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 8),

                                    const Text(
                                      "Style that speaks for you ♡",
                                      style: TextStyle(
                                        color: greyText,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),

                                    const SizedBox(height: 25),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();

    _mainAnimationController.dispose();
    _scissorController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    _successController.dispose();

    super.dispose();
  }
}

// ================================================================
// FASHION BACKGROUND PAINTER
// ================================================================

class _FashionBackgroundPainter extends CustomPainter {
  final double scissorProgress;
  final double particleProgress;
  final double glowProgress;

  _FashionBackgroundPainter({
    required this.scissorProgress,
    required this.particleProgress,
    required this.glowProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    paint.color = const Color(0xFF0B2220);

    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.34),
      size.width * 0.42,
      paint,
    );

    final dressPaint = Paint()
      ..color = const Color(0xFF102B29).withValues(alpha: 0.62)
      ..style = PaintingStyle.fill;

    final dressPath = Path();

    final cx = size.width * 0.82;
    final top = size.height * 0.24;

    dressPath.moveTo(cx - 12, top);
    dressPath.lineTo(cx - 38, top + 20);
    dressPath.lineTo(cx - 55, top + 45);
    dressPath.lineTo(cx - 25, top + 105);
    dressPath.lineTo(cx - 90, top + 255);

    dressPath.quadraticBezierTo(
      cx,
      top + 290,
      cx + 90,
      top + 255,
    );

    dressPath.lineTo(cx + 25, top + 105);
    dressPath.lineTo(cx + 55, top + 45);
    dressPath.lineTo(cx + 38, top + 20);
    dressPath.lineTo(cx + 12, top);

    dressPath.close();

    canvas.drawPath(dressPath, dressPaint);

    final outlinePaint = Paint()
      ..color = const Color(0xFF18C7B7)
          .withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawPath(dressPath, outlinePaint);

    final cutPaint = Paint()
      ..color = const Color(0xFFFFC44D)
          .withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final cutPath = Path();

    for (int i = 0; i < 6; i++) {
      final x1 = cx - 65 + (i * 22);
      final y = top + 170 + math.sin(i * 1.5) * 4;

      if (i == 0) {
        cutPath.moveTo(x1, y);
      } else {
        cutPath.lineTo(x1, y);
      }
    }

    canvas.drawPath(cutPath, cutPaint);

    final particlePaint = Paint();

    for (int i = 0; i < 22; i++) {
      particlePaint.color = (i % 3 == 0)
          ? const Color(0xFF18C7B7).withValues(alpha: 0.24)
          : const Color(0xFFFFC44D).withValues(alpha: 0.18);
      final baseX =
          (i * 71.0) % size.width;

      final baseY =
          (i * 97.0) % size.height;

      final movement =
          math.sin(
                particleProgress * math.pi * 2 +
                    i,
              ) *
              12;

      final y =
          (baseY +
                  particleProgress * size.height +
                  movement) %
              size.height;

      final radius = 1.0 + (i % 3) * 0.5;

      canvas.drawCircle(
        Offset(baseX, y),
        radius,
        particlePaint,
      );
    }

    final scissorPaint = Paint()
      ..color = const Color(0xFF18C7B7)
          .withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final sx =
        size.width * 0.16 +
        math.sin(
              scissorProgress * math.pi * 2,
            ) *
            8;

    final sy = size.height * 0.70;

    canvas.drawCircle(
      Offset(sx - 8, sy),
      8,
      scissorPaint,
    );

    canvas.drawCircle(
      Offset(sx + 8, sy),
      8,
      scissorPaint,
    );

    canvas.drawLine(
      Offset(sx - 2, sy - 2),
      Offset(sx + 30, sy - 24),
      scissorPaint,
    );

    canvas.drawLine(
      Offset(sx + 2, sy + 2),
      Offset(sx + 30, sy + 24),
      scissorPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _FashionBackgroundPainter oldDelegate,
  ) {
    return oldDelegate.scissorProgress !=
            scissorProgress ||
        oldDelegate.particleProgress !=
            particleProgress ||
        oldDelegate.glowProgress != glowProgress;
  }
}