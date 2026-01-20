import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants/app_string.dart';

class BasketData {
  final String basketNo;
  final String basketVendor;
  final int basketCapacity;
  final String basketLength;
  final String basketReceiveDate;
  final String basketPurchaseOrder;
  final String formerSize;
  final int formerUsedDay;

  BasketData({
    required this.basketNo,
    required this.basketVendor,
    required this.basketCapacity,
    required this.basketLength,
    required this.basketReceiveDate,
    required this.basketPurchaseOrder,
    required this.formerSize,
    required this.formerUsedDay,
  });

  factory BasketData.fromJson(Map<String, dynamic> json) {
    return BasketData(
      basketNo: json['basket_no'] ?? '',
      basketVendor: json['basket_vendor'] ?? '',
      basketCapacity: json['basket_capacity'] ?? 0,
      basketLength: json['basket_length'] ?? '',
      basketReceiveDate: json['basket_receive_date'] ?? '',
      basketPurchaseOrder: json['basket_purchase_order'] ?? '',
      formerSize: json['former_size'] ?? '',
      formerUsedDay: json['former_used_day'] ?? 0,
    );
  }
}

class ApiService {
  static Future<BasketData?> getBasketData(String tagId) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}${AppStrings.uhfBasketApi}?tagId=$tagId');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['data'] != null && jsonData['data'].isNotEmpty) {
          return BasketData.fromJson(jsonData['data'][0]);
        }
        return null;
      } else {
        throw Exception('Failed to load basket data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching basket data: $e');
      rethrow;
    }
  }
}