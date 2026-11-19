import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/admin/widgets/ml_metric_card.dart';
import 'package:intellibreak/features/admin/widgets/ml_confusion_matrix_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_performance_comparison_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_training_readiness_widget.dart';
import 'package:intellibreak/features/admin/widgets/ml_class_distribution_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_feature_importance_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_chart_empty_state.dart';
import 'package:intellibreak/features/admin/widgets/ml_recommendation_activity_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_recommendation_pipeline_stepper.dart';

class MLModelDashboardScreen extends StatefulWidget {
  const MLModelDashboardScreen({super.key});

  @override
  State<MLModelDashboardScreen> createState() => _MLModelDashboardScreenState();
}

class _MLModelDashboardScreenState extends State<MLModelDashboardScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  String? _token;
  String _selectedDataset = 'production';

  // Tab controller
  late TabController _tabController;

  // Error and data state
  String? _overviewError;
  Map<String, dynamic> _overviewData = {};
  Map<String, dynamic> _performanceData = {};
  Map<String, dynamic> _datasetData = {};
  Map<String, dynamic> _featureImportanceData = {};
  Map<String, dynamic> _comparisonData = {};
  Map<String, dynamic> _predictionInspectorData = {};
  Map<String, dynamic> _activityData = {};
  String? _selectedFeatureImportanceModelId;

  // Loading states
  bool _isLoadingOverview = true;
  bool _isLoadingPerformance = true;
  bool _isLoadingDataset = true;
  bool _isLoadingFeatureImportance = true;
  bool _isLoadingAlgorithmComparison = true;
  bool _isLoadingPredictionInspector = true;
  bool _isLoadingActivity = true;
  bool _isTrainingCandidate = false;
  bool _isRunningComparison = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final token = await _apiService.getToken();
      if (!mounted) return;
      setState(() {
        _token = token;
      });

      if (_token != null) {
        _loadAllData();
      } else {
        setState(() {
          _isLoadingOverview = false;
          _isLoadingPerformance = false;
          _isLoadingDataset = false;
          _isLoadingFeatureImportance = false;
          _isLoadingAlgorithmComparison = false;
          _isLoadingPredictionInspector = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _token = null;
        _isLoadingOverview = false;
        _isLoadingPerformance = false;
        _isLoadingDataset = false;
        _isLoadingFeatureImportance = false;
        _isLoadingAlgorithmComparison = false;
        _isLoadingPredictionInspector = false;
      });
    }
  }

  void _loadAllData() {
    if (_token == null) return;
    _loadOverview(_token!);
    _loadPerformance(_token!);
    _loadDataset(_token!);
    _loadFeatureImportance(_token!);
    _loadAlgorithmComparison(_token!);
    _loadPredictionInspector(_token!);
    _loadActivity(_token!);
  }

  Future<void> _loadOverview(String token) async {
    setState(() => _isLoadingOverview = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/overview?dataset=$_selectedDataset', token);
      if (response != null && mounted) {
        setState(() => _overviewData = response);
      }
    } catch (e) {
      if (mounted) setState(() => _overviewError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingOverview = false);
    }
  }

  Future<void> _loadPerformance(String token) async {
    setState(() => _isLoadingPerformance = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/performance?dataset=$_selectedDataset', token);
      if (response != null && mounted) {
        setState(() => _performanceData = response);
      }
    } catch (e) {
      debugPrint('[MLDashboard] Performance load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPerformance = false);
    }
  }

  Future<void> _loadDataset(String token) async {
    setState(() => _isLoadingDataset = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/dataset?dataset=$_selectedDataset', token);
      if (response != null && mounted) {
        setState(() => _datasetData = response);
      }
    } catch (e) {
      debugPrint('[MLDashboard] Dataset load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDataset = false);
    }
  }

  Future<void> _loadFeatureImportance(String token, {String? modelId}) async {
    setState(() {
      _isLoadingFeatureImportance = true;
      if (modelId != null) {
        _selectedFeatureImportanceModelId = modelId;
      }
    });
    try {
      final modelParam = modelId != null ? '&model_id=$modelId' : '';
      final endpoint = '/admin/ml/feature-importance?dataset=$_selectedDataset$modelParam';
      final response = await _apiService.getMapWithAuth(endpoint, token);
      if (response != null && mounted) {
        setState(() {
          _featureImportanceData = response;
          if (_selectedFeatureImportanceModelId == null && response['model_id'] != null) {
            _selectedFeatureImportanceModelId = response['model_id'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('[MLDashboard] Feature importance load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingFeatureImportance = false);
    }
  }

  Future<void> _loadAlgorithmComparison(String token) async {
    setState(() => _isLoadingAlgorithmComparison = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/comparison?dataset=$_selectedDataset', token);
      if (response != null && mounted) {
        setState(() => _comparisonData = response);
      }
    } catch (e) {
      debugPrint('[MLDashboard] Algorithm comparison load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingAlgorithmComparison = false);
    }
  }

  Future<void> _loadPredictionInspector(String token) async {
    setState(() => _isLoadingPredictionInspector = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/prediction-inspector/latest', token);
      if (response != null && mounted) {
        setState(() => _predictionInspectorData = response);
      }
    } catch (e) {
      debugPrint('[MLDashboard] Prediction inspector load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPredictionInspector = false);
    }
  }

  Future<void> _loadActivity(String token) async {
    setState(() => _isLoadingActivity = true);
    try {
      final response = await _apiService.getMapWithAuth('/admin/ml/activity?dataset=$_selectedDataset&days=30', token);
      if (response != null && mounted) {
        setState(() => _activityData = response);
      }
    } catch (e) {
      debugPrint('[MLDashboard] Activity load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingActivity = false);
    }
  }

  Future<void> _trainCandidateModel() async {
    if (_token == null) return;
    setState(() => _isTrainingCandidate = true);
    try {
      final response = await _apiService.postWithAuth('/admin/ml/train-candidate?dataset=$_selectedDataset', _token!, {});
      if (!mounted) return;
      if (response.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Candidate model trained successfully. Review in Feature Importance or promote in admin settings.')),
        );
        _loadAllData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Training failed: Unknown error')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error training candidate: $e')),
      );
    } finally {
      if (mounted) setState(() => _isTrainingCandidate = false);
    }
  }

  Future<void> _runAlgorithmComparison() async {
    if (_token == null) return;
    setState(() => _isRunningComparison = true);
    try {
      final response = await _apiService.postWithAuth('/admin/ml/run-comparison?dataset=$_selectedDataset', _token!, {});
      if (!mounted) return;
      if (response.isNotEmpty) {
        setState(() {
          _comparisonData = response;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Algorithm comparison executed successfully.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comparison failed: Unknown error')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error running comparison: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRunningComparison = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1100;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ML Model & Recommendation Dashboard',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monitor model status, training readiness, performance, feature importance, and prediction behavior.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _token != null ? _loadAllData : null,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh Data'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerTheme.color ?? Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dataset, size: 20, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text(
                    'Dataset Context:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDataset,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'production',
                            child: Text('Production (Real Operational Data)'),
                          ),
                          DropdownMenuItem(
                            value: 'experimental',
                            child: Text('Experimental (Test / Demo Data)'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All Combined (Production + Experimental)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedDataset = val);
                            _loadAllData();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).dividerTheme.color ?? Colors.grey.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Theme.of(context).colorScheme.secondary,
                unselectedLabelColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.grey.shade600,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Performance'),
                  Tab(text: 'Dataset & Training'),
                  Tab(text: 'Feature Importance'),
                  Tab(text: 'Algorithm Comparison'),
                  Tab(text: 'Prediction Inspector'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 850,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(context),
                  _buildPerformanceTab(context),
                  _buildDatasetTab(context),
                  _buildFeatureImportanceTab(context),
                  _buildAlgorithmComparisonTab(context),
                  _buildPredictionInspectorTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. OVERVIEW TAB ---
  Widget _buildOverviewTab(BuildContext context) {
    if (_isLoadingOverview) return const Center(child: CircularProgressIndicator());
    if (_overviewError != null) {
      return Center(child: Text('Error: $_overviewError', style: const TextStyle(color: Colors.red)));
    }

    final dataSufficiency = _overviewData['data_sufficiency'] as Map<String, dynamic>? ?? {};
    final bool mlEnabled = _overviewData['ml_recommendations_enabled'] == true;
    final bool inferenceActive = _overviewData['ml_inference_active'] == true;
    final String modelStatus = _overviewData['model_status']?.toString() ?? 'disabled';
    final String modelVersion = _overviewData['model_version']?.toString() ?? 'none';
    final String algorithm = _overviewData['algorithm']?.toString() ?? 'none';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. Model Status Cards
          Text('Model & Inference Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          const SizedBox(height: 12),
          GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 4 : 2,
              mainAxisExtent: 125,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              MLMetricCard(label: 'ML Feature Flag', value: mlEnabled ? 'Enabled' : 'Disabled', color: mlEnabled ? Colors.green : Colors.orange, icon: Icons.flag),
              MLMetricCard(label: 'Inference Status', value: inferenceActive ? 'Active' : 'Inactive / Heuristic', color: inferenceActive ? Colors.green : Colors.grey, icon: Icons.bolt),
              MLMetricCard(label: 'Active Version ($modelStatus)', value: modelVersion, color: Colors.blue, icon: Icons.code),
              MLMetricCard(label: 'Algorithm ($algorithm)', value: dataSufficiency['sufficient_for_training'] == true ? 'Ready' : 'Blocked', color: dataSufficiency['sufficient_for_training'] == true ? Colors.green : Colors.red, icon: Icons.check_circle_outline),
            ],
          ),
          const SizedBox(height: 24),

          // B. Recommendation Pipeline Stages
          Text('Recommendation Pipeline Stages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text('Operational status across the 6-stage recommendation and feedback lifecycle.', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 12),
          MLRecommendationPipelineStepper(pipelineData: _overviewData),
          const SizedBox(height: 24),

          // C. Data Readiness & Blocking Reason
          Text('Data Readiness & Sufficiency Gate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Labeled Feedback:', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('${dataSufficiency['labeled_feedback'] ?? 0} / ${dataSufficiency['minimum_required'] ?? 20}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Accepted (Positive Class):', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('${dataSufficiency['accepted'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dismissed / Ignored (Negative Class):', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('${(dataSufficiency['dismissed'] ?? 0) + (dataSufficiency['ignored'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                if (dataSufficiency['blocking_reason'] != null) ...[
                  const Divider(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dataSufficiency['blocking_reason'].toString(),
                          style: TextStyle(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. PERFORMANCE TAB ---
  Widget _buildPerformanceTab(BuildContext context) {
    if (_isLoadingPerformance) return const Center(child: CircularProgressIndicator());

    final bool hasLiveModel = _performanceData['has_live_model'] == true && _performanceData['live_evaluation'] != null;
    final liveEval = _performanceData['live_evaluation'] as Map<String, dynamic>?;
    final metrics = liveEval?['metrics'] as Map<String, dynamic>? ?? {};
    final historical = _performanceData['historical_benchmark'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Model Performance & Evaluation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text('Predicting recommendation acceptance to rank break options. Does not diagnose psychological conditions or fatigue.', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 16),

          if (hasLiveModel) ...[
            Text('Live Production Model Evaluation (${liveEval?['model_version'] ?? 'Active'})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            GridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 5 : 2,
                mainAxisExtent: 125,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                MLMetricCard(label: 'Accuracy', value: ((metrics['accuracy'] as num?) ?? 0.0).toStringAsFixed(4), color: Colors.blue, icon: Icons.analytics),
                MLMetricCard(label: 'Precision', value: ((metrics['precision'] as num?) ?? 0.0).toStringAsFixed(4), color: Colors.teal, icon: Icons.gps_fixed),
                MLMetricCard(label: 'Recall', value: ((metrics['recall'] as num?) ?? 0.0).toStringAsFixed(4), color: Colors.purple, icon: Icons.track_changes),
                MLMetricCard(label: 'F1-Score', value: ((metrics['f1'] as num?) ?? 0.0).toStringAsFixed(4), color: Colors.indigo, icon: Icons.balance),
                MLMetricCard(label: 'ROC-AUC', value: ((metrics['roc_auc'] as num?) ?? 0.0).toStringAsFixed(4), color: Colors.green, icon: Icons.show_chart),
              ],
            ),
            const SizedBox(height: 24),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _performanceData['message']?.toString() ?? 'No live trained model available. Displaying verified thesis benchmark reference below.',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Historical Thesis Benchmark Section
          Text('Historical Thesis Benchmark (Reference)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text('Source: ${historical['source']} (${historical['context']})', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Model Name:', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text(historical['model_name']?.toString() ?? 'Logistic Regression (Balanced)', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Train Set Size / Test Set Size:', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('${historical['train_set_size']} / ${historical['test_set_size']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                GridView(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 5 : 2,
                    mainAxisExtent: 125,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    MLMetricCard(label: 'Accuracy', value: '${historical['accuracy']}', color: Colors.blueGrey, icon: Icons.analytics),
                    MLMetricCard(label: 'Precision', value: '${historical['precision']}', color: Colors.blueGrey, icon: Icons.gps_fixed),
                    MLMetricCard(label: 'Recall', value: '${historical['recall']}', color: Colors.blueGrey, icon: Icons.track_changes),
                    MLMetricCard(label: 'F1-Score', value: '${historical['f1_score']}', color: Colors.blueGrey, icon: Icons.balance),
                    MLMetricCard(label: 'ROC-AUC', value: '${historical['roc_auc']}', color: Colors.blueGrey, icon: Icons.show_chart),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Confusion Matrix (Test Split — Historical Benchmark):', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final cm = historical['confusion_matrix'];
                    final r00 = (cm is List && cm.isNotEmpty && cm[0] is List && cm[0].isNotEmpty) ? (cm[0][0] ?? 22) : 22;
                    final r01 = (cm is List && cm.isNotEmpty && cm[0] is List && cm[0].length > 1) ? (cm[0][1] ?? 12) : 12;
                    final r10 = (cm is List && cm.length > 1 && cm[1] is List && cm[1].isNotEmpty) ? (cm[1][0] ?? 9) : 9;
                    final r11 = (cm is List && cm.length > 1 && cm[1] is List && cm[1].length > 1) ? (cm[1][1] ?? 10) : 10;
                    return MLConfusionMatrixChart(
                      matrix: [
                        [r00, r01],
                        [r10, r11],
                      ],
                      label: 'Historical Benchmark — Logistic Regression (Balanced)',
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Recommendation Activity Chart
          Text('Recommendation Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 4),
          Text('Generated, accepted, dismissed, and ignored recommendations over available time.', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 12),
          _isLoadingActivity
              ? const Center(child: CircularProgressIndicator())
              : MLRecommendationActivityChart(
                  activityData: List<Map<String, dynamic>>.from(_activityData['activity_data'] ?? []),
                ),
        ],
      ),
    );
  }

  // --- 3. DATASET & TRAINING TAB ---
  Widget _buildDatasetTab(BuildContext context) {
    if (_isLoadingDataset) return const Center(child: CircularProgressIndicator());

    final int totalFeedback = _datasetData['total_feedback'] ?? 0;
    final int labeledCount = _datasetData['labeled_feedback_count'] ?? 0;
    final int acceptedCount = _datasetData['accepted_count'] ?? 0;
    final int dismissedCount = _datasetData['dismissed_count'] ?? 0;
    final int ignoredCount = _datasetData['ignored_count'] ?? 0;
    final int minRequired = _datasetData['minimum_required_for_training'] ?? 20;
    final bool sufficient = _datasetData['sufficient_for_training'] == true;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dataset & Training Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                  const SizedBox(height: 4),
                  Text('Feedback provenance, data sufficiency, and candidate model training triggers.', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: (_isTrainingCandidate || !sufficient) ? null : () => _showTrainConfirmationDialog(context),
                icon: _isTrainingCandidate ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt, size: 16),
                label: Text(_isTrainingCandidate ? 'Training...' : 'Train Candidate Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: sufficient ? Theme.of(context).colorScheme.secondary : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Dataset Breakdown Cards
          GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 4 : 2,
              mainAxisExtent: 125,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              MLMetricCard(label: 'Total Feedback', value: totalFeedback.toString(), color: Colors.blue, icon: Icons.storage),
              MLMetricCard(label: 'Labeled Samples', value: labeledCount.toString(), color: Colors.teal, icon: Icons.label),
              MLMetricCard(label: 'Accepted (Positive)', value: acceptedCount.toString(), color: Colors.green, icon: Icons.thumb_up),
              MLMetricCard(label: 'Dismissed/Ignored', value: (dismissedCount + ignoredCount).toString(), color: Colors.orange, icon: Icons.thumb_down),
            ],
          ),
          const SizedBox(height: 24),

          // Training Eligibility & Requirements
          Text('Training Eligibility Gate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sufficient ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Minimum Samples Required:', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('$labeledCount / $minRequired Labeled Samples', style: TextStyle(fontWeight: FontWeight.bold, color: sufficient ? Colors.green : Colors.orange)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Per-Class Minimum (>=5 per class):', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                    Text('Accepted: $acceptedCount, Dismissed/Ignored: ${dismissedCount + ignoredCount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(sufficient ? Icons.check_circle : Icons.info, color: sufficient ? Colors.green : Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sufficient
                            ? 'Dataset meets training requirements. You can trigger a candidate model training run above.'
                            : 'Training is currently blocked due to insufficient labeled feedback samples. More user feedback is required.',
                        style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Training Readiness Visualization
          Text('Training Readiness', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 12),
          MLTrainingReadinessWidget(
            labeledCount: labeledCount,
            minRequired: minRequired,
            acceptedCount: acceptedCount,
            dismissedCount: dismissedCount + ignoredCount,
            sufficient: sufficient,
          ),
          const SizedBox(height: 24),

          // Class Distribution Chart
          Text('Class Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 12),
          MLClassDistributionChart(
            acceptedCount: acceptedCount,
            dismissedCount: dismissedCount,
            ignoredCount: ignoredCount,
          ),
          const SizedBox(height: 24),

          // Provenance & Methodology Notes
          Text('Data Provenance & Training Methodology', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ${_datasetData['data_provenance_note']?.toString() ?? 'Excludes synthetic test records (is_test_data=true).'}', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 6),
                Text('• ${_datasetData['training_methodology_note']?.toString() ?? 'Trained using standardized features and categorical encoding.'}', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTrainConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Train Candidate Model'),
        content: const Text(
          'This will train a new candidate model using current labeled feedback data.\n\n'
          'The model will be created with is_active=false. It will NOT automatically replace the active production model until manually promoted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _trainCandidateModel();
            },
            child: const Text('Start Training'),
          ),
        ],
      ),
    );
  }

  // --- 4. FEATURE IMPORTANCE TAB ---
  Widget _buildFeatureImportanceTab(BuildContext context) {
    if (_isLoadingFeatureImportance) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<dynamic> availableModels = _featureImportanceData['available_models'] is List
        ? _featureImportanceData['available_models'] as List
        : [];
    final bool hasModels = availableModels.isNotEmpty &&
        _featureImportanceData['feature_importance'] != null &&
        _featureImportanceData['feature_importance'] is Map &&
        (_featureImportanceData['feature_importance'] as Map).isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feature Importance & Coefficients',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inspect standardized coefficient magnitudes from active or candidate models.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (availableModels.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? DesignSystem.getSemanticColor(context, SemanticColor.background)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedFeatureImportanceModelId ?? _featureImportanceData['model_id']?.toString(),
                      hint: const Text('Select Model Version'),
                      items: availableModels.map<DropdownMenuItem<String>>((m) {
                        final mMap = m as Map<String, dynamic>;
                        final id = mMap['model_id']?.toString() ?? '';
                        final ver = mMap['model_version']?.toString() ?? 'unknown';
                        final active = mMap['is_active'] == true ? ' [Active]' : ' [Candidate]';
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text('$ver$active', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
                        );
                      }).toList(),
                      onChanged: (String? newId) {
                        if (newId != null && _token != null) {
                          _loadFeatureImportance(_token!, modelId: newId);
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!hasModels)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DesignSystem.getSemanticColor(context, SemanticColor.background)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights, size: 48, color: Colors.orange.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No trained models available for feature importance inspection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Train a candidate model via the Dataset & Training tab to generate artifacts and analyze feature coefficients.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _compactInfoCard(context, 'Model ID', _featureImportanceData['model_id']?.toString() ?? '-')),
                    const SizedBox(width: 8),
                    Expanded(child: _compactInfoCard(context, 'Version', _featureImportanceData['model_version']?.toString() ?? '-')),
                    const SizedBox(width: 8),
                    Expanded(child: _compactInfoCard(context, 'Status', _featureImportanceData['is_active'] == true ? 'Active Production' : 'Trained Candidate')),
                    const SizedBox(width: 8),
                    Expanded(child: _compactInfoCard(context, 'Schema', _featureImportanceData['feature_set_version']?.toString() ?? 'v1-base')),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Ranked Feature Influence (Absolute Coefficients)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Higher magnitude indicates stronger relative influence on recommendation acceptance probability.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                if (_featureImportanceData['feature_importance'] != null && (_featureImportanceData['feature_importance'] as Map).isNotEmpty)
                  MLFeatureImportanceChart(
                    features: (_featureImportanceData['feature_importance'] as Map<dynamic, dynamic>).map((k, v) => MapEntry(k.toString(), {
                      'name': k.toString(),
                      'coefficient': v is num ? v.toDouble() : 0.0,
                      'importance': v is num ? v.abs().toDouble() : 0.0,
                    })).values.toList(),
                  )
                else
                  MLChartEmptyState(
                    icon: Icons.insights,
                    title: 'Feature Importance Unavailable',
                    message: 'No trained model artifact found or feature extraction failed. Train a candidate model via the Dataset & Training tab to generate coefficients.',
                  ),
                const SizedBox(height: 16),
                if (_featureImportanceData['note'] != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _featureImportanceData['note'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // --- 5. ALGORITHM COMPARISON TAB ---
  Widget _buildAlgorithmComparisonTab(BuildContext context) {
    if (_isLoadingAlgorithmComparison) return const Center(child: CircularProgressIndicator());

    final results = _comparisonData['comparison_results'] is List ? _comparisonData['comparison_results'] as List : [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Algorithm Comparison', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
                  const SizedBox(height: 4),
                  Text('Comparing candidate algorithms on standardized stratified training/test splits.', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _isRunningComparison ? null : _runAlgorithmComparison,
                icon: _isRunningComparison ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.compare_arrows, size: 16),
                label: Text(_isRunningComparison ? 'Running...' : 'Run Live Comparison'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: const Center(child: Text('No algorithm comparison results available. Click "Run Live Comparison" to evaluate.')),
            )
          else ...[
            MLPerformanceComparisonChart(
              models: results.map((r) {
                final metrics = r['metrics'] is Map<String, dynamic>
                    ? r['metrics'] as Map<String, dynamic>
                    : {
                        'accuracy': r['accuracy'],
                        'precision': r['precision'],
                        'recall': r['recall'],
                        'f1_score': r['f1'] ?? r['f1_score'],
                        'roc_auc': r['roc_auc'],
                      };
                return <String, dynamic>{
                  'algorithm': r['algorithm']?.toString() ?? 'Unknown',
                  'name': r['algorithm']?.toString() ?? 'Model',
                  'metrics': metrics,
                };
              }).toList(),
            ),
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index] as Map<String, dynamic>;
                final metrics = r['metrics'] is Map<String, dynamic>
                    ? r['metrics'] as Map<String, dynamic>
                    : {
                        'accuracy': r['accuracy'],
                        'precision': r['precision'],
                        'recall': r['recall'],
                        'f1': r['f1'] ?? r['f1_score'],
                        'roc_auc': r['roc_auc'],
                      };
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(r['algorithm']?.toString() ?? 'Algorithm', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r['status']?.toString() ?? 'Evaluated', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _metricItem('Accuracy', metrics['accuracy']),
                          _metricItem('Precision', metrics['precision']),
                          _metricItem('Recall', metrics['recall']),
                          _metricItem('F1-Score', metrics['f1']),
                          _metricItem('ROC-AUC', metrics['roc_auc']),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricItem(String label, dynamic val) {
    final double numVal = val is num ? val.toDouble() : 0.0;
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(numVal.toStringAsFixed(4), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- 6. PREDICTION INSPECTOR TAB ---
  Widget _buildPredictionInspectorTab(BuildContext context) {
    if (_isLoadingPredictionInspector) return const Center(child: CircularProgressIndicator());

    final features = _predictionInspectorData['features'] as Map<String, dynamic>?;
    final bool hasData = features != null && features.isNotEmpty;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prediction Inspector', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
          const SizedBox(height: 4),
          Text('Inspect input features and acceptance probabilities for recent recommendations.', style: TextStyle(fontSize: 13, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 16),

          if (!hasData)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(_predictionInspectorData['message']?.toString() ?? 'No recommendation history available for inspection.'),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recommendation Type: ${_predictionInspectorData['recommendation_type'] ?? '-'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _predictionInspectorData['ml_used'] == true ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _predictionInspectorData['ml_used'] == true ? 'ML Enhanced' : 'Heuristic Only',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _predictionInspectorData['ml_used'] == true ? Colors.green.shade700 : Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Model Version Used: ${_predictionInspectorData['model_version_used'] ?? '-'}'),
                      Text('Prediction Probability: ${_predictionInspectorData['prediction_probability'] != null ? (_predictionInspectorData['prediction_probability'] as num).toStringAsFixed(4) : 'N/A'}'),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('Input Features Supplied:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: features.length,
                    itemBuilder: (context, index) {
                      final key = features.keys.elementAt(index);
                      final val = features[key];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(key, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
                            Text(val?.toString() ?? '0.0', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_predictionInspectorData['note'] != null) ...[
                    const Divider(height: 24),
                    Text(_predictionInspectorData['note'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactInfoCard(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? DesignSystem.getSemanticColor(context, SemanticColor.background) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
