import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/constants/app_colors.dart';
import './basket_detail_modal.dart';
import './bin_location_modal.dart';
import './app_modal.dart';
import 'package:wms_flutter/services/api_service.dart';
import 'package:wms_flutter/models/scanned_item.dart';

class RfidScannedItemsModal extends StatefulWidget {
  final Map<String, ScannedItem> scannedItemsMap;
  final Function(ScannedItem, String) onBinLocationChanged;

  const RfidScannedItemsModal({
    Key? key,
    required this.scannedItemsMap,
    required this.onBinLocationChanged,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required Map<String, ScannedItem> scannedItemsMap,
    required Function(ScannedItem, String) onBinLocationChanged,
  }) async {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RfidScannedItemsModal(
        scannedItemsMap: scannedItemsMap,
        onBinLocationChanged: onBinLocationChanged,
      ),
    );
  }

  @override
  State<RfidScannedItemsModal> createState() => _RfidScannedItemsModalState();
}

class _RfidScannedItemsModalState extends State<RfidScannedItemsModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Pagination
  final int _itemsPerPage = 20;
  int _currentSuccessPage = 0;
  int _currentErrorPage = 0;

  bool _isDownloading = false;

  List<ScannedItem> get allItems => widget.scannedItemsMap.values.toList();

  List<ScannedItem> get successItems => allItems
      .where((item) => item.status == ItemStatus.success)
      .toList();

  List<ScannedItem> get errorItems => allItems
      .where((item) =>
  item.status == ItemStatus.error ||
      item.status == ItemStatus.duplicate)
      .toList();

  List<ScannedItem> get pendingItems => allItems
      .where((item) => item.status == ItemStatus.pending)
      .toList();

  // Paginated lists
  List<ScannedItem> get paginatedSuccessItems {
    final startIndex = _currentSuccessPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, successItems.length);
    if (startIndex >= successItems.length) return [];
    return successItems.sublist(startIndex, endIndex);
  }

  List<ScannedItem> get paginatedErrorItems {
    final startIndex = _currentErrorPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, errorItems.length);
    if (startIndex >= errorItems.length) return [];
    return errorItems.sublist(startIndex, endIndex);
  }

  int get successTotalPages => (successItems.length / _itemsPerPage).ceil();
  int get errorTotalPages => (errorItems.length / _itemsPerPage).ceil();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _downloadTagIds() async {
    if (allItems.isEmpty) {
      AppModal.showWarning(
        context: context,
        title: 'No Data',
        message: 'No scanned items to download',
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      // 1. Generate content Buffer
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'scanned_tags_$timestamp.txt';

      final buffer = StringBuffer();
      buffer.writeln('Scanned Tag IDs Report');
      buffer.writeln('Generated: ${DateTime.now().toString()}');
      buffer.writeln('Total Items: ${allItems.length}');
      buffer.writeln('Success: ${successItems.length}');
      buffer.writeln('Errors: ${errorItems.length}');
      buffer.writeln('Pending: ${pendingItems.length}');
      buffer.writeln('');
      buffer.writeln('=' * 50);
      buffer.writeln('');

      if (successItems.isNotEmpty) {
        buffer.writeln('SUCCESS ITEMS (${successItems.length}):');
        buffer.writeln('-' * 50);
        for (var item in successItems) {
          buffer.writeln('Tag ID: ${item.id}');
          buffer.writeln('  Quantity: ${item.quantity}');
          if (item.vendor.isNotEmpty) buffer.writeln('  Vendor: ${item.vendor}');
          if (item.bin.isNotEmpty) buffer.writeln('  Bin: ${item.bin}');
          buffer.writeln('');
        }
      }

      if (errorItems.isNotEmpty) {
        buffer.writeln('ERROR ITEMS (${errorItems.length}):');
        buffer.writeln('-' * 50);
        for (var item in errorItems) {
          buffer.writeln('Tag ID: ${item.id}');
          buffer.writeln('  Status: ${item.status.toString()}');
          if (item.errorMessage != null) buffer.writeln('  Error: ${item.errorMessage}');
          buffer.writeln('');
        }
      }

      buffer.writeln('=' * 50);
      buffer.writeln('End of Report');

      Directory? directory;

      if (Platform.isAndroid) {
        // Direct path to the public Downloads folder
        directory = Directory('/storage/emulated/0/Download');

        // Safety check: if the path doesn't exist, fallback to external storage
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      final String filePath = '${directory!.path}/$fileName';
      final File file = File(filePath);

      // Write with flush: true to ensure the OS finishes the write operation
      await file.writeAsString(buffer.toString(), flush: true);

      // 4. Double Check: Ensure file has size before sharing
      final stat = await file.stat();
      if (stat.size == 0) {
        throw Exception("File verification failed: Size is 0 bytes");
      }

      setState(() => _isDownloading = false);

      // 5. Share with Explicit MIME Type
      // Helps apps (like Google Drive or Gmail) know how to handle the file
      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'text/plain')],
        subject: 'Scanned Tag IDs Report',
        text: 'Report generated with ${allItems.length} scanned items',
      );

      if (mounted) {
        AppModal.showSuccess(
          context: context,
          title: 'Ready',
          message: 'Choose "Save to Files" or Email to export.',
        );
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      if (mounted) {
        AppModal.showError(
          context: context,
          title: 'Export Failed',
          message: 'Error: ${e.toString()}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSuccessTab(scrollController),
                    _buildErrorTab(scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final totalBaskets = successItems.length;
    final totalFormers =
    allItems.fold<int>(0, (sum, item) => sum + item.quantity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: AppColors.slate200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.slate300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          /// Title and Download Button
          Row(
            children: [
              const Text(
                'SCANNED ITEMS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _isDownloading
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
                  : IconButton(
                icon: const Icon(Icons.download, size: 20),
                onPressed: _downloadTagIds,
                tooltip: 'Download Tag IDs',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          /// Stats Row
          Row(
            children: [
              Expanded(
                child: _buildMiniStatChip(
                  'BASKETS',
                  totalBaskets.toString(),
                  AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStatChip(
                  'FORMERS',
                  totalFormers.toString(),
                  AppColors.primary,
                ),
              ),
              if (errorItems.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniStatChip(
                    'ERRORS',
                    errorItems.length.toString(),
                    AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: color.withOpacity(0.8),
              letterSpacing: 0.5,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        dividerColor: AppColors.slate200,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: 8),
                Text('SUCCESS (${successItems.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 18),
                const SizedBox(width: 8),
                Text('ERRORS (${errorItems.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessTab(ScrollController scrollController) {
    if (successItems.isEmpty && pendingItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'No successful scans yet',
        subtitle: 'Scanned items will appear here',
      );
    }

    return Column(
      children: [
        if (pendingItems.isNotEmpty) _buildPendingBanner(),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: paginatedSuccessItems.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildScannedItemCard(paginatedSuccessItems[index]),
              );
            },
          ),
        ),
        if (successTotalPages > 1) _buildPagination(true),
      ],
    );
  }

  Widget _buildErrorTab(ScrollController scrollController) {
    if (errorItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.sentiment_satisfied,
        title: 'No errors found',
        subtitle: 'All scanned items are successful',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: paginatedErrorItems.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildScannedItemCard(paginatedErrorItems[index]),
              );
            },
          ),
        ),
        if (errorTotalPages > 1) _buildPagination(false),
      ],
    );
  }

  Widget _buildPendingBanner() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.info),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${pendingItems.length} item${pendingItems.length > 1 ? 's' : ''} loading...',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.info,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(bool isSuccessTab) {
    final currentPage = isSuccessTab ? _currentSuccessPage : _currentErrorPage;
    final totalPages = isSuccessTab ? successTotalPages : errorTotalPages;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.slate200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton.icon(
            onPressed: currentPage > 0
                ? () {
              setState(() {
                if (isSuccessTab) {
                  _currentSuccessPage--;
                } else {
                  _currentErrorPage--;
                }
              });
            }
                : null,
            icon: const Icon(Icons.chevron_left, size: 20),
            label: const Text('PREV'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.slate100,
              foregroundColor: AppColors.textPrimary,
              disabledBackgroundColor: AppColors.slate50,
              disabledForegroundColor: AppColors.slate300,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Page ${currentPage + 1} of $totalPages',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),

          ElevatedButton.icon(
            onPressed: currentPage < totalPages - 1
                ? () {
              setState(() {
                if (isSuccessTab) {
                  _currentSuccessPage++;
                } else {
                  _currentErrorPage++;
                }
              });
            }
                : null,
            icon: const Icon(Icons.chevron_right, size: 20),
            label: const Text('NEXT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.slate100,
              foregroundColor: AppColors.textPrimary,
              disabledBackgroundColor: AppColors.slate50,
              disabledForegroundColor: AppColors.slate300,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: AppColors.textTertiary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedItemCard(ScannedItem item) {
    Color qtyBgColor;
    Color qtyTextColor;
    Color statusBgColor;
    Color statusTextColor;
    String statusLabel;
    Color borderColor;

    switch (item.status) {
      case ItemStatus.success:
        qtyBgColor = const Color(0xFFECFDF5);
        qtyTextColor = const Color(0xFF059669);
        statusBgColor = const Color(0xFFD1FAE5);
        statusTextColor = const Color(0xFF047857);
        statusLabel = 'SUCCESS';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.duplicate:
        qtyBgColor = const Color(0xFFFEF3C7);
        qtyTextColor = const Color(0xFFD97706);
        statusBgColor = const Color(0xFFFDE68A);
        statusTextColor = const Color(0xFFB45309);
        statusLabel = 'DUPLICATE';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.pending:
        qtyBgColor = const Color(0xFFE0E7FF);
        qtyTextColor = const Color(0xFF4F46E5);
        statusBgColor = const Color(0xFFDDD6FE);
        statusTextColor = const Color(0xFF6366F1);
        statusLabel = 'LOADING...';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.error:
        qtyBgColor = const Color(0xFFFEE2E2);
        qtyTextColor = const Color(0xFFDC2626);
        statusBgColor = const Color(0xFFFECDD3);
        statusTextColor = const Color(0xFFBE123C);
        statusLabel = 'ERROR';
        borderColor = const Color(0xFFFFE4E6);
        break;
    }

    return GestureDetector(
      onTap: item.status == ItemStatus.success
          ? () => _showItemDetails(item)
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: qtyBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'QTY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: qtyTextColor,
                        ),
                      ),
                      Text(
                        '${item.quantity}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: qtyTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.id,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (item.status == ItemStatus.success &&
                          item.vendor.isNotEmpty)
                        Text(
                          'Vendor: ${item.vendor}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.status == ItemStatus.error)
                        Text(
                          item.errorMessage ?? 'Unknown error',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.status == ItemStatus.pending)
                          const Text(
                            'Fetching basket data...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else if (item.status == ItemStatus.duplicate)
                            const Text(
                              'Already scanned',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD97706),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    ],
                  ),
                ),
                if (item.basketData != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ],
              ],
            ),
            if (item.status == ItemStatus.success && item.bin.isNotEmpty)
              Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slate200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warehouse,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BIN LOCATION',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.bin,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showBinLocationSelector(item),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'CHANGE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if (item.status == ItemStatus.success)
              Column(
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showBinLocationSelector(item),
                      icon: const Icon(Icons.warehouse, size: 18),
                      label: const Text(
                        'SELECT BIN LOCATION',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showItemDetails(ScannedItem item) {
    if (item.basketData != null) {
      BasketDetailModal.show(context: context, basketData: item.basketData!);
    } else {
      AppModal.showError(
        context: context,
        title: 'No Data',
        message: 'No basket data available for this item',
      );
    }
  }

  Future<void> _showBinLocationSelector(ScannedItem item) async {
    final selectedBin = await BinLocationModal.show(
      context: context,
      currentBin: item.bin,
    );

    if (selectedBin != null) {
      widget.onBinLocationChanged(item, selectedBin);
      setState(() {
        item.bin = selectedBin;
      });

      if (mounted) {
        AppModal.showSuccess(
          context: context,
          title: 'Bin Updated',
          message: 'Bin location set to $selectedBin',
        );
      }
    }
  }
}