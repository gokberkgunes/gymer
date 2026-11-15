part of '../settings.dart';

class _DataSettings extends StatelessWidget {
  const _DataSettings();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Page(
      title: 'Data',
      children: [
        const SizedBox(height: 8),
        _group([
          _row(
            context,
            'Automatic backups',
            Icon(Icons.history_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Last 3 days, 4 weeks and 6 months',
            onTap: () => openAutoBackups(context),
          ),
        ]),
        const SizedBox(height: 12),
        _group([
          _row(
            context,
            'Export backup',
            Icon(Icons.upload_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Everything as one JSON file',
            onTap: () => exportBackup(context),
          ),
          _row(
            context,
            'Export sets as CSV',
            Icon(Icons.table_rows_outlined, color: cs.onSurfaceVariant),
            subtitle: 'Every logged set, for spreadsheets; not a backup',
            onTap: () => exportCsv(context),
          ),
          _row(
            context,
            'Restore backup',
            Icon(Icons.restore_rounded, color: cs.onSurfaceVariant),
            subtitle: 'Replace all data from a JSON backup',
            onTap: () => restoreBackup(context),
          ),
        ]),
      ],
    );
  }
}
