import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:confetti/confetti.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('Notifications error: $e');
  }
  try {
    tz.initializeTimeZones();
  } catch (e) {
    debugPrint('Timezone error: $e');
  }
  runApp(const SmartShelfApp());
}

// ==================== СЕРВИС УВЕДОМЛЕНИЙ ====================
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(settings);
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  Future<void> scheduleExpiryNotification(Product product) async {
    final expiryDate = product.expiryDate;
    final notifyDate = expiryDate.subtract(const Duration(days: 1));
    
    if (notifyDate.isBefore(DateTime.now())) return;

    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(notifyDate, tz.local);

    await _notifications.zonedSchedule(
      product.id.hashCode,
      'Срок годности истекает!',
      '${product.name} испортится завтра',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_channel',
          'Сроки годности',
          channelDescription: 'Уведомления о скором испорченности продуктов',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelNotification(String productId) async {
    await _notifications.cancel(productId.hashCode);
  }
}

// ==================== ТЕМЫ И СТИЛИ ====================
class AppTheme {
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF14B8A6);
  static const Color accent = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF97316);
  static const Color info = Color(0xFF3B82F6);
  
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkSurface = Color(0xFF334155);
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Colors.white;
  static const Color lightSurface = Color(0xFFE2E8F0);

  static ThemeData getTheme(bool isDark) {
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: isDark ? darkBg : lightBg,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: primary,
        secondary: secondary,
        surface: isDark ? darkCard : lightCard,
        error: danger,
        onSurface: isDark ? Colors.white : const Color(0xFF1E293B),
      ),
      cardTheme: CardTheme(
        color: isDark ? darkCard : lightCard,
        elevation: isDark ? 0 : 4,
        shadowColor: isDark ? Colors.transparent : Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkCard : lightCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: isDark ? darkCard : lightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
    );
  }
}

// ==================== МОДЕЛИ ДАННЫХ ====================
class Product {
  final String id;
  String name;
  DateTime expiryDate;
  final String category;
  final String iconName;
  final DateTime addedDate;
  bool isUsed;
  String? barcode;
  String? notes;
  int quantity;

  Product({
    required this.id,
    required this.name,
    required this.expiryDate,
    required this.category,
    required this.iconName,
    required this.addedDate,
    this.isUsed = false,
    this.barcode,
    this.notes,
    this.quantity = 1,
  });

  int get daysLeft => expiryDate.difference(DateTime.now()).inDays;
  bool get isExpired => daysLeft < 0;
  bool get isExpiringToday => daysLeft == 0;
  bool get isExpiringSoon => daysLeft > 0 && daysLeft <= 3;
  bool get isExpiringThisWeek => daysLeft > 3 && daysLeft <= 7;
  bool get isFresh => daysLeft > 7;

  Color get statusColor {
    if (isExpired || isExpiringToday) return AppTheme.danger;
    if (isExpiringSoon) return AppTheme.warning;
    if (isExpiringThisWeek) return AppTheme.accent;
    return AppTheme.success;
  }

  String get statusText {
    if (isExpired) return daysLeft == -1 ? "Просрочен вчера" : "Просрочен ${daysLeft.abs()} дн.";
    if (isExpiringToday) return "Истекает сегодня!";
    if (daysLeft == 1) return "Истекает завтра";
    if (daysLeft == 2) return "Истекает послезавтра";
    if (isExpiringSoon) return "Истекает через $daysLeft дн.";
    if (isExpiringThisWeek) return "Истекает через $daysLeft дн.";
    return "Свежий продукт";
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'expiryDate': expiryDate.toIso8601String(),
    'category': category,
    'iconName': iconName,
    'addedDate': addedDate.toIso8601String(),
    'isUsed': isUsed,
    'barcode': barcode,
    'notes': notes,
    'quantity': quantity,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'],
    name: json['name'],
    expiryDate: DateTime.parse(json['expiryDate']),
    category: json['category'],
    iconName: json['iconName'],
    addedDate: DateTime.parse(json['addedDate']),
    isUsed: json['isUsed'] ?? false,
    barcode: json['barcode'],
    notes: json['notes'],
    quantity: json['quantity'] ?? 1,
  );

  Product copyWith({
    String? id,
    String? name,
    DateTime? expiryDate,
    String? category,
    String? iconName,
    DateTime? addedDate,
    bool? isUsed,
    String? barcode,
    String? notes,
    int? quantity,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    expiryDate: expiryDate ?? this.expiryDate,
    category: category ?? this.category,
    iconName: iconName ?? this.iconName,
    addedDate: addedDate ?? this.addedDate,
    isUsed: isUsed ?? this.isUsed,
    barcode: barcode ?? this.barcode,
    notes: notes ?? this.notes,
    quantity: quantity ?? this.quantity,
  );
}

class ProductCategory {
  final String name;
  final IconData icon;
  final Color color;
  final int defaultDays;

