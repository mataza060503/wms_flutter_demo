import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';
import '../common/app_modal.dart';
import '../common/rfid_scanned_items_modal.dart';
import '../common/filled_basket_qty_modal.dart';
import '../common/rack_detail_modal.dart';
import '../../services/rfid_scanner.dart';
import '../../services/api_service.dart';
import 'package:wms_flutter/models/scanned_item.dart';

enum ScannerStatus {
  disconnected,
  initializing,
  initialized,
  connected,
  scanning,
  stopped,
}

enum BasketMode { full, filled, empty }

class RfidScannerComponent extends StatefulWidget {
  final RfidScanner? rfidScanner;
  final VoidCallback? onScanComplete;

  const RfidScannerComponent({
    Key? key,
    this.rfidScanner,
    this.onScanComplete,
  }) : super(key: key);

  @override
  State<RfidScannerComponent> createState() => RfidScannerComponentState();
}

class RfidScannerComponentState extends State<RfidScannerComponent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late RfidScanner _rfidScanner;
  double rfidPower = 25.0;
  bool isScanning = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;
  BasketMode _basketMode = BasketMode.full;
  int quantity = 0;

  final Map<String, ScannedItem> _scannedItemsMap = {};
  StreamSubscription<TagData>? _tagSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<String>? _errorSubscription;

  final Queue<String> _unfetchedTags = Queue<String>();
  static const int _maxConcurrentRequests = 50;
  int _activeRequests = 0;
  bool _queueRunning = false;

  final List<Rack> _racks = [];
  int get currentRackNo => _racks.length + 1;
  final Set<String> _allRackTagIds = {};

  int _totalBaskets = 0;
  int _totalFormers = 0;
  bool _singleTagCaptured = false;

  @override
  void initState() {
    super.initState();
    _rfidScanner = widget.rfidScanner ?? RfidScanner();
    _initializeRfid();
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    
    if (isScanning) _rfidScanner.stopScan();
    if (widget.rfidScanner == null && isConnected) {
      _rfidScanner.disconnect();
    }
    
    super.dispose();
  }

  void onTabActivated() {
    // Tab became visible
    setState(() {});
  }

  Future<void> onTabDeactivated() async {
    if (isScanning) {
      await _rfidScanner.stopScan();
      isScanning = false;
    }
  }

  Future<void> _initializeRfid() async {
    try {
      setState(() => scannerStatus = ScannerStatus.initializing);
      
      final initSuccess = await _rfidScanner.init();
      if (!initSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        return;
      }

      setState(() => scannerStatus = ScannerStatus.initialized);

      final connectSuccess = await _rfidScanner.connect();
      if (!connectSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        return;
      }

      setState(() {
        scannerStatus = ScannerStatus.connected;
        isConnected = true;
      });

      await _rfidScanner.setPower(_convertPowerToLevel(rfidPower));

      _tagSubscription = _rfidScanner.onTagScanned.listen(_handleTagScanned);
      _statusSubscription = _rfidScanner.onConnectionStatusChange.listen(_handleStatusChange);
      _errorSubscription = _rfidScanner.onError.listen((error) => _showError('RFID Error', error));

      if (mounted) {
        AppModal.showSuccess(
          context: context,
          title: 'Connected',
          message: 'RFID scanner ready',
        );
      }
    } catch (e) {
      setState(() => scannerStatus = ScannerStatus.disconnected);
    }
  }

  void _handleTagScanned(TagData tagData) async {    
    if (_basketMode == BasketMode.filled && _singleTagCaptured) return;

    final tagId = tagData.tagId;
    if (_allRackTagIds.contains(tagId)) return;
    if (_scannedItemsMap.containsKey(tagId)) return;

    if (_basketMode == BasketMode.full) {
      quantity = 5;
    } else if (_basketMode == BasketMode.empty) {
      quantity = 0;
    }

    if (_basketMode == BasketMode.filled) {
      _singleTagCaptured = true;
      await _rfidScanner.stopScan();
      setState(() {
        isScanning = false;
        scannerStatus = ScannerStatus.connected;
      });

      final selectedQty = await FilledBasketQtyModal.show(context);
      if (selectedQty == null) return;
      quantity = selectedQty;
    }

    final pendingItem = ScannedItem(
      id: tagId,
      quantity: 0,
      vendor: '',
      bin: '',
      status: ItemStatus.pending,
      rssi: tagData.rssi,
    );

    _scannedItemsMap[tagId] = pendingItem;
    _updateStats();
    _unfetchedTags.add(tagId);
    _processApiQueue();
  }

  void _updateStats() {
    final baskets = _scannedItemsMap.values
        .where((item) => item.status == ItemStatus.success)
        .length;
    final formers = _scannedItemsMap.values
        .fold<int>(0, (sum, item) => sum + item.quantity);
    
    if (_totalBaskets != baskets || _totalFormers != formers) {
      setState(() {
        _totalBaskets = baskets;
        _totalFormers = formers;
      });
    }
  }

  void _processApiQueue() {
    if (_queueRunning) return;
    _queueRunning = true;

    while (_activeRequests < _maxConcurrentRequests && _unfetchedTags.isNotEmpty) {
      final tagId = _unfetchedTags.removeFirst();
      _activeRequests++;
      _fetchAndProcessTag(tagId);
    }

    _queueRunning = false;
  }

  Future<void> _fetchAndProcessTag(String tagId) async {
    try {
      final basketData = await ApiService.getBasketData(tagId);
      final existingItem = _scannedItemsMap[tagId];
      if (existingItem == null) return;

      if (basketData != null) {
        existingItem.status = ItemStatus.success;
        existingItem.quantity = quantity;
        existingItem.vendor = basketData.basketVendor;
        existingItem.bin = basketData.basketPurchaseOrder;
        existingItem.basketData = basketData;
      } else {
        existingItem.status = ItemStatus.error;
        existingItem.quantity = 0;
        existingItem.errorMessage = 'No data found for this tag';
      }
    } catch (e) {
      final existingItem = _scannedItemsMap[tagId];
      if (existingItem != null) {
        existingItem.status = ItemStatus.error;
        existingItem.quantity = 0;
        existingItem.errorMessage = 'Failed to fetch data';
      }
    } finally {
      _activeRequests--;
      _updateStats();
      _processApiQueue();
    }
  }

  void _handleStatusChange(ConnectionStatus status) {
    if (!mounted) return;
    
    switch (status) {
      case ConnectionStatus.connected:
        setState(() {
          isConnected = true;
          scannerStatus = ScannerStatus.connected;
        });
        break;
      case ConnectionStatus.disconnected:
        setState(() {
          isConnected = false;
          isScanning = false;
          scannerStatus = ScannerStatus.disconnected;
        });
        break;
      case ConnectionStatus.scanStopped:
        setState(() {
          isScanning = false;
          scannerStatus = ScannerStatus.stopped;
        });
        break;
      default:
        break;
    }
  }

  int _convertPowerToLevel(double power) {
    return ((power / 50) * 32 + 1).round().clamp(1, 33);
  }

  Future<void> _startScanning() async {
    if (!isConnected) {
      _showError('Not Connected', 'Please connect to RFID scanner first');
      return;
    }

    if (_basketMode == BasketMode.filled) {
      _singleTagCaptured = false;
    }

    try {
      final success = await _rfidScanner.startScan(
        mode: ScanMode.continuous,
        uniqueOnly: true,
      );

      if (success) {
        setState(() {
          isScanning = true;
          scannerStatus = ScannerStatus.scanning;
        });
      }
    } catch (e) {
      _showError('Start Scan Failed', e.toString());
    }
  }

  Future<void> _stopScanning() async {
    try {
      final success = await _rfidScanner.stopScan();
      if (success) {
        setState(() {
          isScanning = false;
          scannerStatus = ScannerStatus.stopped;
        });
      }
    } catch (e) {
      _showError('Stop Scan Failed', e.toString());
    }
  }

  Future<void> _clearScannedItems() async {
    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Clear All Items',
      message: 'Are you sure you want to clear all scanned items?',
    );

    if (confirm == true) {
      try {
        await _rfidScanner.clearSeenTags();
        setState(() {
          _scannedItemsMap.clear();
          _unfetchedTags.clear();
          _totalBaskets = 0;
          _totalFormers = 0;
        });
      } catch (e) {
        _showError('Clear Failed', e.toString());
      }
    }
  }

  void _showError(String title, String message) {
    if (!mounted) return;
    AppModal.showError(context: context, title: title, message: message);
  }

  void _showWarning(String title, String message) {
    if (!mounted) return;
    AppModal.showWarning(context: context, title: title, message: message);
  }

  Future<void> _showScannedItemsModal() async {
    if (_scannedItemsMap.isEmpty) {
      _showError('Empty', 'No scanned items to view');
      return;
    }

    await RfidScannedItemsModal.show(
      context: context,
      scannedItemsMap: _scannedItemsMap,
      onBinLocationChanged: (item, bin) {
        setState(() {
          for (final scannedItem in _scannedItemsMap.values) {
            scannedItem.bin = bin;
          }
        });
      },
    );
  }

  Future<void> _addCurrentScannedToRack() async {
    if (_scannedItemsMap.isEmpty) {
      _showWarning('Empty', 'No scanned items to add');
      return;
    }

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Add to Rack',
      message: 'Add ${_scannedItemsMap.length} items to Rack $currentRackNo?',
    );

    if (confirm != true) return;

    setState(() {
      _racks.add(
        Rack(
          rackNo: currentRackNo,
          items: _scannedItemsMap.values.toList(),
        ),
      );

      _allRackTagIds.addAll(_scannedItemsMap.keys);
      _scannedItemsMap.clear();
      _totalBaskets = 0;
      _totalFormers = 0;
    });

    AppModal.showSuccess(
      context: context,
      title: 'Rack Added',
      message: 'Items saved successfully to Rack ${currentRackNo - 1}',
    );
  }

  Future<bool> handleExit() async {
    if (_allRackTagIds.isEmpty) return true;

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Unsaved Items',
      message:
          'You have ${_allRackTagIds.length} scanned items that are not saved yet.\n\nAre you sure you want to exit?',
      confirmText: 'EXIT',
      cancelText: 'CANCEL',
    );

    return confirm == true;
  }

  Map<String, dynamic> getScanData() {
    return {
      'scannedItems': _scannedItemsMap,
      'racks': _racks,
      'allRackTagIds': _allRackTagIds,
      'totalBaskets': _totalBaskets,
      'totalFormers': _totalFormers,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildBasketModeSelector(),
          const SizedBox(height: 24),
          _buildStatsCards(),
          const SizedBox(height: 24),
          _buildRFIDScannerCard(),
          const SizedBox(height: 24),
          if (isScanning) _buildScanningIndicator(),
        ],
      ),
    );
  }

  Widget _buildBasketModeSelector() {
    Widget buildButton(BasketMode mode, String label) {
      final bool selected = _basketMode == mode;

      return Expanded(
        child: GestureDetector(
          onTap: () async {
            setState(() => _basketMode = mode);
            if (mode == BasketMode.filled) {
              await _rfidScanner.stopScan();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          buildButton(BasketMode.full, 'Full basket'),
          buildButton(BasketMode.filled, 'Filled'),
          buildButton(BasketMode.empty, 'Empty'),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard('BASKETS', _totalBaskets.toString(), AppColors.textPrimary, true),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('FORMERS', _totalFormers.toString(), AppColors.primary, true),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'RACK',
            _racks.length.toString().padLeft(1, '0'),
            const Color(0xFFE11D48),
            false,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, bool isClickableForItems) {
    final isRack = label == 'RACK';
    
    return GestureDetector(
      onTap: isRack
          ? () {
              RackDetailModal.show(context: context, racks: _racks);
            }
          : isClickableForItems
              ? _showScannedItemsModal
              : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRack ? const Color(0xFFFFF1F2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRack ? const Color(0xFFFFE4E6) : AppColors.slate100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isRack ? const Color(0xFFE11D48) : AppColors.textSecondary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (isClickableForItems && _scannedItemsMap.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.visibility, size: 12, color: color.withOpacity(0.6)),
                ],
              ],
            ),
            const SizedBox(height: 4),
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

  Widget _buildRFIDScannerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RFID POWER',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${rfidPower.round()}',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'dBm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sensors, color: AppColors.primary, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getScannerStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getScannerStatusColor().withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getScannerStatusColor(),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _getScannerStatusColor().withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SCANNER STATUS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getScannerStatusText(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _getScannerStatusColor(),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (scannerStatus == ScannerStatus.scanning)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getScannerStatusColor(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() => rfidPower = (rfidPower - 1).clamp(0, 50));
                      },
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 6,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.slate200,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 14,
                            elevation: 4,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                          overlayColor: AppColors.primary.withOpacity(0.1),
                        ),
                        child: Slider(
                          value: rfidPower,
                          min: 0,
                          max: 50,
                          onChanged: (value) => setState(() => rfidPower = value),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() => rfidPower = (rfidPower + 1).clamp(0, 50));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.slate100)),
            ),
            child: Row(
              children: [
                _buildScanButton(Icons.play_circle, 'START', AppColors.success, _startScanning),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.pause_circle, 'STOP', AppColors.textTertiary, _stopScanning),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.refresh, 'CLEAR', const Color(0xFFE11D48), _clearScannedItems),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCANNING IN PROGRESS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_scannedItemsMap.length} items scanned • Tap stats to view',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getScannerStatusColor() {
    switch (scannerStatus) {
      case ScannerStatus.disconnected:
        return AppColors.error;
      case ScannerStatus.initializing:
        return AppColors.warning;
      case ScannerStatus.initialized:
        return AppColors.info;
      case ScannerStatus.connected:
        return AppColors.success;
      case ScannerStatus.scanning:
        return AppColors.primary;
      case ScannerStatus.stopped:
        return AppColors.textSecondary;
    }
  }

  String _getScannerStatusText() {
    switch (scannerStatus) {
      case ScannerStatus.disconnected:
        return 'DISCONNECTED';
      case ScannerStatus.initializing:
        return 'INITIALIZING...';
      case ScannerStatus.initialized:
        return 'INITIALIZED';
      case ScannerStatus.connected:
        return 'CONNECTED';
      case ScannerStatus.scanning:
        return 'SCANNING...';
      case ScannerStatus.stopped:
        return 'STOPPED';
    }
  }

  Widget buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        border: const Border(top: BorderSide(color: AppColors.slate200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _addCurrentScannedToRack,
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.slate100,
                  foregroundColor: AppColors.slate700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _allRackTagIds.isEmpty
                    ? null
                    : () async {
                        final confirm = await AppModal.showConfirm(
                          context: context,
                          title: 'Save All Items',
                          message: 'Save ${_allRackTagIds.length} scanned items?',
                        );

                        if (confirm == true) {
                          widget.onScanComplete?.call();
                          AppModal.showSuccess(
                            context: context,
                            title: 'Saved',
                            message: '${_allRackTagIds.length} items saved successfully',
                          );
                        }
                      },
                icon: const Icon(Icons.save, size: 20),
                label: const Text(
                  'SAVE ALL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: AppColors.primary.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  disabledBackgroundColor: AppColors.slate200,
                  disabledForegroundColor: AppColors.slate700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final canExit = await handleExit();
                  if (canExit && mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF1F2),
                  foregroundColor: const Color(0xFFE11D48),
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Icon(Icons.close, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}