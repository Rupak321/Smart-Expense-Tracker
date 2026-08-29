import 'package:flutter/material.dart';

/// Maps stored icon keys to icons.
///
/// Categories store a key such as 'restaurant' rather than an icon code point.
/// Building an IconData from a stored code point defeats Flutter's icon
/// tree-shaking, which either bloats the release build or fails it outright.
class CategoryIcons {
  const CategoryIcons._();

  static const fallbackKey = 'category';

  static const _icons = <String, IconData>{
    'category': Icons.category_rounded,
    'restaurant': Icons.restaurant_rounded,
    'groceries': Icons.local_grocery_store_rounded,
    'transport': Icons.directions_bus_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'bill': Icons.receipt_long_rounded,
    'home': Icons.home_rounded,
    'health': Icons.medical_services_rounded,
    'education': Icons.school_rounded,
    'entertainment': Icons.movie_rounded,
    'personal': Icons.person_rounded,
    'salary': Icons.payments_rounded,
    'business': Icons.storefront_rounded,
    'laptop': Icons.laptop_mac_rounded,
    'gift': Icons.card_giftcard_rounded,
    'investment': Icons.trending_up_rounded,
    'refund': Icons.replay_rounded,
    'travel': Icons.flight_takeoff_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'phone': Icons.smartphone_rounded,
    'pet': Icons.pets_rounded,
    'fitness': Icons.fitness_center_rounded,
    'coffee': Icons.local_cafe_rounded,
    'savings': Icons.savings_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'insurance': Icons.shield_rounded,
  };

  /// Keys offered when picking an icon for a category.
  static List<String> get pickable => _icons.keys.toList();

  static IconData resolve(String? key) {
    return _icons[key] ?? _icons[fallbackKey]!;
  }

  /// Best-guess icon for a brand new category, from its name.
  static String suggestFor(String name) {
    final lower = name.toLowerCase();
    const guesses = <String, String>{
      'food': 'restaurant',
      'restaurant': 'restaurant',
      'dining': 'restaurant',
      'coffee': 'coffee',
      'tea': 'coffee',
      'grocer': 'groceries',
      'transport': 'transport',
      'travel': 'travel',
      'flight': 'travel',
      'fuel': 'fuel',
      'petrol': 'fuel',
      'shop': 'shopping',
      'cloth': 'shopping',
      'bill': 'bill',
      'utilit': 'bill',
      'rent': 'home',
      'hous': 'home',
      'health': 'health',
      'medic': 'health',
      'hospital': 'health',
      'educat': 'education',
      'school': 'education',
      'college': 'education',
      'course': 'education',
      'entertain': 'entertainment',
      'movie': 'entertainment',
      'game': 'entertainment',
      'salary': 'salary',
      'wage': 'salary',
      'business': 'business',
      'freelance': 'laptop',
      'gift': 'gift',
      'family': 'gift',
      'invest': 'investment',
      'refund': 'refund',
      'phone': 'phone',
      'mobile': 'phone',
      'pet': 'pet',
      'gym': 'fitness',
      'fitness': 'fitness',
      'saving': 'savings',
      'charit': 'charity',
      'donat': 'charity',
      'insur': 'insurance',
    };

    for (final entry in guesses.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return fallbackKey;
  }
}
