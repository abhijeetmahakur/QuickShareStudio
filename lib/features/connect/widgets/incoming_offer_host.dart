import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/design/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../transfer/connection_manager.dart';
import 'methods_intro.dart';
import 'transfer_widgets.dart';

/// Shows the Accept / Decline prompt for incoming files above whatever screen is open.
/// Nothing is received until the user taps Accept.
class IncomingOfferHost extends StatelessWidget {
  const IncomingOfferHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    ConnectionManager? manager;
    try {
      manager = context.watch<ConnectionManager>();
    } catch (_) {}
    final pending = manager?.pendingOffers.where((p) => !p.isDecided).firstOrNull;
    return Stack(children: [
      child,
      const Positioned.fill(child: MethodsIntroOverlay()),
      if (pending != null && manager != null) ...[
        const ModalBarrier(dismissible: false, color: Color(0x99000000)),
        Center(child: AcceptOfferCard(key: ValueKey(pending.offer.transferId), pending: pending, manager: manager)),
      ],
    ]);
  }
}

class AcceptOfferCard extends StatelessWidget {
  const AcceptOfferCard({super.key, required this.pending, required this.manager});
  final PendingOffer pending;
  final ConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    final offer = pending.offer;
    final link = pending.link;
    final files = offer.files;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'Incoming files from ${offer.sender.name}',
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            margin: const EdgeInsets.all(Space.l),
            padding: const EdgeInsets.all(Space.xl),
            decoration: cardDecoration(border: AppColors.limeGreen.withValues(alpha: 0.5)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.move_to_inbox_rounded, color: AppColors.limeGreen, size: 26),
                const SizedBox(width: Space.m),
                Expanded(child: Text('${offer.sender.name} wants to send you', style: TextStyles.title)),
              ]),
              const SizedBox(height: Space.m),
              Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                MethodBadge(link.method, relayed: link.relayed),
                VerificationCodeChip(link.verificationCode),
                if (offer.sender.platform.isNotEmpty)
                  Text(offer.sender.platform, style: TextStyles.caption),
              ]),
              const SizedBox(height: Space.l),
              Text(
                '${files.length} ${files.length == 1 ? 'file' : 'files'} · ${FormatUtils.formatBytes(offer.totalBytes)}',
                style: TextStyles.label,
              ),
              const SizedBox(height: Space.s),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in files)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Icon(Icons.insert_drive_file_outlined, size: 16, color: AppColors.secondaryText),
                          const SizedBox(width: Space.s),
                          Expanded(child: Text(f.name, style: TextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(FormatUtils.formatBytes(f.size), style: TextStyles.caption),
                        ]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.m),
              Text(
                'Check that ${offer.sender.name} shows the same verification code (${link.verificationCode}). '
                'Only accept files you expect.',
                style: TextStyles.caption,
              ),
              const SizedBox(height: Space.xl),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => manager.declineOffer(pending),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(minTapTarget),
                      foregroundColor: AppColors.primaryText,
                      side: BorderSide(color: AppColors.subtleBorderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                    ),
                    child: const Text('Decline', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: ElevatedButton(
                    autofocus: true,
                    onPressed: () => manager.acceptOffer(pending),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(minTapTarget),
                      backgroundColor: AppColors.limeGreen,
                      foregroundColor: AppColors.nearBlack,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
                    ),
                    child: const Text('Accept', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
