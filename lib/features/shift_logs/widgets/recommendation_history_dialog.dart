import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/dashboard/services/work_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecommendationHistoryDialog extends StatefulWidget {
  final String workSessionId;
  final String sessionLabel;

  const RecommendationHistoryDialog({
    super.key,
    required this.workSessionId,
    required this.sessionLabel,
  });

  @override
  State<RecommendationHistoryDialog> createState() => _RecommendationHistoryDialogState();
}

class _RecommendationHistoryDialogState extends State<RecommendationHistoryDialog> {
  final WorkService _workService = WorkService();
  bool _isLoading = true;
  String? _error;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final result = await _workService.getSessionRecommendations(token, widget.workSessionId);
      if (!mounted) return;
      final List<dynamic> items = List<dynamic>.from(result['items'] ?? []);
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load recommendations: $e';
        _isLoading = false;
      });
    }
  }

  String _formatType(String? raw) {
    if (raw == null || raw.isEmpty) return 'Recommendation';
    final upper = raw.toUpperCase();
    switch (upper) {
      case 'SHORT_BREAK':
        return 'Short Break';
      case 'LONG_BREAK':
      case 'BREAK_1':
        return 'Break 1';
      case 'BREAK_2':
        return 'Break 2';
      case 'WALK':
        return 'Walk';
      case 'HYDRATE':
        return 'Hydrate';
      case 'STRETCH':
        return 'Stretch';
      case 'LUNCH':
        return 'Lunch';
      case 'COACH_BREAK':
        return 'Coach Break';
      default:
        return upper
            .replaceAll('_', ' ')
            .toLowerCase()
            .split(' ')
            .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
            .join(' ');
    }
  }

  IconData _getIcon(String? raw) {
    final upper = (raw ?? '').toUpperCase();
    if (upper.contains('LUNCH')) return Icons.lunch_dining_outlined;
    if (upper.contains('WALK')) return Icons.directions_walk_outlined;
    if (upper.contains('HYDRATE')) return Icons.water_drop_outlined;
    if (upper.contains('STRETCH')) return Icons.self_improvement_outlined;
    return Icons.psychology_alt_outlined;
  }

  Widget _buildStatusBadge(BuildContext context, String? action) {
    final status = (action ?? 'PENDING').toLowerCase();
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'accepted':
        bg = DesignSystem.getSemanticColor(context, SemanticColor.success).withValues(alpha: 0.12);
        fg = DesignSystem.getSemanticColor(context, SemanticColor.success);
        label = 'Accepted';
        break;
      case 'dismissed':
        bg = DesignSystem.getSemanticColor(context, SemanticColor.error).withValues(alpha: 0.12);
        fg = DesignSystem.getSemanticColor(context, SemanticColor.error);
        label = 'Dismissed';
        break;
      case 'expired':
        bg = DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.12);
        fg = DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant);
        label = 'Expired';
        break;
      case 'pending':
      default:
        bg = DesignSystem.getSemanticColor(context, SemanticColor.info).withValues(alpha: 0.12);
        fg = DesignSystem.getSemanticColor(context, SemanticColor.info);
        label = 'Pending';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final maxDialogWidth = isDesktop ? 680.0 : double.infinity;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.surface),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 24,
                      color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommendation History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.sessionLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Session ID metadata row with copy
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 14,
                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Session ID: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.workSessionId,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.workSessionId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Session ID copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Content Area
              Flexible(
                child: _isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 36,
                                    color: DesignSystem.getSemanticColor(context, SemanticColor.error),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: DesignSystem.getSemanticColor(context, SemanticColor.error),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _load,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.notifications_none_rounded,
                                        size: 40,
                                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No recommendations recorded for this session.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _items.length,
                                separatorBuilder: (context, _) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = _items[index] as Map<dynamic, dynamic>;
                                  final rawType = item['recommendation_type']?.toString();
                                  final title = _formatType(rawType);
                                  final reason = item['reason']?.toString();
                                  final userAction = item['user_action']?.toString();
                                  final modelVersion = item['model_version']?.toString() ?? item['source']?.toString();
                                  final duration = item['session_duration_minutes'] ?? item['duration_minutes'];
                                  final taskCount = item['task_count'];

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant).withValues(alpha: 0.1),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: DesignSystem.getSemanticColor(context, SemanticColor.primary).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Icon(
                                                _getIcon(rawType),
                                                size: 16,
                                                color: DesignSystem.getSemanticColor(context, SemanticColor.primary),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: DesignSystem.getSemanticColor(context, SemanticColor.onSurface),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStatusBadge(context, userAction),
                                          ],
                                        ),
                                        if (reason != null && reason.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            reason,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.4,
                                              color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                            ),
                                          ),
                                        ],
                                        if (modelVersion != null || duration != null || taskCount != null) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 4,
                                            children: [
                                              if (modelVersion != null && modelVersion.isNotEmpty)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.psychology, size: 12, color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Model: $modelVersion',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (duration != null)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.timer_outlined, size: 12, color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Session: ${duration}m',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (taskCount != null)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.task_alt, size: 12, color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Tasks: $taskCount',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: DesignSystem.getSemanticColor(context, SemanticColor.onSurfaceVariant),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