  ProductCategory(this.name, this.icon, this.color, this.defaultDays);
}

// ==================== КАТЕГОРИИ ====================
final Map<String, ProductCategory> categories = {
  'Молочка': ProductCategory('Молочка', Icons.local_drink, Color(0xFF60A5FA), 7),
  'Мясо': ProductCategory('Мясо', Icons.restaurant, Color(0xFFEF4444), 3),
  'Рыба': ProductCategory('Рыба', Icons.set_meal, Color(0xFF06B6D4), 2),
  'Яйца': ProductCategory('Яйца', Icons.egg, Color(0xFFFCD34D), 21),
  'Хлеб': ProductCategory('Хлеб', Icons.bakery_dining, Color(0xFFD97706), 3),
  'Фрукты': ProductCategory('Фрукты', Icons.apple, Color(0xFF22C55E), 14),
  'Овощи': ProductCategory('Овощи', Icons.eco, Color(0xFF10B981), 21),
  'Грибы': ProductCategory('Грибы', Icons.forest, Color(0xFF8B5CF6), 5),
  'Сладости': ProductCategory('Сладости', Icons.cake, Color(0xFFF472B6), 180),
  'Напитки': ProductCategory('Напитки', Icons.local_cafe, Color(0xFF3B82F6), 30),
  'Алкоголь': ProductCategory('Алкоголь', Icons.wine_bar, Color(0xFF7C3AED), 365),
  'Консервы': ProductCategory('Консервы', Icons.inventory_2, Color(0xFF6B7280), 730),
  'Крупы': ProductCategory('Крупы', Icons.grain, Color(0xFFF59E0B), 365),
  'Соусы': ProductCategory('Соусы', Icons.local_dining, Color(0xFFEC4899), 90),
  'Масла': ProductCategory('Масла', Icons.opacity, Color(0xFFFBBF24), 365),
  'Детское': ProductCategory('Детское', Icons.child_care, Color(0xFF8B5CF6), 180),
  'Другое': ProductCategory('Другое', Icons.kitchen, Color(0xFF9CA3AF), 7),
};

// ==================== СЕРВИС ДАННЫХ ====================
class ProductService {
  static const String _key = 'products_v2';
  static const String _firstLaunchKey = 'first_launch_completed';
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  List<Product> _products = [];
  List<Product> get products => List.unmodifiable(_products);

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_firstLaunchKey) ?? false);
  }

  Future<void> setFirstLaunchComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, true);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        _products = list.map((e) => Product.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading products: $e');
        _products = [];
      }
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_products.map((e) => e.toJson()).toList());
    await prefs.setString(_key, data);
  }

  Future<void> add(Product product) async {
    _products.add(product);
    await save();
    await NotificationService().scheduleExpiryNotification(product);
  }

  Future<void> addMultiple(List<Product> products) async {
    _products.addAll(products);
    await save();
    for (var p in products) {
      await NotificationService().scheduleExpiryNotification(p);
    }
  }

  Future<void> update(Product product) async {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _products[index] = product;
      await save();
      await NotificationService().cancelNotification(product.id);
      await NotificationService().scheduleExpiryNotification(product);
    }
  }

  Future<void> delete(String id) async {
    _products.removeWhere((p) => p.id == id);
    await save();
    await NotificationService().cancelNotification(id);
  }

  Future<void> toggleUsed(String id) async {
    final product = _products.firstWhere((p) => p.id == id);
    product.isUsed = !product.isUsed;
    await save();
    if (product.isUsed) {
      await NotificationService().cancelNotification(id);
    } else {
      await NotificationService().scheduleExpiryNotification(product);
    }
  }

  Future<void> clearAll() async {
    for (var p in _products) {
      await NotificationService().cancelNotification(p.id);
    }
    _products.clear();
    await save();
  }

  List<Product> get sortedProducts {
    final list = List<Product>.from(_products);
    list.sort((a, b) {
      if (a.isUsed != b.isUsed) return a.isUsed ? 1 : -1;
      if (a.isExpired != b.isExpired) return a.isExpired ? 1 : -1;
      return a.expiryDate.compareTo(b.expiryDate);
    });
    return list;
  }

  List<Product> search(String query) {
    if (query.isEmpty) return sortedProducts;
    return sortedProducts.where((p) => 
      p.name.toLowerCase().contains(query.toLowerCase()) ||
      p.category.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  List<Product> filterByCategory(String category) {
    if (category == 'Все') return sortedProducts;
    return sortedProducts.where((p) => p.category == category).toList();
  }

  Map<String, dynamic> getStats() {
    final total = _products.length;
    final expired = _products.where((p) => p.isExpired && !p.isUsed).length;
    final expiringSoon = _products.where((p) => p.isExpiringSoon && !p.isUsed).length;
    final fresh = _products.where((p) => p.isFresh && !p.isUsed).length;
    final used = _products.where((p) => p.isUsed).length;
    
    return {
      'total': total,
      'expired': expired,
      'expiringSoon': expiringSoon,
      'fresh': fresh,
      'used': used,
    };
  }

  Future<String> exportToJson() async {
    return jsonEncode(_products.map((e) => e.toJson()).toList());
  }

  Future<void> importFromJson(String json) async {
    final list = jsonDecode(json) as List;
    _products = list.map((e) => Product.fromJson(e)).toList();
    await save();
    for (var p in _products) {
      await NotificationService().scheduleExpiryNotification(p);
    }
  }
}

// ==================== ПАРСЕР ЧЕСТНОГО ЗНАКА ====================
class HonestSignParser {
  // Парсит Data Matrix код Честного ЗНАКА
  // Формат: GS1 Data Matrix с идентификаторами применения
  static DateTime? parseExpiryDate(String barcode) {
    try {
      // Ищем AI (01) - GTIN и (17) - срок годности YYMMDD
      // Пример: 01046012345678902123456717250331...
      // 01 = GTIN (14 цифр)
      // 17 = Срок годности YYMMDD (6 цифр)
      
      String? expiryStr;
      
      // Ищем маркер 17 (срок годности)
      final expIndex = barcode.indexOf('17');
      if (expIndex != -1 && expIndex + 8 <= barcode.length) {
        expiryStr = barcode.substring(expIndex + 2, expIndex + 8);
      }
      
      // Альтернативный формат: просто 6 цифр подряд после GTIN
      if (expiryStr == null && barcode.length >= 20) {
        // Пробуем найти дату в формате YYMMDD
        final datePattern = RegExp(r'(20\d{2})(\d{2})(\d{2})');
        final match = datePattern.firstMatch(barcode);
        if (match != null) {
          final year = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          final day = int.parse(match.group(3)!);
          return DateTime(year, month, day);
        }
      }
      
      if (expiryStr != null && expiryStr.length == 6) {
        final year = 2000 + int.parse(expiryStr.substring(0, 2));
        final month = int.parse(expiryStr.substring(2, 4));
        final day = int.parse(expiryStr.substring(4, 6));
        return DateTime(year, month, day);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error parsing Honest Sign: $e');
      return null;
    }
  }
  
  static String? extractProductName(String barcode) {
    // Пытаемся извлечь название из базы или возвращаем null
    return null;
  }
}

// ==================== БАЗА ПРОДУКТОВ ====================
class ProductDatabase {
  static Map<String, dynamic>? _data;

  static Future<void> load() async {
    try {
      final jsonString = await rootBundle.loadString('assets/products_db.json');
      _data = jsonDecode(jsonString);
    } catch (e) {
      debugPrint('Error loading product database: $e');
      _data = {'products': []};
    }
  }

  static Map<String, dynamic>? findByBarcode(String barcode) {
    if (_data == null) return null;
    final products = _data!['products'] as List;
    try {
      return products.firstWhere((p) => p['barcode'] == barcode);
    } catch (e) {
      return null;
    }
  }

  static List<Map<String, dynamic>> search(String query) {
    if (_data == null) return [];
    final products = _data!['products'] as List;
    return products.where((p) => 
      p['name'].toString().toLowerCase().contains(query.toLowerCase())
    ).cast<Map<String, dynamic>>().toList();
  }
}

// ==================== ГЛАВНОЕ ПРИЛОЖЕНИЕ ====================
class SmartShelfApp extends StatefulWidget {
  const SmartShelfApp({super.key});

  @override
  State<SmartShelfApp> createState() => _SmartShelfAppState();
}

class _SmartShelfAppState extends State<SmartShelfApp> {
  bool isDark = true;
  bool isLoading = true;
  bool isFirstLaunch = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ProductDatabase.load();
    await ProductService().load();
    final prefs = await SharedPreferences.getInstance();
    isFirstLaunch = await ProductService().isFirstLaunch();
    setState(() {
      isDark = prefs.getBool('isDark') ?? true;
      isLoading = false;
    });
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => isDark = !isDark);
    await prefs.setBool('isDark', isDark);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      );
    }

    return AnimatedTheme(
      data: AppTheme.getTheme(isDark),
      duration: const Duration(milliseconds: 400),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.getTheme(isDark),
        home: isFirstLaunch 
          ? OnboardingScreen(
              onThemeToggle: toggleTheme,
              isDark: isDark,
              onComplete: () async {
                await ProductService().setFirstLaunchComplete();
                setState(() => isFirstLaunch = false);
              },
            )
          : HomeScreen(
              onThemeToggle: toggleTheme,
              isDark: isDark,
            ),
      ),
    );
  }
}

