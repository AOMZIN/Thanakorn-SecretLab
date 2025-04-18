// models/category.dart
import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String? parentCategoryId;
  final bool isIncome;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.parentCategoryId,
    this.isIncome = false,
  });
}