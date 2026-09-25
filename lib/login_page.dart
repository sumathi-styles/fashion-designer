import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';
import 'main_nav_page.dart';
import 'otp_verify_page.dart';
import 'app_state.dart';
import 'admin_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final mobileController = TextEditingController();

  final Color teal = const Color(0xff0F766E);
  final Color lightTeal = const Color(0xff4FC3B0);
  final Color gold = const Color(0xffD4AF37);

  bool isSendingOtp = false;

  // India only
  static const String _countryCode = '+91';
  static const int _mobileLength = 10;

  Future<void> _completeLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);

    final name = nameController.text.trim();
    final mobile = mobileController.text.trim();
    await prefs.setString('userName', name);
    await prefs.setString('userMobile', mobile);
    await prefs.setString('userCountryCode', _countryCode);

    // Same id as before (10 digits)
    AppState.instance.login(userId: mobile, userName: name);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainNavPage()),
      (route) => false,
    );
  }

  Future<void> _startLogin() async {
    if (!_formKey.currentState!.validate()) return;
    if (isSendingOtp) return;

    setState(() {
      isSendingOtp = true;
    });

    final mobile = mobileController.text.trim();
    final data = {'identifier': '91$mobile'};

    try {
      final response = await OTPWidget.sendOTP(data);
      debugPrint('sendOTP response: $response');

      if (!mounted) return;

      if (response != null && response['type'] == 'success') {
        final reqId = response['message'];

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerifyPage(
              phoneNumber: '$_countryCode ${mobile}',
              reqId: reqId,
              onVerified: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Login Successful"),
                    backgroundColor: Colors.green,
                  ),
                );
                _completeLogin();
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to send OTP. Please try again."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('sendOTP error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Something went wrong. Please try again."),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSendingOtp = false;
        });
      }
    }
  }

  void _continueAsGuest() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainNavPage()),
      (route) => false,
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? prefixIcon,
    BoxConstraints? prefixIconConstraints,
  }) {
    return InputDecoration(
      counterText: "",
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIconConstraints,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70, fontSize: 15),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      enabledBorder: _border(Colors.white.withValues(alpha: 0.30)),
      focusedBorder: _border(lightTeal, width: 2),
      errorBorder: _border(Colors.redAccent),
      focusedErrorBorder: _border(Colors.redAccent, width: 2),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }

  /// Fixed India prefix (no dropdown)
  Widget _indiaPrefix() {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🇮🇳 $_countryCode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 1,
            height: 24,
            color: Colors.white.withValues(alpha: 0.30),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/lgn_bg.png",
              fit: BoxFit.cover,
            ),
          ),

          // Light overlay only for text readability
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
              ),
            ),
          ),

          // Admin-access icon -> opens Admin Dashboard (kept faint on purpose)
          Positioned(
            top: 40,
            right: 16,
            child: SafeArea(
              child: Opacity(
                opacity: 0.25,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminPage()),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ---------- LOGO (circle, no extra box/padding) ----------
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            "assets/images/cir.png",
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.white,
                              child: Icon(Icons.checkroom, color: teal, size: 40),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ---------- BRAND NAME ----------
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "SUMATHI'S",
                            style: TextStyle(
                              color: lightTeal,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "STYLES",
                            style: TextStyle(
                              color: gold,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // ---------- TAGLINE ----------
                      const Text(
                        "Fashion Designing Boutique",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ---------- LOGIN CONTAINER ----------
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "Customer Login",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Enter your details to continue",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Full Name
                              TextFormField(
                                controller: nameController,
                                keyboardType: TextInputType.name,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z ]')),
                                ],
                                style: const TextStyle(color: Colors.white),
                                decoration: _fieldDecoration(
                                  hint: "Full Name",
                                  prefixIcon: Icon(Icons.person_outline,
                                      color: gold),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Please enter your name";
                                  }
                                  if (!RegExp(r'^[a-zA-Z ]+$')
                                      .hasMatch(value.trim())) {
                                    return "Only alphabets are allowed";
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              // Mobile Number (India +91 fixed)
                              TextFormField(
                                controller: mobileController,
                                keyboardType: TextInputType.phone,
                                maxLength: _mobileLength,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                style: const TextStyle(color: Colors.white),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: _fieldDecoration(
                                  hint: "Mobile Number",
                                  prefixIcon: _indiaPrefix(),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 0,
                                    minHeight: 0,
                                  ),
                                ),
                                validator: (value) {
                                  final v = value?.trim() ?? '';
                                  if (v.isEmpty) {
                                    return "Please enter your Mobile Number";
                                  }
                                  if (v.length != _mobileLength) {
                                    return "Enter a valid $_mobileLength-digit mobile number";
                                  }
                                  // Indian mobile numbers start with 6-9
                                  if (!RegExp(r'^[6-9]').hasMatch(v)) {
                                    return "Indian mobile numbers start with 6, 7, 8 or 9";
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 8),

                              // Hint below the mobile field
                              Row(
                                children: const [
                                  Icon(Icons.info_outline,
                                      size: 16, color: Colors.white70),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Enter a valid 10-digit Indian mobile number",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

                              // LOGIN button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: lightTeal,
                                  foregroundColor: Colors.white,
                                  overlayColor: gold.withValues(alpha: 0.35),
                                  elevation: 4,
                                  shadowColor: teal.withValues(alpha: 0.6),
                                  minimumSize: const Size(double.infinity, 52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: isSendingOtp ? null : _startLogin,
                                icon: isSendingOtp
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.sms_outlined),
                                label: Text(
                                  isSendingOtp ? "SENDING OTP..." : "LOGIN",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ---------- WELCOME TEXT ----------
                      const Text(
                        "Welcome to Sumathi's Styles ✨",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      TextButton(
                        onPressed: _continueAsGuest,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: "Continue as ",
                                style: TextStyle(
                                  color: lightTeal,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              TextSpan(
                                text: "Guest",
                                style: TextStyle(
                                  color: gold,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    super.dispose();
  }
}