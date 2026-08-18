import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/shell/open_tabs_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'nav_items.dart';
import '../../core/auth/permissions.dart';

/// لوحة الأوامر — Ctrl+K من أي شاشة، فتكتب اسم الوحدة وتصل إليها مباشرة.
///
/// لماذا لا يكفي الشريط الجانبي: الوصول إلى «الجرد الدوري» عبر القائمة يعني
/// فتح مجموعة المخزون ثم تحديد العنصر — نقرتان وبحث بصري في كل مرة. اللوحة
/// تختصرها إلى ثلاثة أحرف دون رفع اليد عن لوحة المفاتيح، وهي المسار الذي
/// يستخدمه المستخدم المتمرّس فعلياً بعد أول أسبوع.
///
/// المطابقة على المسار أيضاً لا الاسم وحده: من يعرف النظام يكتب `pos` أسرع
/// مما يكتب «نقطة البيع» بلوحة مفاتيح عربية.
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key, required this.isPlatformAdmin});

  final bool isPlatformAdmin;

  /// يفتح اللوحة كحوار. يُستدعى من اختصار Ctrl+K في AppShell ومن زر البحث
  /// في الشريط العلوي (للمستخدم الذي لا يعرف الاختصار).
  static Future<void> show(BuildContext context, {required bool isPlatformAdmin}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => CommandPalette(isPlatformAdmin: isPlatformAdmin),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String _query = '';
  int _highlighted = 0;

  /// نفس ترشيح القائمة الجانبية — لوحة الأوامر أسرع طريق إلى أي شاشة،
  /// فتركها بلا ترشيح يجعلها الباب الخلفي إلى وحدة محجوبة.
  List<_Command> _buildCommands(UserPermissions perms) => [
        for (final group in filterByPermissions(
          navGroupsFor(isPlatformAdmin: widget.isPlatformAdmin),
          (route) {
            final required = kRoutePermissions[route];
            return required == null || perms.can(required);
          },
        ))
          for (final item in group.items) _Command(item: item, group: group.label),
      ];

  late List<_Command> _all = const [];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Command> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      return c.item.label.toLowerCase().contains(q) ||
          c.group.toLowerCase().contains(q) ||
          c.item.route.toLowerCase().contains(q);
    }).toList();
  }

  void _run(_Command c) {
    ref.read(openTabsProvider.notifier).open(c.item.route, title: c.item.label, icon: c.item.icon);
    Navigator.of(context).pop();
  }

  /// التنقّل بالأسهم داخل النتائج مع إبقاء الحقل ممسكاً بالفوكس — لو انتقل
  /// الفوكس إلى القائمة لتوقّفت الكتابة، وهي الحركة الأكثر تكراراً هنا.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final results = _results;
    if (results.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlighted = (_highlighted + 1) % results.length);
      _scrollToHighlighted();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlighted = (_highlighted - 1 + results.length) % results.length);
      _scrollToHighlighted();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _run(results[_highlighted.clamp(0, results.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToHighlighted() {
    if (!_scroll.hasClients) return;
    const rowHeight = 52.0;
    final target = (_highlighted * rowHeight).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    _all = _buildCommands(ref.perms);
    final results = _results;
    final primary = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 20, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Focus(
                          onKeyEvent: _onKey,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focus,
                            autofocus: true,
                            style: AppTextStyles.bodyLg(),
                            decoration: InputDecoration(
                              hintText: 'ابحث عن شاشة… (مثال: فواتير، جرد، pos)',
                              hintStyle: AppTextStyles.bodyMd(color: AppColors.textMuted),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (v) => setState(() {
                              _query = v;
                              _highlighted = 0;
                            }),
                          ),
                        ),
                      ),
                      const _KeyCap('Esc'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // عدد النتائج يتغيّر مع كل حرف؛ liveRegion يجعل قارئ الشاشة
                // يعلنه فوراً بدل أن يبحث المستخدم عنه يدوياً بعد كل ضغطة.
                Semantics(
                  liveRegion: true,
                  label: results.isEmpty ? 'لا توجد نتائج' : '${results.length} نتيجة',
                  child: const SizedBox.shrink(),
                ),
                Flexible(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.search_off_outlined, size: 32, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text('لا توجد شاشة مطابقة لـ «$_query»', style: AppTextStyles.bodyMd()),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final c = results[i];
                            final active = i == _highlighted;
                            return _ResultRow(
                              command: c,
                              active: active,
                              accent: primary,
                              onTap: () => _run(c),
                              onHover: () => setState(() => _highlighted = i),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const _KeyCap('↑↓'),
                      const SizedBox(width: 6),
                      Text('تنقّل', style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                      const SizedBox(width: 16),
                      const _KeyCap('Enter'),
                      const SizedBox(width: 6),
                      Text('فتح', style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                      const Spacer(),
                      Text('${results.length} شاشة',
                          style: AppTextStyles.labelMd(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Command {
  const _Command({required this.item, required this.group});
  final NavItem item;
  final String group;
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.command,
    required this.active,
    required this.accent,
    required this.onTap,
    required this.onHover,
  });

  final _Command command;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '${command.item.label}، ضمن ${command.group}',
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 52,
            padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
            color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
            child: Row(
              children: [
                Icon(command.item.icon, size: 18, color: active ? accent : AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    command.item.label,
                    style: AppTextStyles.bodyLg(color: active ? accent : AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(command.group, style: AppTextStyles.labelMd(color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// تمثيل بصري لمفتاح في لوحة المفاتيح — يجعل الاختصار قابلاً للاكتشاف بدل
/// أن يبقى معرفة شفهية يتناقلها المستخدمون.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.labelMd(color: AppColors.textMuted)),
    );
  }
}
