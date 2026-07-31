import 'dart:math' as math;

import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

const grintaTableMinWidth = 620.0;
const grintaTablePinnedWidth = 168.0;
const grintaTableHeaderFontSize = 11.5;
const grintaTableCellFontSize = 13.5;
const grintaTableRankFontSize = 12.5;
const grintaTablePinnedHeaderPadding = EdgeInsets.fromLTRB(16, 12, 8, 12);
const grintaTableScrollableHeaderPadding = EdgeInsets.fromLTRB(8, 12, 16, 12);
const grintaTablePinnedRowPadding = EdgeInsets.fromLTRB(16, 17, 8, 17);
const grintaTableScrollableRowPadding = EdgeInsets.fromLTRB(8, 17, 16, 17);

TextStyle grintaTableHeaderTextStyle(BuildContext context, {Color? color}) {
  return TextStyle(
    color: color ?? AppTheme.textSecondary,
    fontSize: grintaTableHeaderFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: .55,
    height: 1,
  );
}

TextStyle grintaTableCellTextStyle(
  BuildContext context, {
  Color? color,
  FontWeight fontWeight = FontWeight.w700,
}) {
  return TextStyle(
    color: color ?? Theme.of(context).colorScheme.onSurface,
    fontSize: grintaTableCellFontSize,
    fontWeight: fontWeight,
    height: 1.15,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

TextStyle grintaTableRankTextStyle(BuildContext context, {Color? color}) {
  return TextStyle(
    color: color ?? AppTheme.textFaint,
    fontSize: grintaTableRankFontSize,
    fontWeight: FontWeight.w900,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Une ligne du tableau, scindée entre la cellule figée (rang + nom), qui
/// reste toujours visible à gauche, et les cellules de stats qui défilent
/// horizontalement avec l'en-tête.
class StickyTableRow {
  const StickyTableRow({required this.pinned, required this.scrollable});

  final Widget pinned;
  final Widget scrollable;
}

/// Synchronise plusieurs [ScrollController] horizontaux entre eux : glisser
/// l'un d'eux fait défiler tous les autres du même mouvement. Nécessaire ici
/// car l'en-tête et chaque ligne ont leur propre zone de défilement (pour
/// que la colonne figée n'en fasse pas partie), mais doivent bouger ensemble.
class _ScrollLinkGroup {
  double _offset = 0;
  final Set<ScrollController> _controllers = {};
  bool _isSyncing = false;

  ScrollController createController() {
    final controller = ScrollController(initialScrollOffset: _offset);
    controller.addListener(() => _handleScroll(controller));
    _controllers.add(controller);
    return controller;
  }

  void disposeController(ScrollController controller) {
    _controllers.remove(controller);
    controller.dispose();
  }

  void _handleScroll(ScrollController source) {
    if (_isSyncing || !source.hasClients) return;
    _offset = source.offset;
    _isSyncing = true;
    for (final controller in _controllers) {
      if (controller != source &&
          controller.hasClients &&
          controller.offset != _offset) {
        controller.jumpTo(_offset);
      }
    }
    _isSyncing = false;
  }
}

/// Cartouche de tableau dont la ligne d'en-tête reste fixe en haut pendant que
/// les lignes défilent en dessous, et dont la colonne "Joueur" reste figée à
/// gauche pendant que les colonnes de stats défilent horizontalement.
/// Occupe toute la hauteur disponible : à placer dans un parent à hauteur
/// bornée (Expanded, SizedBox…).
class StickyHeaderTableCard extends StatefulWidget {
  const StickyHeaderTableCard({
    required this.pinnedHeader,
    required this.scrollableHeader,
    required this.rows,
    this.onRefresh,
    this.minWidth = grintaTableMinWidth,
    this.pinnedWidth = grintaTablePinnedWidth,
    super.key,
  });

  final Widget pinnedHeader;
  final Widget scrollableHeader;
  final List<StickyTableRow> rows;
  final Future<void> Function()? onRefresh;
  final double minWidth;
  final double pinnedWidth;

  @override
  State<StickyHeaderTableCard> createState() => _StickyHeaderTableCardState();
}

class _StickyHeaderTableCardState extends State<StickyHeaderTableCard> {
  final _ScrollLinkGroup _group = _ScrollLinkGroup();
  late final ScrollController _headerController = _group.createController();

  @override
  void dispose() {
    _group.disposeController(_headerController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.outline.withValues(alpha: .24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            0.0,
            math.max(constraints.maxWidth, widget.minWidth) -
                widget.pinnedWidth,
          );

          Widget list = ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 6),
            itemCount: widget.rows.length,
            itemBuilder: (context, index) {
              final row = widget.rows[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: index.isEven
                      ? Colors.transparent
                      : AppTheme.surfaceHigh.withValues(alpha: .10),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.outline.withValues(alpha: .16),
                    ),
                  ),
                ),
                child: _PinnedScrollableRow(
                  pinnedWidth: widget.pinnedWidth,
                  contentWidth: contentWidth,
                  group: _group,
                  pinned: row.pinned,
                  scrollable: row.scrollable,
                ),
              );
            },
          );
          if (widget.onRefresh != null) {
            list = RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
          }

          return SizedBox(
            height: constraints.maxHeight,
            child: Column(
              children: [
                ColoredBox(
                  color: AppTheme.surfaceHigh,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: widget.pinnedWidth,
                          child: widget.pinnedHeader,
                        ),
                        Container(
                          width: 1,
                          color: AppTheme.outline.withValues(alpha: .22),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            controller: _headerController,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: contentWidth,
                              child: widget.scrollableHeader,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppTheme.outline.withValues(alpha: .22),
                ),
                Expanded(child: list),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PinnedScrollableRow extends StatefulWidget {
  const _PinnedScrollableRow({
    required this.pinnedWidth,
    required this.contentWidth,
    required this.group,
    required this.pinned,
    required this.scrollable,
  });

  final double pinnedWidth;
  final double contentWidth;
  final _ScrollLinkGroup group;
  final Widget pinned;
  final Widget scrollable;

  @override
  State<_PinnedScrollableRow> createState() => _PinnedScrollableRowState();
}

class _PinnedScrollableRowState extends State<_PinnedScrollableRow> {
  late final ScrollController _controller = widget.group.createController();

  @override
  void dispose() {
    widget.group.disposeController(_controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: widget.pinnedWidth, child: widget.pinned),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _controller,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: widget.contentWidth,
                child: widget.scrollable,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cellule d'en-tête cliquable : un appui trie le tableau selon cette colonne
/// (et inverse le sens si la colonne est déjà active). Une flèche ↑/↓ indique
/// la colonne et le sens de tri courants. Sans [flex], la cellule prend toute
/// la place de son parent (utile pour la colonne figée, hors d'un Row à
/// flex) ; avec [flex], elle se comporte comme un `Expanded` classique.
class SortableHeaderCell extends StatelessWidget {
  const SortableHeaderCell({
    required this.label,
    required this.active,
    required this.descending,
    required this.onTap,
    this.flex,
    this.align = TextAlign.center,
    this.style,
    super.key,
  });

  final String label;
  final int? flex;
  final bool active;
  final bool descending;
  final VoidCallback onTap;
  final TextAlign align;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final mainAxis = switch (align) {
      TextAlign.start || TextAlign.left => MainAxisAlignment.start,
      TextAlign.end || TextAlign.right => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

    final content = Row(
      mainAxisAlignment: mainAxis,
      children: [
        Flexible(
          child: Text(
            label,
            style: style?.copyWith(
              color: active ? AppTheme.primaryBright : style?.color,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: align,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 3),
          Icon(
            descending ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 15,
            color: AppTheme.primaryBright,
          ),
        ],
      ],
    );

    final cell = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: content,
      ),
    );

    final flexValue = flex;
    if (flexValue == null) return cell;
    return Expanded(flex: flexValue, child: cell);
  }
}
