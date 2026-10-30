import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/customer/customer_shell.dart';
import '../features/seller/seller_onboarding.dart';
import '../features/seller/seller_shell.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/businesses/business_screen.dart';
import '../features/products/product_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/admin_login_screen.dart';
import '../features/rewards/rewards_screen.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/notifications/notifications_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const LandingScreen()),
      GoRoute(path: '/onboarding/email', builder: (_, __) => const EmailScreen()),
      GoRoute(
        path: '/onboarding/otp',
        builder: (_, s) {
          final extra = (s.extra as Map?) ?? {};
          return OtpScreen(
            email: extra['email']?.toString() ?? '',
            resendAfter: (extra['resendAfter'] as num?)?.toInt() ?? 60,
          );
        },
      ),
      GoRoute(path: '/onboarding/profile', builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/onboarding/role', builder: (_, __) => const RoleScreen()),
      GoRoute(path: '/onboarding/success', builder: (_, __) => const CustomerSuccessScreen()),
      GoRoute(path: '/app', builder: (_, __) => const CustomerShell()),
      GoRoute(path: '/seller', builder: (_, __) => const SellerShell()),
      GoRoute(path: '/seller/onboarding/business', builder: (_, __) => const BusinessInfoScreen()),
      GoRoute(path: '/seller/onboarding/documents', builder: (_, __) => const DocumentsScreen()),
      GoRoute(path: '/seller/onboarding/review', builder: (_, __) => const ReviewDetailsScreen()),
      GoRoute(path: '/seller/onboarding/submitted', builder: (_, __) => const SubmittedScreen()),
      GoRoute(path: '/seller/onboarding/status', builder: (_, __) => const ApplicationStatusScreen()),
      GoRoute(path: '/seller/onboarding/credentials', builder: (_, __) => const CredentialsScreen()),
      GoRoute(path: '/seller/onboarding/security', builder: (_, __) => const SecurityQuestionsScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/business/:id', builder: (_, s) => BusinessScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen()),
      GoRoute(path: '/rewards', builder: (_, __) => const RewardsScreen()),
      GoRoute(path: '/assistant', builder: (_, __) => const AssistantScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/admin/login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
    ],
  );
});
