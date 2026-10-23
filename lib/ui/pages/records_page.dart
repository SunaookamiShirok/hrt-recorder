// 记录：用药记录 + 化验记录。
import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/dose_record.dart';
import '../../data/dose_store.dart';
import '../theme.dart';
import '../widgets/dose_form.dart';
import 'lab_page.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 640;
                final title = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('记录', style: Theme.of(context).textTheme.headlineSmall),
                );
                final tabs = TabBar(
                  tabAlignment: narrow ? TabAlignment.start : TabAlignment.center,
                  isScrollable: true,
                  dividerColor: Colors.transparent,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: PkTheme.text,
                  unselectedLabelColor: PkTheme.muted,
                  tabs: const [
                    Tab(text: '用药'),
                    Tab(text: '化验'),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, tabs],
                  );
                }
                return Row(
                  children: [
                    title,
                    const SizedBox(width: 8),
                    tabs,
                  ],
                );
              },
            ),
          ),          const Expanded(
            child: TabBarView(
              children: [
                DoseListTab(),
                LabPage(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DoseListTab extends StatelessWidget {
  const DoseListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([DoseStore.instance, AppSettings.instance]),
      builder: (context, _) {
        final doses = DoseStore.instance.records;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: PkTheme.accent,
            foregroundColor: Colors.white,
            onPressed: () async {
              final r = await showDoseDialog(context);
              if (r != null) await DoseStore.instance.add(r);
            },
            icon: const Icon(Icons.add),
            label: const Text('记录用药'),
          ),
          body: doses.isEmpty
              ? const Center(
                  child: Text('还没有用药记录', style: TextStyle(color: PkTheme.muted)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: doses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DoseTile(record: doses[i]),
                ),
        );
      },
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.record});

  final DoseRecord record;

  @override
  Widget build(BuildContext context) {
    final color = record.drug == 'CPA' ? PkTheme.accentAlt : PkTheme.accent;
    final d = record.takenAt;
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => DoseStore.instance.remove(record.id),
      child: InkWell(
        onTap: () async {
          final edited = await showDoseDialog(context, initial: record);
          if (edited != null) {
            await DoseStore.instance.remove(record.id);
            await DoseStore.instance.add(edited);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PkTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(record.drug,
                    style: TextStyle(fontSize: 11, color: color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.dose.toStringAsFixed(2)} mg · ${record.route}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
                      '${record.holdMinutes != null ? ' · 含服 ${record.holdMinutes!.toStringAsFixed(0)} 分钟' : ''}',
                      style: const TextStyle(fontSize: 11, color: PkTheme.muted),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }


}
