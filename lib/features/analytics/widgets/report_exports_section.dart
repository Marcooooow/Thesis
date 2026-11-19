import 'package:flutter/material.dart';

/// Reusable Report Exports Section widget sharing consistent design
/// across Employee and Manager analytics while allowing independent configuration.
class ReportExportsSection extends StatelessWidget {
  final String title;
  final String description;
  final bool isDark;
  final bool isDesktop;
  final bool isExporting;
  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;

  const ReportExportsSection({
    super.key,
    this.title = 'Report Exports',
    required this.description,
    required this.isDark,
    required this.isDesktop,
    required this.isExporting,
    required this.onExportExcel,
    required this.onExportPdf,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final exportButtons = [
      _exportButton(
        icon: Icons.table_chart_outlined,
        label: 'Excel (.xlsx)',
        color: Colors.green,
        onPressed: onExportExcel,
      ),
      _exportButton(
        icon: Icons.picture_as_pdf_outlined,
        label: 'PDF Report (.pdf)',
        color: Colors.redAccent,
        onPressed: onExportPdf,
      ),
      _exportButton(
        icon: Icons.archive_outlined,
        label: 'CSV Archive (.zip)',
        color: Colors.blueAccent,
        onPressed: onExportCsv,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1D24) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(description, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: exportButtons,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: exportButtons,
                ),
              ],
            ),
    );
  }

  Widget _exportButton({required IconData icon, required String label, required Color color, required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      onPressed: isExporting ? null : onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
