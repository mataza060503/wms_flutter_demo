class AppStrings {
  static const String appName = 'WMS Flutter';
  
  // API
  static const String apiBaseUrl = 'http://172.18.55.218:8000';
  static const String uhfBasketApi = '/wh_former/uhf/basket';
  static const String uhfBasketStockOutApi = '/wh_former/uhf/basket/stock_out';

  // API Helpers
  static const String getPlantsApi = '/wh_former/get/plants/';
  static const String getMachinesApi = '/wh_former/get/machines/'; //params: plant, mode (change || clean || to_lk)
  static const String getLinesApi = '/wh_former/get/lines/'; //params: machine
  static const String getStockFormApi = '/wh_former/stock_form/get/'; 
  //params: machine, line_name, stock_type, size_name_input
  
  // Navigation
  static const String home = 'Home';
  static const String formerStockIn = 'Former Stock In';
  static const String formerStockOut = 'Former Stock Out';
  static const String rfidTest = 'RFID Test';
  
  // Common
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String add = 'Add';
  static const String search = 'Search';
  static const String filter = 'Filter';
}