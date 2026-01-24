import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';
import '../../screens/former_stock_in_screen.dart';
import 'package:wms_flutter/models/scanned_item.dart';

class RackDetailModal {
  static Future<void> show({
    required BuildContext context,
    required List<Rack> racks,
    ValueChanged<List<Rack>> ? onChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) {
          return _RackDetailContent(
            racks: racks,
            scrollController: controller,
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}

class _RackDetailContent extends StatefulWidget {
  final List<Rack> racks;
  final ScrollController scrollController;
  final ValueChanged<List<Rack>>? onChanged;

  const _RackDetailContent({
    required this.racks,
    required this.scrollController,
    this.onChanged,
  });

  @override
  State<_RackDetailContent> createState() => _RackDetailContentState();
}

class _RackDetailContentState extends State<_RackDetailContent> {
  late List<Rack> _racks;
  final Map<int, String> _searchKeywords = {};

  @override
  void initState() {
    super.initState();
    _racks = List.from(widget.racks);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _racks.length,
              itemBuilder: (context, index) {
                return _buildRackCard(_racks[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveRack(Rack rack) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
        title: const Text('Remove Rack'),
        content: Text(
            'Are you sure you want to remove Rack ${rack.rackNo.toString().padLeft(2, '0')}?',
        ),
        actions: [
            TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
            ),
            ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
            ),
        ],
        ),
    );

    if (confirmed == true) {
        setState(() {
        _racks.remove(rack);
        _searchKeywords.remove(rack.rackNo);
        });

        widget.onChanged?.call(List.from(_racks));
    }
  }

    Widget _buildHeader(BuildContext context) {
        final totalItems =
            _racks.fold<int>(0, (s, r) => s + r.items.length);

        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
            children: [
                Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.slate300,
                    borderRadius: BorderRadius.circular(4),
                ),
                ),
                const SizedBox(height: 12),
                Row(
                children: [
                    const Text(
                    'RACK DETAILS',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                    ),
                    ),
                    const Spacer(),
                    IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    ),
                ],
                ),
                Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '${_racks.length} racks • $totalItems items',
                    style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    ),
                ),
                ),
            ],
            ),
        );
    }

    Widget _buildRackCard(Rack rack) {
        final keyword = _searchKeywords[rack.rackNo] ?? '';
        final filteredItems = rack.items
            .where((i) => i.id.toLowerCase().contains(keyword.toLowerCase()))
            .toList();

        bool _expanded = false;

        return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.slate200),
            ),
            child: Theme(
            data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
                onExpansionChanged: (v) {
                    setState(() => _expanded = v);
                },
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                childrenPadding: EdgeInsets.zero,

                title: Text(
                    'Rack ${rack.rackNo.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    ),
                ),

                subtitle: Text(
                    '${rack.items.length} items',
                    style: const TextStyle(fontSize: 12),
                ),

                trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: AppColors.error,
                        tooltip: 'Remove rack',
                        onPressed: () => _confirmRemoveRack(rack),
                    ),
                    AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more),
                    ),
                    ],
                ),

                children: [
                    _buildSearch(rack),
                    const SizedBox(height: 8),
                    _buildItemTableHeader(),
                    ...filteredItems.map(_buildItemRow),
                    const SizedBox(height: 12),
                ],
                ),
            ),
        );
    }

    Widget _buildSearch(Rack rack) {
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
            decoration: InputDecoration(
                hintText: 'Search tag ID...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
                ),
            ),
            onChanged: (value) {
                setState(() {
                _searchKeywords[rack.rackNo] = value;
                });
            },
            ),
        );
    }

    Widget _buildItemTableHeader() {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
            children: const [
                Expanded(
                flex: 4,
                child: Text(
                    'TAG ID',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                ),
                Expanded(
                flex: 1,
                child: Text(
                    'QTY',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                ),
            ],
            ),
        );
    }

    Widget _buildItemRow(ScannedItem item) {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
            children: [
                Expanded(
                flex: 4,
                child: Text(
                    item.id,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                ),
                ),
                Expanded(
                flex: 1,
                child: Text(
                    item.quantity.toString(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    ),
                ),
                ),
            ],
            ),
        );
    }
}
