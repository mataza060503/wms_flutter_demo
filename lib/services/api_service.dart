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
  final String bin;
  final String formerSize;
  final int formerUsedDay;

  BasketData({
    required this.basketNo,
    required this.basketVendor,
    required this.basketCapacity,
    required this.basketLength,
    required this.basketReceiveDate,
    required this.basketPurchaseOrder,
    required this.bin,
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
      bin: json['bin'] ?? '',
      formerSize: json['former_size'] ?? '',
      formerUsedDay: json['former_used_day'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'basketNo': basketNo,
        'basketVendor': basketVendor,
        'basketCapacity': basketCapacity,
        'basketLength': basketLength,
        'basketReceiveDate': basketReceiveDate,
        'basketPurchaseOrder': basketPurchaseOrder,
        'bin': bin,
        'formerSize': formerSize,
        'formerUsedDay': formerUsedDay,
      };
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

  static Future<BasketData?> getStockOutBasketData(String tagId) async {
    try {
      final url = Uri.parse('${AppStrings.apiBaseUrl}${AppStrings.uhfBasketStockOutApi}?tagId=$tagId');
      
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

  /// ------------------ PLANTS ------------------
  static Future<List<String>> getPlants() async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getPlantsApi}',
      );
      print('Fetching plants from $uri');

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('Plants data: $jsonData');
        return List<String>.from(jsonData['plants'] ?? []);
      } else {
        throw Exception('Failed to load plants');
      }
    } catch (e) {
      print('Error fetching plants: $e');
      rethrow;
    }
  }

  /// ------------------ MACHINES ------------------
  static Future<List<String>> getMachines({
    required String plant,
    String? mode, // change | clean | to_lk
  }) async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getMachinesApi}',
      ).replace(queryParameters: {
        'plant': plant,
        if (mode != null) 'mode': mode,
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return List<String>.from(jsonData['machines'] ?? []);
      } else {
        throw Exception('Failed to load machines');
      }
    } catch (e) {
      print('Error fetching machines: $e');
      rethrow;
    }
  }

  /// ------------------ LINES ------------------
  static Future<List<String>> getLines({
    required String machine,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getLinesApi}',
      ).replace(queryParameters: {
        'machine': machine,
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return List<String>.from(jsonData['lines'] ?? []);
      } else {
        throw Exception('Failed to load lines');
      }
    } catch (e) {
      print('Error fetching lines: $e');
      rethrow;
    }
  }

  /// ------------------ STOCK FORM ------------------
  static Future<String> getStockForm({
    required String machine,
    required String lineName,
    required String sizeNameInput,
    int? stockType,
    String? existingForm,
    String? idStockForm,
    int? buttonMode,
    int? callByButton,
  }) async {
    try {
      final uri = Uri.parse(
        '${AppStrings.apiBaseUrl}${AppStrings.getStockFormApi}',
      ).replace(queryParameters: {
        'machine': machine,
        'line_name': lineName,
        'size_name_input': sizeNameInput,
        'stock_type': stockType.toString(),
        if (existingForm != null) 'existing_form': existingForm,
        if (idStockForm != null) 'id_stock_form': idStockForm,
        if (buttonMode != null) 'button_mode': buttonMode.toString(),
        if (callByButton != null) 'call_by_button': callByButton.toString(),
      });

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return jsonData['form_name'] as String;
      } else {
        throw Exception('Failed to load form name');
      }
    } catch (e) {
      print('Error fetching form name: $e');
      rethrow;
    }
  }
}