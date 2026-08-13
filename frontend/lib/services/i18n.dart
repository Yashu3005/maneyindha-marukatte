import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const languages = {'en': 'English', 'kn': 'ಕನ್ನಡ', 'hi': 'हिंदी', 'ta': 'தமிழ்'};

const Map<String, Map<String, String>> _tr = {
  'en': {
    'home': 'Home', 'orders': 'Orders', 'cart': 'Cart', 'profile': 'Profile',
    'community': 'Community', 'wishlist': 'Wishlist',
    'namaste': 'Namaste', 'discover': 'Discover home-made treasures near you',
    'search_hint': 'Search cakes, crafts, tiffins…', 'categories': 'Categories',
    'all_shops': 'All shops', 'near_you': 'Shops near you', 'near_me': 'Near me',
    'popular': 'Popular products', 'coins': 'My coins', 'language': 'Language',
    'personal': 'Personal details', 'address_book': 'Address book',
    'become_seller': 'Become an Entrepreneur', 'help': 'Help & Support', 'logout': 'Logout',
    'coming_soon': 'We are spreading to your area soon 🌸\nKindly check back!',
    'notifications': 'Notifications', 'share_update': 'Share an update',
  },
  'kn': {
    'home': 'ಮುಖಪುಟ', 'orders': 'ಆರ್ಡರ್‌ಗಳು', 'cart': 'ಬುಟ್ಟಿ', 'profile': 'ಪ್ರೊಫೈಲ್',
    'community': 'ಸಮುದಾಯ', 'wishlist': 'ಇಷ್ಟಪಟ್ಟಿ',
    'namaste': 'ನಮಸ್ಕಾರ', 'discover': 'ನಿಮ್ಮ ಹತ್ತಿರದ ಮನೆ ತಯಾರಿಕೆಯ ನಿಧಿಗಳು',
    'search_hint': 'ಕೇಕ್, ಕರಕುಶಲ, ಟಿಫಿನ್ ಹುಡುಕಿ…', 'categories': 'ವರ್ಗಗಳು',
    'all_shops': 'ಎಲ್ಲಾ ಅಂಗಡಿಗಳು', 'near_you': 'ನಿಮ್ಮ ಹತ್ತಿರದ ಅಂಗಡಿಗಳು', 'near_me': 'ನನ್ನ ಹತ್ತಿರ',
    'popular': 'ಜನಪ್ರಿಯ ಉತ್ಪನ್ನಗಳು', 'coins': 'ನನ್ನ ನಾಣ್ಯಗಳು', 'language': 'ಭಾಷೆ',
    'personal': 'ವೈಯಕ್ತಿಕ ವಿವರಗಳು', 'address_book': 'ವಿಳಾಸ ಪುಸ್ತಕ',
    'become_seller': 'ಉದ್ಯಮಿಯಾಗಿ', 'help': 'ಸಹಾಯ', 'logout': 'ಲಾಗ್ ಔಟ್',
    'coming_soon': 'ನಾವು ಶೀಘ್ರದಲ್ಲೇ ನಿಮ್ಮ ಪ್ರದೇಶಕ್ಕೆ ಬರುತ್ತೇವೆ 🌸',
    'notifications': 'ಅಧಿಸೂಚನೆಗಳು', 'share_update': 'ನವೀಕರಣ ಹಂಚಿಕೊಳ್ಳಿ',
  },
  'hi': {
    'home': 'होम', 'orders': 'ऑर्डर', 'cart': 'कार्ट', 'profile': 'प्रोफ़ाइल',
    'community': 'समुदाय', 'wishlist': 'पसंद',
    'namaste': 'नमस्ते', 'discover': 'अपने पास के घर के बने खज़ाने खोजें',
    'search_hint': 'केक, शिल्प, टिफिन खोजें…', 'categories': 'श्रेणियाँ',
    'all_shops': 'सभी दुकानें', 'near_you': 'आपके पास की दुकानें', 'near_me': 'मेरे पास',
    'popular': 'लोकप्रिय उत्पाद', 'coins': 'मेरे सिक्के', 'language': 'भाषा',
    'personal': 'व्यक्तिगत विवरण', 'address_book': 'पता पुस्तिका',
    'become_seller': 'उद्यमी बनें', 'help': 'सहायता', 'logout': 'लॉग आउट',
    'coming_soon': 'हम जल्द ही आपके क्षेत्र में आ रहे हैं 🌸',
    'notifications': 'सूचनाएँ', 'share_update': 'अपडेट साझा करें',
  },
  'ta': {
    'home': 'முகப்பு', 'orders': 'ஆர்டர்கள்', 'cart': 'கூடை', 'profile': 'சுயவிவரம்',
    'community': 'சமூகம்', 'wishlist': 'விருப்பம்',
    'namaste': 'வணக்கம்', 'discover': 'உங்கள் அருகிலுள்ள வீட்டுத் தயாரிப்புகள்',
    'search_hint': 'கேக், கைவினை, டிபன் தேடுங்கள்…', 'categories': 'வகைகள்',
    'all_shops': 'அனைத்து கடைகள்', 'near_you': 'உங்கள் அருகிலுள்ள கடைகள்', 'near_me': 'என் அருகில்',
    'popular': 'பிரபல பொருட்கள்', 'coins': 'என் நாணயங்கள்', 'language': 'மொழி',
    'personal': 'தனிப்பட்ட விவரங்கள்', 'address_book': 'முகவரி புத்தகம்',
    'become_seller': 'தொழில்முனைவராகுங்கள்', 'help': 'உதவி', 'logout': 'வெளியேறு',
    'coming_soon': 'விரைவில் உங்கள் பகுதிக்கு வருகிறோம் 🌸',
    'notifications': 'அறிவிப்புகள்', 'share_update': 'புதுப்பிப்பு பகிர்',
  },
};

class LocaleNotifier extends StateNotifier<String> {
  LocaleNotifier() : super('en') { _restore(); }
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('lang') ?? 'en';
  }
  Future<void> set(String lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', lang);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, String>((ref) => LocaleNotifier());

String t(WidgetRef ref, String key) {
  final lang = ref.watch(localeProvider);
  return _tr[lang]?[key] ?? _tr['en']![key] ?? key;
}
