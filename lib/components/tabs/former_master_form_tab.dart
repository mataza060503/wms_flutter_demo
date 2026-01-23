import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';
import '../forms/form_section_card.dart';
import '../forms/form_text_field.dart';
import '../forms/form_dropdown_field.dart';
import '../forms/form_date_field.dart';

class FormerMasterFormTab extends StatefulWidget {
  final TextEditingController dnController;
  final TextEditingController itemNoController;
  final TextEditingController usedDayController;
  final TextEditingController purchQtyController;
  final TextEditingController aqlController;
  final TextEditingController batchNoController;
  final TextEditingController lengthController;
  final DateTime dataDate;
  final String selectedBrand;
  final String selectedType;
  final String selectedSurface;
  final String selectedSize;
  final ValueChanged<DateTime> onDataDateChanged;
  final ValueChanged<String> onBrandChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onSurfaceChanged;
  final ValueChanged<String> onSizeChanged;

  const FormerMasterFormTab({
    Key? key,
    required this.dnController,
    required this.itemNoController,
    required this.usedDayController,
    required this.purchQtyController,
    required this.aqlController,
    required this.batchNoController,
    required this.lengthController,
    required this.dataDate,
    required this.selectedBrand,
    required this.selectedType,
    required this.selectedSurface,
    required this.selectedSize,
    required this.onDataDateChanged,
    required this.onBrandChanged,
    required this.onTypeChanged,
    required this.onSurfaceChanged,
    required this.onSizeChanged,
  }) : super(key: key);

  @override
  State<FormerMasterFormTab> createState() => _FormerMasterFormTabState();
}

class _FormerMasterFormTabState extends State<FormerMasterFormTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Identification Section
          FormSectionCard(
            icon: Icons.tag,
            title: 'IDENTIFICATION',
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormTextField(
                      label: 'DN',
                      required: true,
                      controller: widget.dnController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormTextField(
                      label: 'ITEM NO',
                      required: true,
                      controller: widget.itemNoController,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.primary),
                        onPressed: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Tracking & Qty Section
          FormSectionCard(
            icon: Icons.analytics,
            title: 'TRACKING & QTY',
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormTextField(
                      label: 'USED DAY',
                      required: true,
                      keyboardType: TextInputType.number,
                      controller: widget.usedDayController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormTextField(
                      label: 'PURCH. QTY',
                      required: true,
                      keyboardType: TextInputType.number,
                      controller: widget.purchQtyController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FormDateField(
                label: 'DATA DATE',
                required: true,
                value: widget.dataDate,
                onChanged: widget.onDataDateChanged,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Specifications Section
          FormSectionCard(
            icon: Icons.settings_input_component,
            title: 'SPECIFICATIONS',
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormDropdownField<String>(
                      label: 'BRAND',
                      required: true,
                      value: widget.selectedBrand,
                      items: const ['Shinko', 'Brand B'],
                      itemLabel: (item) => item,
                      onChanged: (value) => widget.onBrandChanged(value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormDropdownField<String>(
                      label: 'TYPE',
                      required: true,
                      value: widget.selectedType,
                      items: const ['Ceramic', 'Latex'],
                      itemLabel: (item) => item,
                      onChanged: (value) => widget.onTypeChanged(value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FormDropdownField<String>(
                label: 'SURFACE',
                required: true,
                value: widget.selectedSurface,
                items: const ['Standard Fine Surface', 'Rough Surface'],
                itemLabel: (item) => item,
                onChanged: (value) => widget.onSurfaceChanged(value!),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: FormDropdownField<String>(
                            label: 'SIZE',
                            required: true,
                            value: widget.selectedSize,
                            items: const ['S', 'M', 'L', 'XL'],
                            itemLabel: (item) => item,
                            onChanged: (value) => widget.onSizeChanged(value!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          margin: const EdgeInsets.only(top: 22),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.slate100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: AppColors.textSecondary),
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: FormTextField(
                            label: 'LENGTH',
                            required: true,
                            keyboardType: TextInputType.number,
                            controller: widget.lengthController,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          margin: const EdgeInsets.only(top: 22),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.slate100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.add, color: AppColors.textSecondary),
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Quality & Batch Section
          FormSectionCard(
            icon: Icons.verified,
            title: 'QUALITY & BATCH',
            children: [
              FormTextField(
                label: 'AQL LEVEL',
                required: true,
                keyboardType: TextInputType.number,
                controller: widget.aqlController,
              ),
              const SizedBox(height: 12),
              FormTextField(
                label: 'BATCH NUMBER',
                required: true,
                placeholder: 'Enter Batch No',
                controller: widget.batchNoController,
              ),
            ],
          ),
        ],
      ),
    );
  }
}