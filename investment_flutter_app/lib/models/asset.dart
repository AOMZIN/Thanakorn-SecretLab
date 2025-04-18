class Portfolio {
  final int id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Portfolio({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Portfolio.fromMap(Map<String, dynamic> map) {
    return Portfolio(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}

class Asset {
  final int id;
  final int portfolioId;
  final String symbol;
  final String name;
  final String assetType;
  final double allocation;

  Asset({
    required this.id,
    required this.portfolioId,
    required this.symbol,
    required this.name,
    required this.assetType,
    required this.allocation,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'portfolioId': portfolioId,
      'symbol': symbol,
      'name': name,
      'assetType': assetType,
      'allocation': allocation,
    };
  }

  factory Asset.fromMap(Map<String, dynamic> map) {
    return Asset(
      id: map['id'],
      portfolioId: map['portfolioId'],
      symbol: map['symbol'],
      name: map['name'],
      assetType: map['assetType'],
      allocation: map['allocation'],
    );
  }
}

class AssetPrice {
  final int id;
  final int assetId;
  final DateTime date;
  final double price;

  AssetPrice({
    required this.id,
    required this.assetId,
    required this.date,
    required this.price,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'assetId': assetId,
      'date': date.toIso8601String(),
      'price': price,
    };
  }

  factory AssetPrice.fromMap(Map<String, dynamic> map) {
    return AssetPrice(
      id: map['id'],
      assetId: map['assetId'],
      date: DateTime.parse(map['date']),
      price: map['price'],
    );
  }
}