// ==================== ОНБОРДИНГ (ТОЛЬКО ПЕРВЫЙ РАЗ) ====================
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDark;
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDark,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final PageController _pageCtrl = PageController();
  int _page = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'СмартПолка',
      'subtitle': 'Умный трекер сроков годности',
      'icon': Icons.kitchen,
    },
    {
      'title': 'Следи за сроками',
      'subtitle': 'Никаких просроченных продуктов',
      'icon': Icons.timer,
    },
    {
      'title': 'Сканируй Честный ЗНАК',
      'subtitle': 'Точный срок из Data Matrix',
      'icon': Icons.qr_code_scanner,
    },
    {
      'title': 'Голосовой ввод',
      'subtitle': 'Скажи "Молоко 5 дней, Хлеб 3 дня"',
      'icon': Icons.mic,
    },
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                : [const Color(0xFFEEF2FF), const Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Минималистичный холодильник вместо Фриджи
              _buildFridge(),
              const SizedBox(height: 40),
              SizedBox(
                height: 200,
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _pages.length,
                  itemBuilder: (ctx, i) => _buildPage(i),
                ),
              ),
              const Spacer(),
              _buildIndicators(),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 8,
                      shadowColor: AppTheme.primary.withOpacity(0.4),
                    ),
                    child: Text(
                      _page == _pages.length - 1 ? 'НАЧАТЬ' : 'ДАЛЕЕ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFridge() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, child) {
        final bounce = math.sin(_ctrl.value * math.pi * 2) * 0.05 + 1.0;
        return Transform.scale(
          scale: bounce,
          child: Container(
            width: 140,
            height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey.shade300,
                  Colors.grey.shade400,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade500, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Верхняя дверь (морозилка)
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade500, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // Нижняя дверь (холодильник)
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade500, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(int index) {
    final page = _pages[index];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            page['icon'] as IconData,
            size: 40,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          page['title'] as String,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          page['subtitle'] as String,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _pages.length,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _page == i ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _page == i ? AppTheme.primary : Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }
}

// ==================== ГЛАВНЫЙ ЭКРАН ====================
class HomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDark;

  const HomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.isDark,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final ProductService _service = ProductService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late ConfettiController _confettiCtrl;

  List<Product> _filtered = [];
  String _selectedCategory = 'Все';
  String _searchQuery = '';
  bool _showFab = true;
  double _lastScroll = 0;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 3));
    _scrollCtrl.addListener(_onScroll);
    _loadProducts();
  }

  void _onScroll() {
    final current = _scrollCtrl.offset;
    if (current > _lastScroll && current > 100 && _showFab) {
      setState(() => _showFab = false);
    } else if (current < _lastScroll && !_showFab) {
      setState(() => _showFab = true);
    }
    _lastScroll = current;
  }

  void _loadProducts() {
    setState(() {
      _filtered = _service.sortedProducts;
    });
  }

  void _filterProducts() {
    var list = _service.sortedProducts;
    if (_selectedCategory != 'Все') {
      list = list.where((p) => p.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((p) => 
        p.name.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    setState(() => _filtered = list);
  }

  Future<void> _deleteProduct(String id) async {
    await _service.delete(id);
    _filterProducts();
    _showSnack('Продукт удален', AppTheme.danger);
  }

  Future<void> _toggleUsed(Product product) async {
    await _service.toggleUsed(product.id);
    if (!product.isUsed) {
      _confettiCtrl.play();
      _showSnack('Отлично! Продукт использован', AppTheme.success);
    }
    _filterProducts();
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppTheme.success ? Icons.check_circle : Icons.info,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            const SizedBox(height: 20),
            const Text(
              'Добавить продукт',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 28),
            _buildAddOption(
              Icons.mic,
              'Голосом',
              'Скажи: "Молоко 5 дней, Хлеб 3 дня"',
              AppTheme.warning,
              () {
                Navigator.pop(ctx);
                _showVoiceInput();
              },
            ),
            _buildAddOption(
              Icons.qr_code_scanner,
              'Честный ЗНАК',
              'Сканировать Data Matrix',
              AppTheme.accent,
              () {
                Navigator.pop(ctx);
                _showHonestSignScanner();
              },
            ),
            _buildAddOption(
              Icons.edit,
              'Вручную',
              'Ввести данные',
              AppTheme.primary,
              () {
                Navigator.pop(ctx);
                _showManualAdd();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        onTap: onTap,
      ),
    );
  }

  // ==================== ГОЛОСОВОЙ ВВОД С РАЗДЕЛЕНИЕМ ====================
  void _showVoiceInput() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnack('Нужно разрешение на микрофон', AppTheme.warning);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoiceInputSheet(
        onResult: (products) {
          Navigator.pop(ctx);
          _showVoiceConfirmList(products);
        },
      ),
    );
  }

  void _showVoiceConfirmList(List<Map<String, dynamic>> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoiceConfirmSheet(
        products: products,
        onConfirm: (confirmed) async {
          final productsToAdd = confirmed.map((p) {
            final category = _detectCategory(p['name']);
            return Product(
              id: DateTime.now().millisecondsSinceEpoch.toString() + p['name'],
              name: p['name'],
              expiryDate: DateTime.now().add(Duration(days: p['days'])),
              category: category.name,
              iconName: category.name.toLowerCase(),
              addedDate: DateTime.now(),
            );
          }).toList();
          
          await _service.addMultiple(productsToAdd);
          _filterProducts();
          Navigator.pop(ctx);
          _showSnack('Добавлено ${productsToAdd.length} продуктов', AppTheme.success);
        },
        onAddMore: () {
          // Продолжаем добавлять голосом
          Navigator.pop(ctx);
          _showVoiceInput();
        },
      ),
    );
  }

  ProductCategory _detectCategory(String name) {
    final lower = name.toLowerCase();
    for (final entry in categories.entries) {
      if (lower.contains(entry.key.toLowerCase()) ||
          lower.contains(entry.value.name.toLowerCase())) {
        return entry.value;
      }
    }
    return categories['Другое']!;
  }

  // ==================== СКАНЕР ЧЕСТНОГО ЗНАКА ====================
  void _showHonestSignScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _showSnack('Нужно разрешение на камеру', AppTheme.warning);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => HonestSignScannerScreen(
          onScan: (barcode) async {
            // Парсим срок годности из Честного ЗНАКА
            final expiryDate = HonestSignParser.parseExpiryDate(barcode);
            
            if (expiryDate != null) {
              // Пробуем найти в базе
              final data = ProductDatabase.findByBarcode(barcode);
              final product = Product(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: data?['name'] ?? 'Продукт',
                expiryDate: expiryDate,
                category: data?['category'] ?? 'Другое',
                iconName: (data?['category'] ?? 'другое').toString().toLowerCase(),
                addedDate: DateTime.now(),
                barcode: barcode,
              );
              await _service.add(product);
              _filterProducts();
              _showSnack('Добавлено: ${product.name}', AppTheme.success);
            } else {
              // Если не распарсили срок - ручной ввод
              _showManualAdd(barcode: barcode);
            }
          },
        ),
      ),
    );
  }

  // ==================== РУЧНОЙ ВВОД ====================
  void _showManualAdd({String? barcode}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ManualAddSheet(
        barcode: barcode,
        onSave: (product) async {
          await _service.add(product);
          _filterProducts();
          _showSnack('Добавлено: ${product.name}', AppTheme.success);
        },
      ),
    );
  }

  // ==================== АНАЛИТИКА ====================
  void _showAnalytics() {
    final stats = _service.getStats();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnalyticsSheet(stats: stats),
    );
  }

  // ==================== НАСТРОЙКИ ====================
  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsSheet(
        isDark: widget.isDark,
        onThemeToggle: widget.onThemeToggle,
        onClearAll: () async {
          await _service.clearAll();
          _filterProducts();
          Navigator.pop(ctx);
          _showSnack('Все продукты удалены', AppTheme.danger);
        },
        onExport: () async {
          final json = await _service.exportToJson();
          await Share.share(json, subject: 'СмартПолка Backup');
        },
        onShowAnalytics: () {
          Navigator.pop(ctx);
          _showAnalytics();
        },
      ),
    );
  }

  Widget _buildHandle() => Center(
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: 48,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.3),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stats = _service.getStats();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              SliverAppBar(
                expandedHeight: 160,
                floating: true,
                pinned: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'СмартПолка',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26),
                  ),
                  centerTitle: true,
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primary.withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _showSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildStatsRow(stats),
                      const SizedBox(height: 20),
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      _buildCategoryFilter(),
                    ],
                  ),
                ),
              ),
              _filtered.isEmpty
                  ? SliverFillRemaining(
                      child: _buildEmptyState(isDark),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (c, i) => _buildProductCard(_filtered[i]),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiCtrl,
              blastDirectionality: BlastDirectionality.explosive,
              particleDrag: 0.05,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.2,
              colors: const [
                AppTheme.primary,
                AppTheme.secondary,
                AppTheme.accent,
                AppTheme.success,
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        offset: _showFab ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showFab ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.secondary],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: _showAddOptions,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 26),
                      SizedBox(width: 14),
                      Text(
                        'ДОБАВИТЬ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> stats) {
    return Row(
      children: [
        _buildStatCard(
          stats['total'].toString(),
          Icons.kitchen,
          Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1E293B),
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          stats['expiringSoon'].toString(),
          Icons.timer,
          AppTheme.warning,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          stats['expired'].toString(),
          Icons.warning,
          AppTheme.danger,
        ),
      ],
    );
  }

  Widget _buildStatCard(String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          setState(() => _searchQuery = v);
          _filterProducts();
        },
        decoration: InputDecoration(
          hintText: 'Поиск продуктов...',
          hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
          prefixIcon: Icon(Icons.search, color: Color(0xFF9E9E9E)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Color(0xFF9E9E9E)),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                    _filterProducts();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final cats = ['Все', 'Другое', ...categories.keys.take(6)];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        itemBuilder: (ctx, i) {
          final isSelected = _selectedCategory == cats[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cats[i]),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedCategory = cats[i]);
                _filterProducts();
              },
              selectedColor: AppTheme.primary,
              backgroundColor: Theme.of(context).cardTheme.color,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? AppTheme.primary : Colors.grey.withOpacity(0.2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.kitchen_outlined,
            color: isDark ? Colors.white24 : Colors.black12,
            size: 100,
          ),
          const SizedBox(height: 24),
          Text(
            'Нет продуктов',
            style: TextStyle(
              color: isDark ? Colors.white30 : Colors.black26,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте первый продукт',
            style: TextStyle(
              color: isDark ? Colors.white.withOpacity(0.2) : Colors.black12,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product p) {
    final cat = categories[p.category] ?? categories['Другое']!;
    
    return Slidable(
      key: Key(p.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _deleteProduct(p.id),
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Удалить',
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.statusColor.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: p.statusColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => _toggleUsed(p),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cat.color.withOpacity(0.3),
                        cat.color.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(cat.icon, color: cat.color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          decoration: p.isUsed ? TextDecoration.lineThrough : null,
                          color: p.isUsed ? Colors.grey : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          p.statusText,
                          style: TextStyle(
                            color: p.statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        p.statusColor.withOpacity(0.15),
                        p.statusColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${p.daysLeft.abs()}',
                        style: TextStyle(
                          color: p.statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        p.daysLeft == 1 ? 'день' : 'дн.',
                        style: TextStyle(
                          color: p.statusColor.withOpacity(0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }
}

// ==================== ГОЛОСОВОЙ ВВОД С РАЗДЕЛЕНИЕМ ====================
class VoiceInputSheet extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onResult;

  const VoiceInputSheet({super.key, required this.onResult});

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<VoiceInputSheet>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late AnimationController _animCtrl;
  bool _isListening = false;
  String _text = '';
  String _status = 'Нажмите и говорите';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && _isListening) {
          _stopListening();
        }
      },
      onError: (error) {
        setState(() {
          _status = 'Ошибка: ${error.errorMsg}';
          _isListening = false;
        });
      },
    );
  }

  void _startListening() async {
    if (!_speech.isAvailable) {
      setState(() => _status = 'Распознавание недоступно');
      return;
    }

    setState(() {
      _isListening = true;
      _text = '';
      _status = 'Слушаю...';
    });
    _animCtrl.repeat();

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _text = result.recognizedWords;
          if (result.finalResult) {
            _processResult(_text);
          }
        });
      },
      localeId: 'ru_RU',
    );
  }

  void _stopListening() async {
    await _speech.stop();
    _animCtrl.stop();
    setState(() => _isListening = false);
    if (_text.isNotEmpty) {
      _processResult(_text);
    }
  }

  void _processResult(String text) {
    // Парсим несколько продуктов: "Молоко 5 Хлеб 3 Икра 10"
    final products = <Map<String, dynamic>>[];
    
    // Разбиваем по ключевым словам продуктов или по цифрам
    final pattern = RegExp(r'([а-яА-ЯёЁ\s]+?)\s+(\d+)\s*(?:дн?\.?(?:ей|я|ь)?)?', caseSensitive: false);
    final matches = pattern.allMatches(text);
    
    for (final match in matches) {
      final name = match.group(1)!.trim();
      final days = int.tryParse(match.group(2)!) ?? 7;
      if (name.isNotEmpty) {
        products.add({'name': name, 'days': days});
      }
    }
    
    if (products.isEmpty) {
      // Если не распарсили - берем всё как один продукт с дефолтным сроком
      products.add({'name': text.trim(), 'days': 7});
    }
    
    widget.onResult(products);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Голосовой ввод',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _status,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTapDown: (_) => _startListening(),
            onTapUp: (_) => _stopListening(),
            onTapCancel: () => _stopListening(),
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (ctx, child) {
                final scale = _isListening
                    ? 1.0 + math.sin(_animCtrl.value * math.pi * 2) * 0.1
                    : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [AppTheme.primary, AppTheme.secondary]
                            : [Colors.grey.shade300, Colors.grey.shade400],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 40),
          if (_text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _text,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Примеры:\n"Молоко 5 дней, Хлеб 3 дня, Яйца 14"',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _animCtrl.dispose();
    super.dispose();
  }
}

