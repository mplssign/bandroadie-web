import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

import '../models/gear_item.dart';

class GearRow extends StatelessWidget {
  final GearItem item;
  final String ownerLabel;
  final VoidCallback onTap;

  const GearRow({
    super.key,
    required this.item,
    required this.ownerLabel,
    required this.onTap,
  });

  String _priceLabel() {
    if (item.priceCents == null) return 'Price unknown';
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return fmt.format(item.priceCents! / 100);
  }

  String _dateLabel() {
    if (item.purchasedOn == null) return 'Date unknown';
    return DateFormat('MMM d, yyyy').format(item.purchasedOn!);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.space16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: AppFontSizes.title,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.space6),
                    Text(
                      ownerLabel,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: AppFontSizes.body,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.space6),
                    Text(
                      '${_priceLabel()} • ${_dateLabel()}',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: AppFontSizes.subhead,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.space8),
              Icon(
                AppIcons.forward,
                size: 18,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