// ==================== ПОДТВЕРЖДЕНИЕ СПИСКА ГОЛОСОВОГО ВВОДА ====================
class VoiceConfirmSheet extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final Function(List<Map<String, dynamic>>) onConfirm;
  final VoidCallback onAddMore;

  const VoiceConfirmSheet({
    super.key,
    required this.products,
    required this.onConfirm,
    required this.onAddMore,
  });

  @override
  State<VoiceConfirmSheet> createState() => _VoiceConfirmSheetState();
}

class _VoiceConfirmSheetState extends State<VoiceConfirmSheet> {
  late List<Map<String, dynamic>> _products;

  @override
  void initState() {
    super.initState();
    _products = List.from(widget.products);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Проверьте список',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${_products.length} продуктов',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _products.length,
              itemBuilder: (ctx, i) {
                final p = _products[i];
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${p['days']} дн.',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(p['name']),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                    onPressed: () {
                      setState(() => _products.removeAt(i));
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onAddMore,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить ещё'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_products),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'ДОБАВИТЬ ВСЁ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ==================== СКАНЕР ЧЕСТНОГО ЗНАКА ====================
class HonestSignScannerScreen extends StatefulWidget {
  final Function(String barcode) onScan;

  const HonestSignScannerScreen({super.key, required this.onScan});

  @override
  State<HonestSignScannerScreen> createState() => _HonestSignScannerScreenState();
}

class _HonestSignScannerScreenState extends State<HonestSignScannerScreen> {
  bool _isScanning = true;
  String? _lastBarcode;

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    
    final barcode = capture.barcodes.firstOrNull;
    if (barcode != null && barcode.rawValue != null) {
      final value = barcode.rawValue!;
      if (value != _lastBarcode) {
        _lastBarcode = value;
        setState(() => _isScanning = false);
        HapticFeedback.mediumImpact();
        widget.onScan(value);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),
          // Простой квадратик без символов
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 20,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
            ),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white70,
                  size: 40,
                ),
                const SizedBox(height: 16),
                Text(
                  'Наведите на Data Matrix (Честный ЗНАК)',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== РУЧНОЕ ДОБАВЛЕНИЕ ====================
class ManualAddSheet extends StatefulWidget {
  final String? barcode;
  final Function(Product product) onSave;

  const ManualAddSheet({super.key, this.barcode, required this.onSave});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  final _nameCtrl = TextEditingController();
  int _days = 7;
  String _selectedCategory = 'Другое';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    if (widget.barcode != null) {
      // Пробуем распарсить срок из Честного ЗНАКА
      final expiry = HonestSignParser.parseExpiryDate(widget.barcode!);
      if (expiry != null) {
        _selectedDate = expiry;
        _days = expiry.difference(DateTime.now()).inDays;
      }
      _nameCtrl.text = 'Продукт ${widget.barcode!.substring(0, math.min(8, widget.barcode!.length))}';
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
        _days = date.difference(DateTime.now()).inDays;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Новый продукт',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Название продукта...',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (ctx, i) {
                final cat = categories.values.elementAt(i);
                final isSelected = _selectedCategory == cat.name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(cat.icon, size: 18, color: isSelected ? Colors.white : cat.color),
                    label: Text(cat.name),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat.name),
                    selectedColor: cat.color,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Срок годности',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd.MM.yyyy').format(_selectedDate),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$_days дн.',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                if (_nameCtrl.text.trim().isEmpty) return;
                final cat = categories[_selectedCategory]!;
                final product = Product(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: _nameCtrl.text.trim(),
                  expiryDate: _selectedDate,
                  category: _selectedCategory,
                  iconName: _selectedCategory.toLowerCase(),
                  addedDate: DateTime.now(),
                  barcode: widget.barcode,
                );
                widget.onSave(product);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
                shadowColor: AppTheme.primary.withOpacity(0.4),
              ),
              child: const Text(
                'ДОБАВИТЬ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1,
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
    _nameCtrl.dispose();
    super.dispose();
  }
}

// ==================== АНАЛИТИКА ====================
class AnalyticsSheet extends StatelessWidget {
  final Map<String, dynamic> stats;

  const AnalyticsSheet({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats['total'] as int;
    final expired = stats['expired'] as int;
    final expiringSoon = stats['expiringSoon'] as int;
    final fresh = stats['fresh'] as int;
    final used = stats['used'] as int;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.analytics, color: Colors.white),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Аналитика',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (total > 0)
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      value: fresh.toDouble(),
                      color: AppTheme.success,
                      title: fresh > 0 ? '$fresh' : '',
                      radius: 60,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: expiringSoon.toDouble(),
                      color: AppTheme.warning,
                      title: expiringSoon > 0 ? '$expiringSoon' : '',
                      radius: 60,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: expired.toDouble(),
                      color: AppTheme.danger,
                      title: expired > 0 ? '$expired' : '',
                      radius: 60,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PieChartSectionData(
                      value: used.toDouble(),
                      color: Colors.grey,
                      title: used > 0 ? '$used' : '',
                      radius: 60,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text('Нет данных для анализа'),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                _buildStatRow('Всего продуктов', total, AppTheme.primary),
                _buildStatRow('Свежих', fresh, AppTheme.success),
                _buildStatRow('Истекает скоро', expiringSoon, AppTheme.warning),
                _buildStatRow('Просрочено', expired, AppTheme.danger),
                _buildStatRow('Использовано', used, Colors.grey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

// ==================== НАСТРОЙКИ ====================
class SettingsSheet extends StatelessWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;
  final VoidCallback onClearAll;
  final VoidCallback onExport;
  final VoidCallback onShowAnalytics;

  const SettingsSheet({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
    required this.onClearAll,
    required this.onExport,
    required this.onShowAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Настройки',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildTile(
            isDark ? Icons.dark_mode : Icons.light_mode,
            isDark ? 'Тёмная тема' : 'Светлая тема',
            onThemeToggle,
            AppTheme.primary,
          ),
          _buildTile(
            Icons.analytics,
            'Аналитика',
            onShowAnalytics,
            AppTheme.secondary,
          ),
          _buildTile(
            Icons.help_outline,
            'Гайд по приложению',
            () => _showGuide(context),
            AppTheme.info,
          ),
          _buildTile(
            Icons.share,
            'Экспорт данных',
            onExport,
            AppTheme.info,
          ),
          _buildTile(
            Icons.delete_forever,
            'Очистить всё',
            () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Очистить всё?'),
                  content: const Text('Все продукты будут удалены безвозвратно.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onClearAll();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                      ),
                      child: const Text('Удалить'),
                    ),
                  ],
                ),
              );
            },
            AppTheme.danger,
          ),
          const SizedBox(height: 20),
          // PRO версия
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.accent.withOpacity(0.2), AppTheme.accent.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.star, color: AppTheme.accent),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRO версия',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          Text(
                            'Глубокая аналитика + скан чеков',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Заглушка для PRO версии
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('PRO версия'),
                          content: const Text(
                            'PRO версия включает:\n\n'
                            '• Глубокую аналитику расходов\n'
                            '• Сканирование QR-кодов чеков\n'
                            '• Экспорт в Excel\n'
                            '• Безлимитные продукты\n\n'
                            '149 ₽/месяц\n\n'
                            'Скоро в Google Play!',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Понятно'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('149 ₽/мес'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'СмартПолка v1.0.0',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Автор: Nikita Lob',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(IconData icon, String title, VoidCallback onTap, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showGuide(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Гайд по СмартПолке',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: const [
                  _GuideItem(
                    icon: Icons.add_circle,
                    title: 'Добавление продуктов',
                    description: 'Нажмите кнопку "Добавить" и выберите способ: голосом, сканированием Честного ЗНАКА или вручную.',
                  ),
                  _GuideItem(
                    icon: Icons.mic,
                    title: 'Голосовой ввод',
                    description: 'Скажите: "Молоко 5 дней, Хлеб 3 дня". Приложение автоматически разделит продукты.',
                  ),
                  _GuideItem(
                    icon: Icons.qr_code_scanner,
                    title: 'Сканирование',
                    description: 'Наведите камеру на Data Matrix код (Честный ЗНАК). Срок годности определится автоматически.',
                  ),
                  _GuideItem(
                    icon: Icons.notifications,
                    title: 'Уведомления',
                    description: 'За день до истечения срока вы получите уведомление.',
                  ),
                  _GuideItem(
                    icon: Icons.check_circle,
                    title: 'Отметка использования',
                    description: 'Нажмите на продукт, чтобы отметить его использованным.',
                  ),
                  _GuideItem(
                    icon: Icons.swipe,
                    title: 'Удаление',
                    description: 'Свайпните продукт влево для удаления.',
                  ),
                  _GuideItem(
                    icon: Icons.analytics,
                    title: 'Аналитика',
                    description: 'Смотрите статистику по продуктам в разделе Аналитика.',
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Понятно!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _GuideItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
