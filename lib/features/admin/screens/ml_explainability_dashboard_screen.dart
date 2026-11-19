import 'package:flutter/material.dart';
import 'package:intellibreak/core/design_system.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/admin/widgets/ml_confusion_matrix_chart.dart';
import 'package:intellibreak/features/admin/widgets/ml_feature_importance_chart.dart';

class MLExplainabilityDashboardScreen extends StatefulWidget {
  final ApiService apiService;

  MLExplainabilityDashboardScreen({
    super.key,
    ApiService? apiService,
  }) : apiService = apiService ?? ApiService();

  @override
  State<MLExplainabilityDashboardScreen> createState() =>
      _MLExplainabilityDashboardScreenState();
}

class _MLExplainabilityDashboardScreenState
    extends State<MLExplainabilityDashboardScreen>
    with SingleTickerProviderStateMixin {
  ApiService get _apiService => widget.apiService;
  late TabController _tabController;

  bool _isLoading = true;
  String? _errorMessage;

  // Dataset context selector state (Phase 2)
  String _selectedDataset = 'production'; // 'production' | 'experimental'

  // Tab 1: Overview
  Map<String, dynamic> _overviewData = {};
  Map<String, dynamic> _pipelineStatus = {};
  Map<String, dynamic> _recommendationActivity = {};

  // Tab 2: How It Works - static educational content

  // Tab 3: Data & Features
  Map<String, dynamic> _featuresData = {};

  // Tab 4: Scoring Engine
  Map<String, dynamic> _scoringData = {};

  // Tab 5: Model Performance
  Map<String, dynamic> _modelPerformanceData = {};
  Map<String, dynamic> _featureImportanceData = {};

  // Tab 6: Training & Feedback
  Map<String, dynamic> _trainingData = {};
  bool _isTraining = false;
  Map<String, dynamic>? _lastTrainingJob;

  // Tab 7: Prediction Inspector
  Map<String, dynamic> _predictionInspectorData = {};
  String? _inspectorError;
  bool _inspectorLoading = false;

  String? _token;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    _token = await _apiService.getToken();
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadOverview(),
        _loadFeatures(),
        _loadScoringEngine(),
        _loadModelPerformance(),
        _loadFeatureImportance(),
        _loadTrainingFeedback(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load dashboard data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Dataset selector change handler
  void _onDatasetChanged(String? value) {
    if (value != null && value != _selectedDataset) {
      setState(() {
        _selectedDataset = value;
        _isLoading = true;
        _errorMessage = null;
      });
      _loadAllData();
    }
  }

  Future<void> _loadOverview() async {
    if (_token == null) return;
    try {
      final results = await Future.wait([
        _apiService.getMapWithAuth('/admin/ml/overview?dataset=$_selectedDataset', _token!),
        _apiService.getMapWithAuth('/admin/ml/pipeline-status?dataset=$_selectedDataset', _token!),
        _apiService.getMapWithAuth('/admin/ml/activity?dataset=$_selectedDataset', _token!),
      ]);
      setState(() {
        _overviewData = _asStringKeyedMap(results[0]) ?? _getDefaultOverview();
        _pipelineStatus = _asStringKeyedMap(results[1]) ?? _getDefaultPipelineStatus();
        _recommendationActivity = _asStringKeyedMap(results[2]) ?? _getDefaultActivity();
      });
    } catch (e) {
      // Use fallback data structure
      setState(() {
        _overviewData = _getDefaultOverview();
        _pipelineStatus = _getDefaultPipelineStatus();
        _recommendationActivity = _getDefaultActivity();
      });
    }
  }

  Future<void> _loadFeatures() async {
    if (_token == null) return;
    try {
      final data = await _apiService.getMapWithAuth(
        '/admin/ml/dataset?dataset=$_selectedDataset',
        _token!,
      );
      setState(() {
        _featuresData = _asStringKeyedMap(data) ?? _getDefaultFeatures();
      });
    } catch (e) {
      setState(() {
        _featuresData = _getDefaultFeatures();
      });
    }
  }

  Future<void> _loadScoringEngine() async {
    if (_token == null) return;
    try {
      final data = await _apiService.getMapWithAuth(
        '/admin/ml/scoring-engine',
        _token!,
      );
      setState(() {
        _scoringData = _asStringKeyedMap(data) ?? _getDefaultScoring();
      });
    } catch (e) {
      setState(() {
        _scoringData = _getDefaultScoring();
      });
    }
  }

  String? _selectedModelId;

  Future<void> _loadModelPerformance() async {
    if (_token == null) return;
    try {
      final url = '/admin/ml/performance?dataset=$_selectedDataset${_selectedModelId != null ? '&model_id=$_selectedModelId' : ''}';
      final data = await _apiService.getMapWithAuth(
        url,
        _token!,
      );
      setState(() {
        _modelPerformanceData = _asStringKeyedMap(data) ?? _getDefaultModelPerformance();
      });
    } catch (e) {
      setState(() {
        _modelPerformanceData = _getDefaultModelPerformance();
      });
    }
  }

  Future<void> _loadFeatureImportance() async {
    if (_token == null) return;
    try {
      final data = await _apiService.getMapWithAuth(
        '/admin/ml/feature-importance',
        _token!,
      );
      if (!mounted) return;
      setState(() {
        _featureImportanceData = _asStringKeyedMap(data) ?? {};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _featureImportanceData = {};
      });
    }
  }

  Future<void> _loadTrainingFeedback() async {
    if (_token == null) return;
    try {
      final data = await _apiService.getMapWithAuth(
        '/admin/ml/training-feedback?dataset=$_selectedDataset',
        _token!,
      );
      setState(() {
        _trainingData = _asStringKeyedMap(data) ?? _getDefaultTraining();
      });
    } catch (e) {
      setState(() {
        _trainingData = _getDefaultTraining();
      });
    }
  }

  Future<void> _trainModel() async {
    if (_isTraining || _token == null) return;
    setState(() {
      _isTraining = true;
    });
    try {
      final response = await _apiService.postWithAuth(
        '/admin/ml/train?dataset=$_selectedDataset',
        _token!,
        {},
      );
      if (!mounted) return;
      setState(() {
        _lastTrainingJob = response is Map<String, dynamic> ? response : null;
        _isTraining = false;
      });
      if (response != null) {
        await _loadTrainingFeedback();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message']?.toString() ?? 'Training job scheduled.'),
            backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.success),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Training request failed. See logs for details.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTraining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Training failed: $e')),
      );
    }
  }

  Future<void> _activateModel(String modelId, String version) async {
    if (_token == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Model Activation'),
        content: Text('Are you sure you want to activate model version $version? This will replace the current active model for production inference.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activate')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {});
    try {
      final response = await _apiService.postWithAuth(
        '/admin/ml/activate/$modelId',
        _token!,
        {},
      );
      if (!mounted) return;
      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message']?.toString() ?? 'Model activated successfully.'),
            backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.success),
          ),
        );
        await _loadAllData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to activate model: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deactivateModels() async {
    if (_token == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Model Deactivation'),
        content: const Text('Are you sure you want to deactivate all active ML models? The system will automatically fall back to heuristic recommendations.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final response = await _apiService.postWithAuth(
        '/admin/ml/deactivate',
        _token!,
        {},
      );
      if (!mounted) return;
      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message']?.toString() ?? 'Models deactivated successfully.'),
            backgroundColor: DesignSystem.getSemanticColor(context, SemanticColor.success),
          ),
        );
        await _loadAllData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deactivate models: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadPredictionInspector(String recommendationId) async {
    if (_token == null) return;
    setState(() {
      _inspectorLoading = true;
      _inspectorError = null;
    });
    try {
      final data = await _apiService.getMapWithAuth(
        '/admin/ml/prediction-inspector/$recommendationId',
        _token!,
      );
      setState(() {
        _predictionInspectorData = _asStringKeyedMap(data) ?? {};
        _inspectorLoading = false;
      });
    } catch (e) {
      setState(() {
        _inspectorError = 'Failed to load prediction: $e';
        _inspectorLoading = false;
      });
    }
  }

  // Phase 2: Dataset Context Selector Widget
  Widget _buildDatasetSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.data_object,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            size: 20,
          ),
          const SizedBox(width: DesignSystem.spacingM),
          Expanded(
            child: Text(
              'Dataset Context',
              style: DesignSystem.bodyLarge(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _selectedDataset,
            items: const [
              DropdownMenuItem(
                value: 'production',
                child: Text('Production (real operational data)'),
              ),
              DropdownMenuItem(
                value: 'experimental',
                child: Text('Experimental (demo/test data)'),
              ),
            ],
            onChanged: _onDatasetChanged,
            underline: Container(),
            dropdownColor: isDark ? Colors.grey[850] : Colors.white,
            style: DesignSystem.body(context),
            icon: Icon(
              Icons.keyboard_arrow_down,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: DesignSystem.spacingM),
          if (_selectedDataset == 'experimental')
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSystem.spacingS,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.warning,
                ).withOpacity(0.15),
                borderRadius: BorderRadius.circular(DesignSystem.radiusS),
              ),
              child: Text(
                'DEMONSTRATION DATA',
                style: DesignSystem.caption(context).copyWith(
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.warning,
                  ),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Default/fallback data structures
  Map<String, dynamic> _getDefaultOverview() => {
    'ml_enabled': false,
    'model_trained': false,
    'model_activated': false,
    'ml_inference_executed': false,
    'heuristic_fallback': true,
    'active_model_version': null,
    'model_algorithm': null,
    'dataset_readiness': {'labeled_count': 0, 'sufficient': false},
    'warnings': [
      'ML_RECOMMENDATIONS_ENABLED=false',
      'No active production model',
    ],
  };

  Map<String, dynamic> _getDefaultPipelineStatus() => {
    'stages': [
      {
        'name': 'Feature Extraction',
        'status': 'active',
        'description': 'Extracting behavioral & wellbeing features',
      },
      {
        'name': 'Candidate Generation',
        'status': 'active',
        'description': 'Generating 5 break type candidates',
      },
      {
        'name': 'Eligibility Filtering',
        'status': 'active',
        'description': 'Applying break cooldown & active break gates',
      },
      {
        'name': 'Heuristic Scoring',
        'status': 'active',
        'description': 'Scoring candidates with evidence-based rules',
      },
      {
        'name': 'ML Acceptance Prediction',
        'status': 'disabled',
        'description': 'ML disabled (no active model / flag off)',
      },
      {
        'name': 'Final Ranking',
        'status': 'active',
        'description': 'Sorting by heuristic score (ML enhancement skipped)',
      },
      {
        'name': 'Recommendation Served',
        'status': 'active',
        'description': 'Top candidate returned, logged to feedback table',
      },
      {
        'name': 'Feedback Collection',
        'status': 'active',
        'description': 'Awaiting user action (accepted/dismissed/ignored)',
      },
    ],
  };

  Map<String, dynamic> _getDefaultActivity() => {
    'total_recommendations': 0,
    'accepted_count': 0,
    'dismissed_count': 0,
    'ignored_count': 0,
    'acceptance_rate': 0.0,
    'dismissal_rate': 0.0,
  };

  Map<String, dynamic> _getDefaultFeatures() => {
    'extracted_features': [],
    'model_schema_features': [],
    'schema_version': 'v2-wellbeing',
  };

  Map<String, dynamic> _getDefaultScoring() => {
    'heuristic_formula': _getHeuristicFormulaDoc(),
    'ml_enhancement_formula': _getMLEnhancementFormulaDoc(),
    'candidate_adjustments': _getCandidateAdjustments(),
    'weights': _getHeuristicWeights(),
  };

  Map<String, dynamic> _getDefaultModelPerformance() => {
    'has_live_model': false,
    'live_evaluation': null,
    'historical_benchmark': null,
  };

  Map<String, dynamic> _getDefaultTraining() => {
    'labeled_count': 0,
    'accepted_count': 0,
    'dismissed_count': 0,
    'ignored_count': 0,
    'min_required': 20,
    'min_per_class': 5,
    'sufficient_for_training': false,
    'class_distribution': {'positive': 0, 'negative': 0},
    'training_history': [],
  };

  Map<String, dynamic> _getHeuristicFormulaDoc() => {
    'baseline': 0.5,
    'factors': [
      {
        'name': 'session_length_gt_30min',
        'weight': 0.15,
        'condition': 'session_length_minutes > 30',
      },
      {
        'name': 'time_since_break_ge_80pct_preferred',
        'weight': 0.15,
        'condition': 'time_since_break >= preferred_interval * 0.8',
      },
      {
        'name': 'high_completion_rate_gt_80pct',
        'weight': -0.05,
        'condition': 'recent_task_completion_rate > 0.8',
      },
      {
        'name': 'high_fatigue_gt_0.6',
        'weight': 0.12,
        'condition': 'wellbeing_fatigue > 0.6',
        'candidates': ['SHORT_BREAK', 'WALK', 'STRETCH'],
      },
      {
        'name': 'low_fatigue_lt_0.3',
        'weight': -0.05,
        'condition': 'wellbeing_fatigue < 0.3',
        'candidates': ['SHORT_BREAK', 'WALK'],
      },
      {
        'name': 'low_recovery_lt_0.4',
        'weight': 0.10,
        'condition': 'wellbeing_recovery < 0.4',
        'candidates': ['WALK', 'STRETCH', 'SHORT_BREAK'],
      },
      {
        'name': 'high_recovery_gt_0.7_recent_break',
        'weight': -0.10,
        'condition': 'wellbeing_recovery > 0.7 AND time_since_break < 20',
      },
      {
        'name': 'low_workload_lt_0.4',
        'weight': 0.10,
        'condition': 'wellbeing_workload < 0.4',
        'candidates': ['SHORT_BREAK', 'LUNCH'],
      },
      {
        'name': 'stress_count_gt_0',
        'weight': 'min(0.15, 0.05 * stress_count)',
        'condition': 'wellbeing_stress_count > 0',
        'candidates': ['WALK', 'STRETCH'],
      },
    ],
    'behavioral_patterns': [
      {
        'pattern': 'REPEATED_SKIPPED_BREAKS',
        'weight': 0.15,
        'candidates': ['SHORT_BREAK'],
        'evidence_required': 'MEDIUM_or_HIGH',
      },
      {
        'pattern': 'INSUFFICIENT_RECOVERY',
        'weight': 0.12,
        'candidates': ['WALK', 'SHORT_BREAK'],
        'evidence_required': 'MEDIUM_or_HIGH',
      },
      {
        'pattern': 'RECURRING_FATIGUE_STRESS',
        'weight': 0.15,
        'candidates': ['WALK', 'STRETCH'],
        'evidence_required': 'MEDIUM_or_HIGH',
      },
      {
        'pattern': 'DECLINING_MEASURABLE_FOCUS',
        'weight': 0.10,
        'candidates': ['SHORT_BREAK'],
        'evidence_required': 'MEDIUM_or_HIGH',
      },
      {
        'pattern': 'RECURRING_OVERWORK',
        'weight': 0.12,
        'candidates': ['LUNCH', 'SHORT_BREAK'],
        'evidence_required': 'MEDIUM_or_HIGH',
      },
    ],
    'candidate_baselines': {
      'SHORT_BREAK': 0.0,
      'WALK': -0.02,
      'HYDRATE': -0.05,
      'STRETCH': -0.02,
      'LUNCH': -0.10,
    },
    'eligibility_gates': [
      {
        'name': 'active_break',
        'condition': 'has_active_break == true',
        'action': 'score = 0 (excluded)',
      },
      {
        'name': 'lunch_cooldown',
        'condition': 'last_break_duration >= 60 AND time_since_break < 180',
        'action': 'score = 0 (excluded)',
      },
    ],
    'output_bounds': 'max(0.0, min(1.0, score))',
  };

  Map<String, dynamic> _getMLEnhancementFormulaDoc() => {
    'condition': 'ML_RECOMMENDATIONS_ENABLED=true AND active_model_exists',
    'formula': 'final_score = heuristic_score * ml_enhancement',
    'ml_enhancement': 'P(acceptance | features, candidate_type) from LogisticRegression model',
    'ml_probability_display': '(ml_enhancement - 0.5) / 1.5',
    'bounds': 'max(0.0, min(1.0, final_score))',
    'note': 'ML predicts acceptance probability, not standalone recommendation score',
  };

  Map<String, dynamic> _getCandidateAdjustments() => {
    'SHORT_BREAK': 0.0,
    'WALK': -0.02,
    'HYDRATE': -0.05,
    'STRETCH': -0.02,
    'LUNCH': -0.10,
  };

  Map<String, dynamic> _getHeuristicWeights() => {
    'baseline': 0.5,
    'session_length_factor': 0.15,
    'time_since_break_factor': 0.15,
    'high_completion_penalty': -0.05,
    'high_fatigue_boost': 0.12,
    'low_fatigue_penalty': -0.05,
    'low_recovery_boost': 0.10,
    'high_recovery_recent_break_penalty': -0.10,
    'low_workload_boost': 0.10,
    'stress_boost_per_factor': 0.05,
    'stress_boost_max': 0.15,
    'pattern_REPEATED_SKIPPED_BREAKS': 0.15,
    'pattern_INSUFFICIENT_RECOVERY': 0.12,
    'pattern_RECURRING_FATIGUE_STRESS': 0.15,
    'pattern_DECLINING_MEASURABLE_FOCUS': 0.10,
    'pattern_RECURRING_OVERWORK': 0.12,
  };

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState(context);
    }

    if (_errorMessage != null) {
      return _buildErrorState(context);
    }

    return Scaffold(
      backgroundColor: DesignSystem.getSemanticColor(
        context,
        SemanticColor.background,
      ),
      body: Column(
        children: [
          _buildTabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(context),
                _buildHowItWorksTab(context),
                _buildDataFeaturesTab(context),
                _buildScoringEngineTab(context),
                _buildModelPerformanceTab(context),
                _buildTrainingFeedbackTab(context),
                _buildPredictionInspectorTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: DesignSystem.getSemanticColor(context, SemanticColor.surface),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: DesignSystem.getSemanticColor(
          context,
          SemanticColor.primary,
        ),
        unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
        indicatorColor: DesignSystem.getSemanticColor(
          context,
          SemanticColor.primary,
        ),
        indicatorWeight: 3,
        labelStyle: DesignSystem.labelLarge(context)
            .copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: DesignSystem.labelLarge(context),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'How It Works'),
          Tab(text: 'Data & Features'),
          Tab(text: 'Scoring Engine'),
          Tab(text: 'Model Performance'),
          Tab(text: 'Training & Feedback'),
          Tab(text: 'Prediction Inspector'),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: DesignSystem.getSemanticColor(
        context,
        SemanticColor.background,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.primary,
              ),
            ),
            const SizedBox(height: DesignSystem.spacingL),
            Text(
              'Loading ML Intelligence Center...',
              style: DesignSystem.body(
                context,
              ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: DesignSystem.getSemanticColor(
        context,
        SemanticColor.background,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSystem.spacingXL),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.error,
                ),
              ),
              const SizedBox(height: DesignSystem.spacingL),
              Text(
                'Failed to Load Dashboard',
                style: DesignSystem.titleXXL(context)
                    .copyWith(color: isDark ? Colors.white : Colors.black87),
              ),
              const SizedBox(height: DesignSystem.spacingM),
              Text(
                _errorMessage!,
                style: DesignSystem.body(
                  context,
                ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignSystem.spacingL),
              ElevatedButton(onPressed: _loadAllData, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TAB 1: OVERVIEW ====================
  Widget _buildOverviewTab(BuildContext context) {
    // Map backend API keys to frontend expected names
    final dataSufficiency = _overviewData['data_sufficiency'] ?? {};
    final mlEnabled = _overviewData['ml_recommendations_enabled'] ?? false;
    final activeModel = _overviewData['active_model_id'] != null;
    // modelTrained: a valid successfully trained artifact exists (historical OR active).
    // modelActivated: that artifact is currently the deployed inference model.
    // These are independent states; an inactive trained artifact is still "trained".
    final modelTrained = (_overviewData['trained_artifacts_count'] ?? 0) > 0;
    final modelActivated = _overviewData['model_status'] == 'active';
    final mlInferenceExecuted = _overviewData['ml_inference_active'] == true;
    final heuristicFallback = !mlInferenceExecuted;
    final activeModelVersion = _overviewData['model_version'];
    final modelAlgorithm = _overviewData['algorithm'];
    // Backend returns readiness under data_sufficiency, not dataset_readiness
    final datasetReadiness = _asStringKeyedMap(_overviewData['data_sufficiency']) ?? _asStringKeyedMap(_overviewData['dataset_readiness']) ?? {};
    final activity = _recommendationActivity;
    final warnings = _overviewData['warnings'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase 2: Dataset Context Selector
          _buildDatasetSelector(context),
          const SizedBox(height: DesignSystem.spacingL),
          _buildSectionHeader(
            context,
            'System Status',
            'Current operational state of the recommendation engine',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildStatusGrid(context, [
            _buildStatusCard(
              context,
              'ML Enabled',
              mlEnabled ? 'YES' : 'NO',
              mlEnabled ? Icons.check_circle : Icons.cancel,
              mlEnabled
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(context, SemanticColor.error),
              'Feature flag ML_RECOMMENDATIONS_ENABLED',
            ),
            _buildStatusCard(
              context,
              'Model Trained',
              modelTrained ? 'YES' : 'NO',
              modelTrained ? Icons.check_circle : Icons.cancel,
              modelTrained
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.warning,
                    ),
              'Sufficient labeled data & training completed',
            ),
            _buildStatusCard(
              context,
              'Model Activated',
              modelActivated ? 'YES' : 'NO',
              modelActivated ? Icons.check_circle : Icons.cancel,
              modelActivated
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.warning,
                    ),
              'Admin explicitly activated via /admin/ml/activate',
            ),
            _buildStatusCard(
              context,
              'ML Inference Executed',
              mlInferenceExecuted ? 'YES' : 'NO',
              mlInferenceExecuted ? Icons.check_circle : Icons.cancel,
              mlInferenceExecuted
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(context, SemanticColor.info),
              'ML probability used in live recommendations',
            ),
            _buildStatusCard(
              context,
              'Heuristic Fallback Active',
              heuristicFallback ? 'YES' : 'NO',
              heuristicFallback ? Icons.warning : Icons.check_circle,
              heuristicFallback
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.warning,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    ),
              heuristicFallback
                  ? 'All recommendations use heuristic-only scoring'
                  : 'ML enhancement applied',
            ),
          ]),
          const SizedBox(height: DesignSystem.spacingL),

          if (activeModelVersion != null) ...[
            _buildSectionHeader(
              context,
              'Active Model',
              'Currently deployed model for inference',
            ),
            const SizedBox(height: DesignSystem.spacingM),
            _buildInfoCard(context, [
              _buildInfoRow(context, 'Version', activeModelVersion.toString()),
              _buildInfoRow(
                context,
                'Algorithm',
                modelAlgorithm?.toString() ?? 'LogisticRegression (V2)',
              ),
              _buildInfoRow(
                context,
                'Feature Schema',
                _overviewData['feature_schema_version'] ?? 'v2-wellbeing',
              ),
              _buildInfoRow(
                context,
                'Deployment Status',
                modelActivated ? 'Active' : 'Trained but not activated',
              ),
            ]),
            const SizedBox(height: DesignSystem.spacingL),
          ],

          _buildSectionHeader(
            context,
            'Dataset Readiness',
            'Labeled feedback data available for training',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildDatasetReadinessCard(context, datasetReadiness),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Recommendation Activity',
            'Aggregate feedback statistics',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildActivityCards(context, activity),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Pipeline Visualization',
            'End-to-end recommendation flow',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildPipelineVisualization(context),
          const SizedBox(height: DesignSystem.spacingL),

          if (warnings.isNotEmpty) ...[
            _buildSectionHeader(
              context,
              'Operational Warnings',
              'Conditions affecting system behavior',
            ),
            const SizedBox(height: DesignSystem.spacingM),
            _buildWarningsList(context, warnings),
            const SizedBox(height: DesignSystem.spacingL),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: DesignSystem.spacingM),
              Expanded(
                child: Text(
                  title,
                  style: DesignSystem.title(context)
                      .copyWith(color: isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            value,
            style: DesignSystem.titleXXXL(context)
                .copyWith(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            subtitle,
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildDatasetReadinessCard(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // API returns: labeled_feedback, accepted, dismissed, ignored, minimum_required, sufficient_for_training
    final labeledCount = data['labeled_feedback'] ?? data['labeled_count'] ?? 0;
    final minRequired = data['minimum_required'] ?? 20;
    final sufficient = data['sufficient_for_training'] ?? false;
    final acceptedCount = data['accepted'] ?? data['accepted_count'] ?? 0;
    final dismissedCount = data['dismissed'] ?? data['dismissed_count'] ?? 0;
    final ignoredCount = data['ignored'] ?? data['ignored_count'] ?? 0;
    final minPerClass = data['minimum_per_class'] ?? 5;

    final progress = (labeledCount / minRequired).clamp(0.0, 1.0);
    final classBalance =
        acceptedCount >= minPerClass && dismissedCount >= minPerClass;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sufficient ? Icons.check_circle : Icons.schedule,
                color: sufficient
                    ? DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.success,
                      )
                    : DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ),
              ),
              const SizedBox(width: DesignSystem.spacingM),
              Text(
                sufficient
                    ? 'Sufficient for Training'
                    : 'Insufficient for Training',
                style: DesignSystem.title(context).copyWith(
                  color: sufficient
                      ? DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.success,
                        )
                      : DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.warning,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingL),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              sufficient
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.primary,
                    ),
            ),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Labeled Samples',
                  '$labeledCount / $minRequired',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Accepted',
                  '$acceptedCount (min $minPerClass)',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Dismissed',
                  '$dismissedCount (min $minPerClass)',
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Class Balance',
                  classBalance ? '✓ Met' : '✗ Not Met',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: DesignSystem.body(context).copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCards(
    BuildContext context,
    Map<String, dynamic> activity,
  ) {
    // Backend returns activity_data list; aggregate totals
    final activityData = _asMapList(activity['activity_data']);
    int sumActivity(String key) => activityData.fold<int>(0, (sum, row) {
          final value = row[key];
          return sum + (value is num ? value.toInt() : 0);
        });
    final total = sumActivity('generated');
    final accepted = sumActivity('accepted');
    final dismissed = sumActivity('dismissed');
    final ignored = sumActivity('ignored');
    return Row(
      children: [
        Expanded(
          child: _buildActivityCard(
            context,
            'Total',
            total.toString(),
            Icons.recommend,
            DesignSystem.getSemanticColor(context, SemanticColor.primary),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingM),
        Expanded(
          child: _buildActivityCard(
            context,
            'Accepted',
            accepted.toString(),
            Icons.check_circle,
            DesignSystem.getSemanticColor(context, SemanticColor.success),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingM),
        Expanded(
          child: _buildActivityCard(
            context,
            'Dismissed',
            dismissed.toString(),
            Icons.cancel,
            DesignSystem.getSemanticColor(context, SemanticColor.error),
          ),
        ),
        const SizedBox(width: DesignSystem.spacingM),
        Expanded(
          child: _buildActivityCard(
            context,
            'Ignored',
            ignored.toString(),
            Icons.remove_circle_outline,
            DesignSystem.getSemanticColor(context, SemanticColor.warning),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            value,
            style: DesignSystem.titleXXXL(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            label,
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineVisualization(BuildContext context) {
    final stagesRaw = _pipelineStatus['stages'];
    if (stagesRaw != null && stagesRaw is! List) {
      return _buildMalformedErrorCard(context, 'Pipeline stages', stagesRaw);
    }
    final stages = _asMapList(
      stagesRaw ?? _getDefaultPipelineStatus()['stages'],
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: stages.asMap().entries.map((entry) {
          final index = entry.key;
          final stage = entry.value;
          final isLast = index == stages.length - 1;
          final status = stage['status'] ?? 'pending';
          final isActive = status == 'active';
          final isDisabled = status == 'disabled';

          Color stageColor;
          IconData stageIcon;
          if (isDisabled) {
            stageColor = isDark ? Colors.white30 : Colors.grey.shade400;
            stageIcon = Icons.lock_outline;
          } else if (isActive) {
            stageColor = DesignSystem.getSemanticColor(
              context,
              SemanticColor.success,
            );
            stageIcon = Icons.check_circle;
          } else {
            stageColor = DesignSystem.getSemanticColor(
              context,
              SemanticColor.primary,
            );
            stageIcon = Icons.radio_button_unchecked;
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Icon(stageIcon, color: stageColor, size: 24),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 40,
                          color: stageColor.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                  const SizedBox(width: DesignSystem.spacingM),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignSystem.spacingL,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stage['name'] ?? '',
                                  style: DesignSystem.title(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDisabled
                                        ? (isDark
                                              ? Colors.white38
                                              : Colors.grey.shade500)
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black87),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: stageColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(
                                    DesignSystem.radiusS,
                                  ),
                                ),
                                child: Text(
                                  isDisabled
                                      ? 'DISABLED'
                                      : (isActive ? 'ACTIVE' : 'PENDING'),
                                  style: DesignSystem.body(context).copyWith(
                                    color: stageColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stage['description'] ?? '',
                            style: DesignSystem.body(context).copyWith(
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWarningsList(BuildContext context, List<dynamic> warnings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(
          context,
          SemanticColor.warning,
        ).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.warning,
          ).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: warnings
            .map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: DesignSystem.spacingS),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ),
                    ),
                    const SizedBox(width: DesignSystem.spacingS),
                    Expanded(
                      child: Text(
                        w.toString(),
                        style: DesignSystem.body(context).copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ==================== TAB 2: HOW IT WORKS ====================
  Widget _buildHowItWorksTab(BuildContext context) {
    final stages = [
      _HowItWorksStage(
        number: 1,
        title: 'Employee Behavior',
        description: 'Raw telemetry from work sessions, breaks, tasks, and wellbeing check-ins',
        inputs: [
          'work_sessions',
          'breaks',
          'tasks',
          'session_wellbeing_checkins',
          'user_settings',
          'profiles',
        ],
        processing: 'Continuous data collection during work hours',
        outputs: 'Behavioral time series per employee',
        service: 'Flutter frontend → FastAPI backend → PostgreSQL',
      ),
      _HowItWorksStage(
        number: 2,
        title: 'Feature Extraction',
        description: 'Compute 16 behavioral + wellbeing features from recent history (last hour + latest check-in)',
        inputs: [
          'Active session',
          'Last break',
          'Recent tasks (1hr)',
          'Latest wellbeing check-in',
          'User preferences',
        ],
        processing: '_extract_features() in recommendation_service.py — temporal-safe joins, normalization (1-5)→(0-1)',
        outputs: 'Feature dict: session_length, time_since_break, completion_rate, focus_rate, wellbeing_*, cold_start, patterns',
        service: 'recommendation_service.py → _extract_features(), _extract_wellbeing_features(), _detect_behavioral_patterns()',
      ),
      _HowItWorksStage(
        number: 3,
        title: 'Candidate Generation',
        description: 'Fixed set of 5 break-type candidates generated for every recommendation request',
        inputs: ['None (static candidate list)'],
        processing:
            'Hardcoded list: SHORT_BREAK, WALK, HYDRATE, STRETCH, LUNCH',
        outputs: '5 candidate types for scoring',
        service:
            '_recommend_for_profile() in recommendation_service.py (line ~365)',
      ),
      _HowItWorksStage(
        number: 4,
        title: 'Eligibility Filtering',
        description: 'Hard gates that exclude candidates before scoring',
        inputs: ['has_active_break, last_break_duration, time_since_break'],
        processing: 'Gate 1: Active break → exclude all. Gate 2: Lunch cooldown (last_break≥60min & time_since<180min) → exclude all',
        outputs:
            'Eligible candidate subset (typically all 5 unless gates trigger)',
        service:
            '_score_candidate() lines 263-269 in recommendation_service.py',
      ),
      _HowItWorksStage(
        number: 5,
        title: 'Heuristic Scoring',
        description: 'Evidence-based ranking score using 12 weighted factors + 5 behavioral patterns + candidate baselines',
        inputs: ['All extracted features + detected patterns (evidence MEDIUM/HIGH only)'],
        processing: 'Baseline 0.5 + factor weights (see Scoring Engine tab) + pattern adjustments + candidate baselines → clamp [0,1]',
        outputs: 'heuristic_score per candidate (0.0-1.0)',
        service:
            '_score_candidate() in recommendation_service.py (lines 258-395)',
      ),
      _HowItWorksStage(
        number: 6,
        title: 'ML Acceptance Prediction',
        description: 'Optional LogisticRegression predicts P(accepted | features, candidate_type) — only when enabled & model active',
        inputs: ['V2 feature schema (10 features: 9 numeric + 1 categorical one-hot)'],
        processing: 'Active model predict_proba() → ml_enhancement = P(class=1). Hybrid: final = heuristic * ml_enhancement',
        outputs: 'ml_enhancement (0.0-1.0), ml_probability for display, ml_used flag',
        service: '_get_ml_enhancement(), _score_with_ml() in recommendation_service.py; model from ml_training_pipeline.py',
      ),
      _HowItWorksStage(
        number: 7,
        title: 'Final Ranking',
        description:
            'Sort candidates by final_score (heuristic or hybrid), select top',
        inputs: ['final_score per eligible candidate'],
        processing: 'Sort descending, break ties by candidate priority order',
        outputs: 'Top recommendation + full ranked list stored in recommendation_feedback',
        service: '_recommend_for_profile() lines 400-430 in recommendation_service.py',
      ),
      _HowItWorksStage(
        number: 8,
        title: 'Employee Recommendation',
        description: 'Return top candidate with explanation, metadata, and recommendation_id for feedback tracking',
        inputs: ['Selected candidate + all scores + feature snapshot'],
        processing: 'Build response with recommendation_type, score, reason, ml_probability, model_version, cold_start flag',
        outputs: 'API response to Flutter; recommendation_feedback row with user_action=NULL',
        service: '/recommend endpoint in recommendation_service.py',
      ),
      _HowItWorksStage(
        number: 9,
        title: 'Feedback Collection',
        description: 'User responds: accepted/dismissed/ignored/helpful/not_helpful → updates recommendation_feedback.user_action',
        inputs: ['User action via /recommend/feedback endpoint'],
        processing: 'Map actions to labels: accepted/helpful=1 (positive), dismissed/ignored/not_helpful=0 (negative)',
        outputs: 'Labeled training record for next model retraining cycle',
        service: 'submit_feedback() in recommendation_service.py; assess_data_sufficiency() in ml_training_pipeline.py',
      ),
      _HowItWorksStage(
        number: 10,
        title: 'Model Training',
        description: 'When ≥20 labeled samples with ≥5 per class: train LogisticRegression (V2 schema), cross-validate, evaluate, optionally activate',
        inputs: ['Production labeled data (excludes test/demo users)'],
        processing: 'ColumnTransformer(StandardScaler+OneHot) → LogisticRegression → StratifiedKFold CV → metrics → joblib artifact → MLModel DB record',
        outputs: 'Model artifact (.pkl), MLModel DB record, evaluation metrics, activation status',
        service: 'train_model(), evaluate_model(), activate_model() in ml_training_pipeline.py; /admin/ml/train & /activate endpoints',
      ),
    ];

    final List<Widget> stageCards = stages
        .map((stage) => _buildHowItWorksStageCard(context, stage))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Recommendation Pipeline',
            'End-to-end flow from employee behavior to model training',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          ...stageCards,
        ],
      ),
    );
  }

  Widget _buildHowItWorksStageCard(
    BuildContext context,
    _HowItWorksStage stage,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stageColor = _getStageColor(stage.number);

    return Container(
      margin: const EdgeInsets.only(bottom: DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: stageColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(DesignSystem.radiusM),
          ),
          child: Center(
            child: Text(
              '${stage.number}',
              style: DesignSystem.titleLarge(context)
                  .copyWith(fontWeight: FontWeight.bold, color: stageColor),
            ),
          ),
        ),
        title: Text(
          stage.title,
          style: DesignSystem.title(context).copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          stage.description,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          DesignSystem.spacingL,
          0,
          DesignSystem.spacingL,
          DesignSystem.spacingL,
        ),
        children: [
          _buildDetailRow(context, 'Inputs', stage.inputs.join(', ')),
          _buildDetailRow(context, 'Processing', stage.processing),
          _buildDetailRow(context, 'Outputs', stage.outputs),
          _buildDetailRow(
            context,
            'Backend Service',
            stage.service,
            isCode: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isCode = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: DesignSystem.body(context).copyWith(
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
            ),
            child: Text(
              value,
              style: (isCode ? DesignSystem.caption : DesignSystem.body)(
                context,
              ).copyWith(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStageColor(int number) {
    const colors = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.green,
      Colors.cyan,
      Colors.pink,
      Colors.amber,
      Colors.deepOrange,
    ];
    return colors[(number - 1) % colors.length];
  }

  // ==================== TAB 3: DATA & FEATURES ====================
  Widget _buildDataFeaturesTab(BuildContext context) {
    final extractedFeatures =
        _featuresData['extracted_features'] ?? _getDefaultExtractedFeatures();
    final modelSchemaFeatures =
        _featuresData['model_schema_features'] ??
        _getDefaultModelSchemaFeatures();
    final schemaVersion = _featuresData['schema_version'] ?? 'v2-wellbeing';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Feature Schema',
            'Current model feature schema version: $schemaVersion',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildInfoCard(context, [
            _buildInfoRow(context, 'Schema Version', schemaVersion),
            _buildInfoRow(
              context,
              'Numeric Features',
              '${_getV2NumericFeatures().length}',
            ),
            _buildInfoRow(
              context,
              'Categorical Features',
              '${_getV2CategoricalFeatures().length}',
            ),
            _buildInfoRow(
              context,
              'Total Features',
              '${_getV2AllFeatures().length}',
            ),
          ]),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Extracted Features (Runtime)',
            'Features computed by _extract_features() for each recommendation request',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildFeatureTable(
            context,
            _asMapList(extractedFeatures),
            'extracted',
          ),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Model Input Features (V2 Schema)',
            'Features expected by the trained LogisticRegression model (after preprocessing)',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildFeatureTable(
            context,
            _asMapList(modelSchemaFeatures),
            'model',
          ),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Feature Mapping',
            'How extracted features map to model schema',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildFeatureMappingTable(context),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getDefaultExtractedFeatures() => [
    {
      'name': 'session_length_minutes',
      'description': 'Active work session duration in minutes',
      'source': 'work_sessions.started_at',
      'type': 'numeric',
      'used_in': 'heuristic',
      'normalization': 'none',
    },
    {
      'name': 'time_since_last_break_minutes',
      'description': 'Minutes since last break ended (9999 if none)',
      'source': 'breaks.ended_at',
      'type': 'numeric',
      'used_in': 'heuristic',
      'normalization': 'none',
    },
    {
      'name': 'recent_task_completion_rate',
      'description': 'Tasks completed in last hour / total tasks',
      'source': 'tasks (last 1hr)',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic',
      'normalization': 'none',
    },
    {
      'name': 'current_focus_rate',
      'description': 'Focus time / total session time',
      'source': 'tasks.actual_minutes in session',
      'type': 'numeric (0-1)',
      'used_in': 'snapshot',
      'normalization': 'none',
    },
    {
      'name': 'preferred_interval_minutes',
      'description': 'User configured break interval',
      'source': 'user_settings.break_interval_minutes',
      'type': 'numeric',
      'used_in': 'heuristic',
      'normalization': 'none',
    },
    {
      'name': 'preferred_duration_minutes',
      'description': 'User configured break duration',
      'source': 'user_settings.break_duration_minutes',
      'type': 'numeric',
      'used_in': 'snapshot',
      'normalization': 'none',
    },
    {
      'name': 'has_active_break',
      'description': 'Whether user currently on break',
      'source': 'breaks.ended_at IS NULL',
      'type': 'boolean',
      'used_in': 'heuristic (gate)',
      'normalization': 'none',
    },
    {
      'name': 'last_break_duration_minutes',
      'description': 'Duration of most recent completed break',
      'source': 'breaks.duration_minutes',
      'type': 'numeric',
      'used_in': 'heuristic (gate)',
      'normalization': 'none',
    },
    {
      'name': 'cold_start',
      'description': 'Insufficient labeled feedback for ML',
      'source': 'recommendation_feedback count',
      'type': 'boolean',
      'used_in': 'ML gating',
      'normalization': 'none',
    },
    {
      'name': 'wellbeing_overall',
      'description': 'Normalized overall wellbeing (1-5)→(0-1)',
      'source': 'session_wellbeing_checkins.overall_wellbeing',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic + ML',
      'normalization': '(x-1)/4',
    },
    {
      'name': 'wellbeing_fatigue',
      'description': 'Normalized mental fatigue (1-5)→(0-1)',
      'source': 'session_wellbeing_checkins.mental_fatigue',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic + ML',
      'normalization': '(x-1)/4',
    },
    {
      'name': 'wellbeing_workload',
      'description': 'Normalized workload manageability (1-5)→(0-1)',
      'source': 'session_wellbeing_checkins.workload_manageability',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic + ML',
      'normalization': '(x-1)/4',
    },
    {
      'name': 'wellbeing_focus',
      'description': 'Normalized perceived focus (1-5)→(0-1)',
      'source': 'session_wellbeing_checkins.perceived_focus',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic + ML',
      'normalization': '(x-1)/4',
    },
    {
      'name': 'wellbeing_recovery',
      'description': 'Normalized break recovery (1-5)→(0-1)',
      'source': 'session_wellbeing_checkins.break_recovery',
      'type': 'numeric (0-1)',
      'used_in': 'heuristic + ML',
      'normalization': '(x-1)/4',
    },
    {
      'name': 'wellbeing_stress_count',
      'description': 'Stress factor count',
      'source': 'session_wellbeing_checkins.stress_factors (JSON)',
      'type': 'integer',
      'used_in': 'heuristic + ML',
      'normalization': 'raw count',
    },
    {
      'name': 'wellbeing_checkin_observed',
      'description': 'Whether eligible check-in data was found',
      'source': 'Temporal join result',
      'type': 'boolean',
      'used_in': 'snapshot',
      'normalization': 'none',
    },
    {
      'name': 'detected_patterns',
      'description': 'Behavioral patterns with evidence strength',
      'source': '_detect_behavioral_patterns()',
      'type': 'object[]',
      'used_in': 'heuristic (patterns)',
      'normalization': 'N/A',
    },
  ];

  List<Map<String, dynamic>> _getDefaultModelSchemaFeatures() => [
    {
      'name': 'session_length',
      'description': 'Active work session duration in minutes',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'time_since_break',
      'description': 'Minutes since last completed break',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'completion_rate',
      'description': 'Recent task completion rate (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_overall',
      'description': 'Normalized overall wellbeing (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_fatigue',
      'description': 'Normalized mental fatigue (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_workload',
      'description': 'Normalized workload manageability (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_focus',
      'description': 'Normalized perceived focus (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_recovery',
      'description': 'Normalized break recovery (0.0-1.0)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'wellbeing_stress',
      'description': 'Stress factor count (0+)',
      'type': 'numeric',
      'preprocessing': 'SimpleImputer(0.0) → StandardScaler',
      'schema': 'V2 numeric',
    },
    {
      'name': 'recommendation_type',
      'description': 'One of: SHORT_BREAK, WALK, HYDRATE, STRETCH, LUNCH',
      'type': 'categorical',
      'preprocessing': 'OneHotEncoder(handle_unknown=ignore)',
      'schema': 'V2 categorical',
    },
  ];

  List<String> _getV2NumericFeatures() => [
    'session_length',
    'time_since_break',
    'completion_rate',
    'wellbeing_overall',
    'wellbeing_fatigue',
    'wellbeing_workload',
    'wellbeing_focus',
    'wellbeing_recovery',
    'wellbeing_stress',
  ];

  List<String> _getV2CategoricalFeatures() => ['recommendation_type'];

  List<String> _getV2AllFeatures() => [
    ..._getV2NumericFeatures(),
    ..._getV2CategoricalFeatures(),
  ];

  Widget _buildFeatureTable(
    BuildContext context,
    List<Map<String, dynamic>> features,
    String tableType,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Feature Name',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Description',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Data Type',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Used In',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (tableType == 'extracted')
                  Expanded(
                    child: Text(
                      'Normalization',
                      style: DesignSystem.labelLarge(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (tableType == 'model')
                  Expanded(
                    child: Text(
                      'Preprocessing',
                      style: DesignSystem.labelLarge(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final f = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      f['name'] ?? '',
                      style: DesignSystem.caption(context)
                          .copyWith(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      f['description'] ?? '',
                      style: DesignSystem.body(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      f['type'] ?? '',
                      style: DesignSystem.body(context),
                    ),
                  ),
                  Expanded(
                    child: _buildUsageBadges(context, f['used_in'] ?? ''),
                  ),
                  if (tableType == 'extracted')
                    Expanded(
                      child: Text(
                        f['normalization'] ?? '',
                        style: DesignSystem.body(context),
                      ),
                    ),
                  if (tableType == 'model')
                    Expanded(
                      child: Text(
                        f['preprocessing'] ?? '',
                        style: DesignSystem.body(context),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildUsageBadges(BuildContext context, String usage) {
    final badges = <Widget>[];
    if (usage.contains('heuristic')) {
      badges.add(
        _buildBadge(
          context,
          'Heuristic',
          DesignSystem.getSemanticColor(context, SemanticColor.primary),
        ),
      );
    }
    if (usage.contains('ML')) {
      badges.add(
        _buildBadge(
          context,
          'ML',
          DesignSystem.getSemanticColor(context, SemanticColor.success),
        ),
      );
    }
    if (usage.contains('gate')) {
      badges.add(
        _buildBadge(
          context,
          'Gate',
          DesignSystem.getSemanticColor(context, SemanticColor.warning),
        ),
      );
    }
    if (usage.contains('snapshot')) {
      badges.add(
        _buildBadge(
          context,
          'Snapshot',
          DesignSystem.getSemanticColor(context, SemanticColor.info),
        ),
      );
    }
    if (usage.contains('pattern')) {
      badges.add(
        _buildBadge(
          context,
          'Pattern',
          DesignSystem.getSemanticColor(context, SemanticColor.secondary),
        ),
      );
    }
    if (badges.isEmpty) {
      badges.add(_buildBadge(context, '—', Colors.grey));
    }
    return Wrap(spacing: 4, runSpacing: 4, children: badges);
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DesignSystem.radiusS),
      ),
      child: Text(
        text,
        style: DesignSystem.body(context)
            .copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 10),
      ),
    );
  }

  Widget _buildFeatureMappingTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mappings = [
      {
        'extracted': 'session_length_minutes',
        'model': 'session_length',
        'transform': 'Direct (minutes)',
      },
      {
        'extracted': 'time_since_last_break_minutes',
        'model': 'time_since_break',
        'transform': 'Direct (minutes)',
      },
      {
        'extracted': 'recent_task_completion_rate',
        'model': 'completion_rate',
        'transform': 'Direct (0-1)',
      },
      {
        'extracted': 'wellbeing_overall',
        'model': 'wellbeing_overall',
        'transform': 'Direct (already normalized)',
      },
      {
        'extracted': 'wellbeing_fatigue',
        'model': 'wellbeing_fatigue',
        'transform': 'Direct (already normalized)',
      },
      {
        'extracted': 'wellbeing_workload',
        'model': 'wellbeing_workload',
        'transform': 'Direct (already normalized)',
      },
      {
        'extracted': 'wellbeing_focus',
        'model': 'wellbeing_focus',
        'transform': 'Direct (already normalized)',
      },
      {
        'extracted': 'wellbeing_recovery',
        'model': 'wellbeing_recovery',
        'transform': 'Direct (already normalized)',
      },
      {
        'extracted': 'wellbeing_stress_count',
        'model': 'wellbeing_stress',
        'transform': 'Direct (count → numeric)',
      },
      {
        'extracted': 'recommendation_type (candidate)',
        'model': 'recommendation_type',
        'transform': 'One-hot encoded per candidate',
      },
      {
        'extracted': 'current_focus_rate',
        'model': '—',
        'transform': 'NOT in V2 model schema (snapshot only)',
      },
      {
        'extracted': 'preferred_interval_minutes',
        'model': '—',
        'transform': 'NOT in V2 model schema (heuristic only)',
      },
      {
        'extracted': 'preferred_duration_minutes',
        'model': '—',
        'transform': 'NOT in V2 model schema (snapshot only)',
      },
      {
        'extracted': 'has_active_break',
        'model': '—',
        'transform': 'NOT in V2 model schema (gate only)',
      },
      {
        'extracted': 'last_break_duration_minutes',
        'model': '—',
        'transform': 'NOT in V2 model schema (gate only)',
      },
      {
        'extracted': 'cold_start',
        'model': '—',
        'transform': 'NOT in V2 model schema (ML gating only)',
      },
      {
        'extracted': 'wellbeing_checkin_observed',
        'model': '—',
        'transform': 'NOT in V2 model schema (snapshot only)',
      },
      {
        'extracted': 'detected_patterns',
        'model': '—',
        'transform': 'NOT in V2 model schema (heuristic patterns only)',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Extracted Feature',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Model Schema Feature',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Transformation',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...mappings.asMap().entries.map((entry) {
            final index = entry.key;
            final m = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final inModel = m['model'] != '—';
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      m['extracted'] ?? '',
                      style: DesignSystem.caption(context).copyWith(
                        fontSize: 12,
                        color: inModel
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      m['model'] ?? '',
                      style: DesignSystem.caption(context).copyWith(
                        fontSize: 12,
                        color: inModel
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      m['transform'] ?? '',
                      style: DesignSystem.body(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ==================== TAB 4: SCORING ENGINE ====================
  Widget _buildScoringEngineTab(BuildContext context) {
    final mlFormula =
        _scoringData['ml_enhancement_formula'] ?? _getMLEnhancementFormulaDoc();
    final candidateAdjustments =
        _scoringData['candidate_adjustments'];
    final weights = _scoringData['weights'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Heuristic Scoring Formula',
            'Complete breakdown of _score_candidate() implementation',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildFormulaCard(
            context,
            'Baseline Score',
            '0.5',
            'Starting score for all candidates before adjustments',
          ),
          const SizedBox(height: DesignSystem.spacingM),

          _buildSectionHeader(
            context,
            'Factor Weights',
            'Additive adjustments applied when conditions are met',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildWeightsTable(context, weights),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Behavioral Pattern Adjustments',
            'Applied only when NOT cold_start AND evidence_strength ∈ {MEDIUM, HIGH}',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildPatternAdjustmentsTable(context),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Candidate Baseline Adjustments',
            'Per-candidate offsets applied after all factors',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildCandidateBaselinesTable(context, candidateAdjustments),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Eligibility Gates (Hard Exclusions)',
            'Candidates excluded before scoring if triggered',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildEligibilityGatesTable(context),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'ML Enhancement (Hybrid Scoring)',
            'Applied when ML_RECOMMENDATIONS_ENABLED=true AND active model exists',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildMLEnhancementCard(context, mlFormula),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Interactive Calculator',
            'Test scoring with custom feature values (illustrative only)',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildScoringCalculator(context),
        ],
      ),
    );
  }

  Widget _buildFormulaCard(
    BuildContext context,
    String title,
    String formula,
    String description,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: DesignSystem.title(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
            ),
            child: Text(
              formula,
              style: DesignSystem.caption(context).copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            description,
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightsTable(
    BuildContext context,
    Object? weights,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _asScoringRows(
      weights,
      nameKey: 'name',
      valueKey: 'weight',
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Factor',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Weight',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Condition',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final name = row['name']?.toString() ?? 'Unknown';
            final rawWeight = row['weight'];
            final weight = rawWeight is num
                ? rawWeight
                : num.tryParse(rawWeight?.toString() ?? '');
            final weightStr = rawWeight?.toString() ?? 'N/A';
            final color = weight is num && weight > 0
                ? DesignSystem.getSemanticColor(context, SemanticColor.success)
                : weight is num && weight < 0
                ? DesignSystem.getSemanticColor(context, SemanticColor.error)
                : DesignSystem.getSemanticColor(context, SemanticColor.primary);
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      name,
                      style: DesignSystem.caption(context)
                          .copyWith(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      weightStr,
                      style: DesignSystem.body(context)
                          .copyWith(fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row['condition']?.toString() ??
                          _getConditionForWeight(name),
                      style: DesignSystem.body(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getConditionForWeight(String key) {
    const conditions = {
      'baseline': 'Starting score for all candidates',
      'session_length_factor': 'session_length_minutes > 30',
      'time_since_break_factor': 'time_since_break >= preferred_interval * 0.8',
      'high_completion_penalty': 'recent_task_completion_rate > 0.8',
      'high_fatigue_boost':
          'wellbeing_fatigue > 0.6 (SHORT_BREAK, WALK, STRETCH)',
      'low_fatigue_penalty': 'wellbeing_fatigue < 0.3 (SHORT_BREAK, WALK)',
      'low_recovery_boost':
          'wellbeing_recovery < 0.4 (WALK, STRETCH, SHORT_BREAK)',
      'high_recovery_recent_break_penalty':
          'wellbeing_recovery > 0.7 AND time_since_break < 20',
      'low_workload_boost': 'wellbeing_workload < 0.4 (SHORT_BREAK, LUNCH)',
      'stress_boost_per_factor':
          'wellbeing_stress_count > 0 (WALK, STRETCH), max 0.15',
      'stress_boost_max': 'Cap on stress boost',
      'pattern_REPEATED_SKIPPED_BREAKS':
          'Pattern detected, evidence MEDIUM/HIGH (SHORT_BREAK)',
      'pattern_INSUFFICIENT_RECOVERY':
          'Pattern detected, evidence MEDIUM/HIGH (WALK, SHORT_BREAK)',
      'pattern_RECURRING_FATIGUE_STRESS':
          'Pattern detected, evidence MEDIUM/HIGH (WALK, STRETCH)',
      'pattern_DECLINING_MEASURABLE_FOCUS':
          'Pattern detected, evidence MEDIUM/HIGH (SHORT_BREAK)',
      'pattern_RECURRING_OVERWORK':
          'Pattern detected, evidence MEDIUM/HIGH (LUNCH, SHORT_BREAK)',
    };
    return conditions[key] ?? '';
  }

  Widget _buildPatternAdjustmentsTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final patterns = [
      {
        'pattern': 'REPEATED_SKIPPED_BREAKS',
        'weight': 0.15,
        'candidates': 'SHORT_BREAK',
        'evidence': 'MEDIUM or HIGH',
        'description':
            'User frequently skips recommended breaks (≥3 of last 10)',
      },
      {
        'pattern': 'INSUFFICIENT_RECOVERY',
        'weight': 0.12,
        'candidates': 'WALK, SHORT_BREAK',
        'evidence': 'MEDIUM or HIGH',
        'description':
            'Breaks don\'t restore wellbeing (recovery < 0.4 consistently)',
      },
      {
        'pattern': 'RECURRING_FATIGUE_STRESS',
        'weight': 0.15,
        'candidates': 'WALK, STRETCH',
        'evidence': 'MEDIUM or HIGH',
        'description':
            'High fatigue + stress co-occurrence (≥3 recent check-ins)',
      },
      {
        'pattern': 'DECLINING_MEASURABLE_FOCUS',
        'weight': 0.10,
        'candidates': 'SHORT_BREAK',
        'evidence': 'MEDIUM or HIGH',
        'description':
            'Task focus rate declining (slope < -0.05 over 5 sessions)',
      },
      {
        'pattern': 'RECURRING_OVERWORK',
        'weight': 0.12,
        'candidates': 'LUNCH, SHORT_BREAK',
        'evidence': 'MEDIUM or HIGH',
        'description':
            'Sessions consistently exceed preferred hours (>90th pctl)',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Pattern',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Weight',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Candidates',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Evidence Required',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Detection Logic',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...patterns.asMap().entries.map((entry) {
            final index = entry.key;
            final p = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      p['pattern']?.toString() ?? '',
                      style: DesignSystem.caption(context)
                          .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '+${p['weight']}',
                      style: DesignSystem.body(context).copyWith(
                        color: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.success,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p['candidates']?.toString() ?? '',
                      style: DesignSystem.body(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p['evidence']?.toString() ?? '',
                      style: DesignSystem.body(context).copyWith(
                        color: DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.warning,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      p['description']?.toString() ?? '',
                      style: DesignSystem.body(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCandidateBaselinesTable(
    BuildContext context,
    Object? adjustments,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _asScoringRows(
      adjustments,
      nameKey: 'candidate',
      valueKey: 'baseline',
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Candidate',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Baseline Adjustment',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Rationale',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final candidate = row['candidate']?.toString() ?? 'Unknown';
            final rawAdjustment = row['baseline'];
            final adjustment = rawAdjustment is num
                ? rawAdjustment
                : num.tryParse(rawAdjustment?.toString() ?? '') ?? 0;
            final color = adjustment < 0
                ? DesignSystem.getSemanticColor(context, SemanticColor.error)
                : DesignSystem.getSemanticColor(context, SemanticColor.primary);
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      candidate,
                      style: DesignSystem.caption(context)
                          .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${adjustment >= 0 ? '+' : ''}$adjustment',
                      style: DesignSystem.body(context)
                          .copyWith(fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _getCandidateRationale(candidate),
                      style: DesignSystem.body(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getCandidateRationale(String candidate) {
    const rationales = {
      'SHORT_BREAK': 'Reference baseline (no adjustment)',
      'WALK': 'Slightly higher effort than short break',
      'HYDRATE': 'Lowest priority - can be done at desk',
      'STRETCH': 'Slightly higher effort than short break',
      'LUNCH': 'Longest duration, major schedule disruption',
    };
    return rationales[candidate] ?? '';
  }

  Widget _buildEligibilityGatesTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gates = [
      {
        'name': 'Active Break Gate',
        'condition': 'has_active_break == true',
        'action': 'score = 0.0 (excluded from all candidates)',
        'rationale': 'User already on break; no new recommendation needed',
      },
      {
        'name': 'Lunch Cooldown Gate',
        'condition': 'last_break_duration_minutes >= 60 AND time_since_last_break_minutes < 180',
        'action': 'score = 0.0 (excluded from all candidates)',
        'rationale': 'Recent long break (≥60min) within 3 hours; suppress new recommendations',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: gates.asMap().entries.map((entry) {
          final index = entry.key;
          final g = entry.value;
          final rowColor = index.isEven
              ? (isDark ? Colors.transparent : Colors.grey.shade50)
              : (isDark ? Colors.white10 : Colors.transparent);
          return Container(
            color: rowColor,
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.gpp_maybe,
                      size: 18,
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ),
                    ),
                    const SizedBox(width: DesignSystem.spacingS),
                    Text(
                      g['name']!,
                      style: DesignSystem.title(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSystem.spacingS),
                _buildDetailLine(
                  context,
                  'Condition',
                  g['condition']!,
                  isCode: true,
                ),
                _buildDetailLine(context, 'Action', g['action']!, isCode: true),
                _buildDetailLine(context, 'Rationale', g['rationale']!),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMLEnhancementCard(
    BuildContext context,
    Map<String, dynamic> formula,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.info,
          ).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.info,
                ),
              ),
              const SizedBox(width: DesignSystem.spacingS),
              Text(
                'ML Enhancement Formula',
                style: DesignSystem.title(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildDetailLine(context, 'Condition', formula['condition'] ?? ''),
          _buildDetailLine(
            context,
            'Hybrid Formula',
            formula['formula'] ?? '',
            isCode: true,
          ),
          _buildDetailLine(
            context,
            'ML Enhancement',
            formula['ml_enhancement'] ?? '',
            isCode: true,
          ),
          _buildDetailLine(
            context,
            'Display Probability',
            formula['ml_probability_display'] ?? '',
            isCode: true,
          ),
          _buildDetailLine(
            context,
            'Output Bounds',
            formula['bounds'] ?? '',
            isCode: true,
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.info,
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
            ),
            child: Text(
              formula['note'] ?? 'ML predicts acceptance probability, not standalone recommendation score',
              style: DesignSystem.body(context).copyWith(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.info,
                ),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailLine(
    BuildContext context,
    String label,
    String value, {
    bool isCode = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: DesignSystem.body(context).copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (isCode ? DesignSystem.caption : DesignSystem.body)(
                context,
              ).copyWith(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoringCalculator(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calculate,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
              ),
              const SizedBox(width: DesignSystem.spacingS),
              Text(
                'Interactive Heuristic Calculator',
                style: DesignSystem.title(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: DesignSystem.getSemanticColor(
                context,
                SemanticColor.warning,
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
              border: Border.all(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.warning,
                ).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.warning,
                  ),
                ),
                const SizedBox(width: DesignSystem.spacingS),
                Expanded(
                  child: Text(
                    'Illustrative only — does not execute backend code. Uses the documented formula weights. ML enhancement not calculated.',
                    style: DesignSystem.body(context).copyWith(
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignSystem.spacingL),
          _ScoringCalculatorWidget(),
        ],
      ),
    );
  }

  // ==================== TAB 5: MODEL PERFORMANCE ====================
  Widget _buildModelPerformanceTab(BuildContext context) {
    final liveEvaluation = _asStringKeyedMap(
      _modelPerformanceData['live_evaluation'],
    );
    final parsedMetrics = _asStringKeyedMap(liveEvaluation?['metrics']);
    final metrics = parsedMetrics ?? <String, dynamic>{};
    final cvMetrics = _asStringKeyedMap(metrics['cv_metrics']);
    final benchmark = _asStringKeyedMap(
      _modelPerformanceData['historical_benchmark'],
    );
    final confusionMatrix = _parseConfusionMatrix(
      liveEvaluation?['confusion_matrix'] ?? metrics['confusion_matrix'],
    );
    final featureImportance = _parseFeatureImportance(
      _featureImportanceData['feature_importance'],
    );
    final hasLiveModel =
        _modelPerformanceData['has_live_model'] == true &&
        liveEvaluation != null &&
        parsedMetrics != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Model Performance',
            'Live evaluation metrics and candidate selection',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildCandidateSelector(context),
          const SizedBox(height: DesignSystem.spacingL),

          if (!hasLiveModel) ...[
            _buildNoModelState(context),
          ] else ...[
            _buildModelInfoCard(
              context,
              liveEvaluation['model_id']?.toString(),
              liveEvaluation['model_version']?.toString(),
              liveEvaluation['training_date']?.toString(),
              _modelPerformanceData['dataset_context']?.toString(),
              liveEvaluation['is_active'] == true,
              liveEvaluation['validation_status']?.toString() ?? 'PENDING',
              liveEvaluation['training_job_id']?.toString() ?? 'N/A',
              liveEvaluation['is_eligible_for_activation'] == true,
            ),
            const SizedBox(height: DesignSystem.spacingL),
            _buildMetricsGrid(context, metrics),
            const SizedBox(height: DesignSystem.spacingL),
            if (confusionMatrix != null) ...[
              _buildSectionHeader(
                context,
                'Confusion Matrix',
                'Confusion matrix from the live model evaluation',
              ),
              const SizedBox(height: DesignSystem.spacingM),
              MLConfusionMatrixChart(matrix: confusionMatrix),
              const SizedBox(height: DesignSystem.spacingL),
            ],
            if (cvMetrics != null && cvMetrics['cv_available'] == true) ...[
              _buildSectionHeader(
                context,
                'Cross-Validation Details',
                'StratifiedKFold (5 folds) metrics with standard deviation',
              ),
              const SizedBox(height: DesignSystem.spacingM),
              _buildCVMetricsTable(context, cvMetrics),
              const SizedBox(height: DesignSystem.spacingL),
            ],
            if (featureImportance.isEmpty) ...[
              const SizedBox(height: DesignSystem.spacingM),
              Text(
                'Feature importance is unavailable for this model.',
                style: DesignSystem.body(context),
              ),
            ] else ...[
              _buildSectionHeader(
                context,
                'Feature Importance',
                'Backend-provided absolute coefficients from the trained model',
              ),
              const SizedBox(height: DesignSystem.spacingM),
              MLFeatureImportanceChart(
                features: featureImportance,
                magnitudeOnly: true,
              ),
              const SizedBox(height: DesignSystem.spacingL),
            ],
          ],
          if (benchmark != null) ...[
            if (hasLiveModel) const SizedBox(height: DesignSystem.spacingL),
            _buildHistoricalBenchmarkCard(context, benchmark),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _asStringKeyedMap(Object? value) {
    if (value is! Map) return null;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return null;
      result[entry.key] = entry.value;
    }
    return result;
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .map(_asStringKeyedMap)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _asScoringRows(
    Object? value, {
    required String nameKey,
    required String valueKey,
  }) {
    if (value is List) return _asMapList(value);
    if (value is! Map) return <Map<String, dynamic>>[];
    return value.entries.map((entry) => <String, dynamic>{
          nameKey: entry.key.toString(),
          valueKey: entry.value,
        }).toList();
  }

  List<List<int>>? _parseConfusionMatrix(Object? value) {
    if (value is! List || value.length != 2) return null;
    final matrix = <List<int>>[];
    for (final row in value) {
      if (row is! List || row.length != 2) return null;
      final parsedRow = <int>[];
      for (final cell in row) {
        if (cell is! num ||
            !cell.isFinite ||
            cell < 0 ||
            cell != cell.roundToDouble()) {
          return null;
        }
        parsedRow.add(cell.toInt());
      }
      matrix.add(parsedRow);
    }
    return matrix;
  }

  List<Map<String, dynamic>> _parseFeatureImportance(Object? value) {
    if (value != null && value is! Map) return [];
    final data = _asStringKeyedMap(value);
    if (data == null) return [];
    final features = <Map<String, dynamic>>[];
    for (final entry in data.entries) {
      final importance = entry.value;
      if (importance is num &&
          importance.isFinite &&
          importance >= 0) {
        features.add({
          'name': entry.key,
          'importance': importance.toDouble(),
        });
      }
    }
    return features;
  }

  Widget _buildHistoricalBenchmarkCard(
    BuildContext context,
    Map<String, dynamic> benchmark,
  ) {
    final confusionMatrix = _parseConfusionMatrix(
      benchmark['confusion_matrix'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          'Historical Thesis Benchmark',
          'Reference metrics from ${benchmark['source'] ?? 'the backend'}; these are not live-model results.',
        ),
        const SizedBox(height: DesignSystem.spacingM),
        _buildInfoCard(context, [
          _buildInfoRow(
            context,
            'Model',
            benchmark['model_name']?.toString() ?? 'Historical benchmark',
          ),
          _buildInfoRow(
            context,
            'Train / Test Samples',
            '${benchmark['train_set_size'] ?? 'N/A'} / ${benchmark['test_set_size'] ?? 'N/A'}',
          ),
          _buildInfoRow(context, 'Accuracy', _formatMetric(benchmark['accuracy'])),
          _buildInfoRow(
            context,
            'Precision',
            _formatMetric(benchmark['precision']),
          ),
          _buildInfoRow(context, 'Recall', _formatMetric(benchmark['recall'])),
          _buildInfoRow(
            context,
            'F1-Score',
            _formatMetric(benchmark['f1_score']),
          ),
          _buildInfoRow(
            context,
            'ROC-AUC',
            _formatMetric(benchmark['roc_auc']),
          ),
        ]),
        if (confusionMatrix != null) ...[
          const SizedBox(height: DesignSystem.spacingM),
          MLConfusionMatrixChart(
            matrix: confusionMatrix,
            label: 'Historical Benchmark Confusion Matrix',
          ),
        ],
      ],
    );
  }

  String _formatMetric(Object? value) =>
      value is num && value.isFinite ? value.toStringAsFixed(3) : 'N/A';

  Widget _buildNoModelState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.model_training,
            size: 64,
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
          const SizedBox(height: DesignSystem.spacingL),
          Text(
            'No Production Model Deployed',
            style: DesignSystem.titleXXL(context)
                .copyWith(color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            'A production-trained LogisticRegression model has not been trained and activated. The system currently operates in cold-start heuristic-only mode.',
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignSystem.spacingL),
          _buildInfoCard(context, [
            _buildInfoRow(
              context,
              'Inference Mode',
              'Heuristic-only (cold-start-baseline)',
            ),
            _buildInfoRow(context, 'ML_RECOMMENDATIONS_ENABLED', 'false'),
            _buildInfoRow(context, 'Active Model', 'None'),
            _buildInfoRow(
              context,
              'Training Requirement',
              '≥20 labeled samples, ≥5 per class',
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildCandidateSelector(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableModels = _asMapList(_modelPerformanceData['available_models']);
    if (availableModels.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt, size: 18, color: DesignSystem.getSemanticColor(context, SemanticColor.primary)),
              const SizedBox(width: DesignSystem.spacingS),
              Text(
                'Available Candidate Models (${availableModels.length})',
                style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          DropdownButtonFormField<String>(
            value: _selectedModelId ?? (availableModels.isNotEmpty ? availableModels[0]['model_id']?.toString() : null),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignSystem.radiusS)),
              labelText: 'Select Model Candidate to Inspect',
            ),
            items: availableModels.map((m) {
              final version = m['model_version'] ?? 'Unknown';
              final isActive = m['is_active'] == true;
              final status = m['validation_status'] ?? 'PENDING';
              final label = '$version ${isActive ? '(Active Production)' : ''} — Validation: $status';
              return DropdownMenuItem<String>(
                value: m['model_id']?.toString(),
                child: Text(label, style: DesignSystem.body(context)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedModelId = val;
                });
                _loadModelPerformance();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModelInfoCard(
    BuildContext context,
    String? modelId,
    String? version,
    String? timestamp,
    String? dataset,
    bool isActive,
    String validationStatus,
    String trainingJobId,
    bool isEligible,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = validationStatus == 'PASSED'
        ? Colors.green
        : validationStatus == 'FAILED'
            ? Colors.red
            : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.model_training,
                color: statusColor,
              ),
              const SizedBox(width: DesignSystem.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Active Production Model' : 'Inactive Candidate Model',
                      style: DesignSystem.title(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    Text(
                      'Validation Status: $validationStatus',
                      style: DesignSystem.body(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (isActive)
                ElevatedButton.icon(
                  onPressed: _deactivateModels,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Deactivate Model'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                )
              else if (modelId != null && modelId.isNotEmpty)
                Tooltip(
                  message: isEligible ? 'Candidate is validated and ready for activation' : 'Activation blocked: validation status must be PASSED',
                  child: ElevatedButton.icon(
                    onPressed: isEligible ? () => _activateModel(modelId, version ?? 'Candidate') : null,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Activate Model'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEligible ? Colors.green : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildInfoRow(context, 'Model Version', version ?? 'Unknown'),
          _buildInfoRow(context, 'Algorithm', 'Logistic Regression (V2 schema)'),
          _buildInfoRow(context, 'Training Job ID', trainingJobId),
          _buildInfoRow(
            context,
            'Evaluation Dataset',
            dataset ?? 'Production labeled data',
          ),
          _buildInfoRow(context, 'Evaluated At', timestamp ?? 'Unknown'),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(BuildContext context, Map<String, dynamic> metrics) {
    final sampleCount = metrics['sample_count'] ?? metrics['train_samples'];
    final metricCards = <_PerformanceMetricCardData>[
      _PerformanceMetricCardData(
        label: 'Accuracy',
        value: _formatMetric(metrics['accuracy']),
        description: 'Overall correct predictions',
        icon: Icons.analytics,
      ),
      _PerformanceMetricCardData(
        label: 'Precision',
        value: _formatMetric(metrics['precision']),
        description: 'Of predicted accepted, actually accepted',
        icon: Icons.precision_manufacturing,
      ),
      _PerformanceMetricCardData(
        label: 'Recall',
        value: _formatMetric(metrics['recall']),
        description: 'Of actual accepted, correctly predicted',
        icon: Icons.fact_check,
      ),
      _PerformanceMetricCardData(
        label: 'F1-Score',
        value: _formatMetric(metrics['f1']),
        description: 'Harmonic mean of precision & recall',
        icon: Icons.balance,
      ),
      _PerformanceMetricCardData(
        label: 'ROC-AUC',
        value: _formatMetric(metrics['roc_auc']),
        description: 'Discrimination ability across thresholds',
        icon: Icons.show_chart,
      ),
      _PerformanceMetricCardData(
        label: 'Evaluation Samples',
        value: sampleCount?.toString() ?? 'N/A',
        description: 'Labeled records used for evaluation',
        icon: Icons.dataset,
      ),
    ];

    return Wrap(
      spacing: DesignSystem.spacingM,
      runSpacing: DesignSystem.spacingM,
      children: metricCards.map((m) => _buildMetricCard(context, m)).toList(),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    _PerformanceMetricCardData metric,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                metric.icon,
                size: 20,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
              ),
              const SizedBox(width: DesignSystem.spacingS),
              Expanded(
                child: Text(
                  metric.label,
                  style: DesignSystem.labelMedium(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            metric.value,
            style: DesignSystem.titleXXXL(context).copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            metric.description,
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildCVMetricsTable(
    BuildContext context,
    Map<String, dynamic> metrics,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cvMetrics = [
      {
        'metric': 'Accuracy',
        'mean': metrics['cv_accuracy_mean'],
        'std': metrics['cv_accuracy_std'],
      },
      {
        'metric': 'Precision',
        'mean': metrics['cv_precision_mean'],
        'std': metrics['cv_precision_std'],
      },
      {
        'metric': 'Recall',
        'mean': metrics['cv_recall_mean'],
        'std': metrics['cv_recall_std'],
      },
      {
        'metric': 'F1-Score',
        'mean': metrics['cv_f1_mean'],
        'std': metrics['cv_f1_std'],
      },
      {
        'metric': 'ROC-AUC',
        'mean': metrics['cv_roc_auc_mean'],
        'std': metrics['cv_roc_auc_std'],
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Metric',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Mean',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Std Dev',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...cvMetrics.asMap().entries.map((entry) {
            final index = entry.key;
            final m = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      m['metric']!,
                      style: DesignSystem.body(context)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      m['mean']?.toStringAsFixed(4) ?? 'N/A',
                      style: DesignSystem.caption(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '± ${m['std']?.toStringAsFixed(4) ?? 'N/A'}',
                      style: DesignSystem.caption(context).copyWith(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ==================== TAB 6: TRAINING & FEEDBACK ====================
  Widget _buildTrainingFeedbackTab(BuildContext context) {
    final labeledCount = _trainingData['labeled_count'] ?? _trainingData['labeled_feedback'] ?? 0;
    final acceptedCount = _trainingData['accepted_count'] ?? _trainingData['accepted'] ?? 0;
    final dismissedCount = _trainingData['dismissed_count'] ?? _trainingData['dismissed'] ?? 0;
    final ignoredCount = _trainingData['ignored_count'] ?? _trainingData['ignored'] ?? 0;
    final minRequired = _trainingData['min_required'] ?? 20;
    final minPerClass = _trainingData['min_per_class'] ?? 5;
    final sufficient = _trainingData['sufficient_for_training'] ?? false;
    final classDist =
        _trainingData['class_distribution'] ?? {'positive': 0, 'negative': 0};
    final history = _trainingData['training_history'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Training Actions',
            'Trigger candidate model training and inspect job status',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildTrainingActionsCard(context, sufficient, labeledCount, minRequired),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Training Readiness',
            'Current labeled dataset status vs. training requirements',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildTrainingReadinessCard(
            context,
            labeledCount,
            minRequired,
            acceptedCount,
            dismissedCount,
            ignoredCount,
            sufficient,
            minPerClass,
          ),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Feedback Label Distribution',
            'User actions mapped to training labels',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildFeedbackDistributionCard(
            context,
            acceptedCount,
            dismissedCount,
            ignoredCount,
            classDist,
          ),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Labeling Rules',
            'How user actions map to binary classification labels',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildLabelingRulesTable(context),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Training Requirements',
            'Exact thresholds from ml_training_pipeline.py',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildTrainingRequirementsCard(context, minRequired, minPerClass),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Training History',
            'Record of model training attempts',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildTrainingHistoryCard(context, history),
          const SizedBox(height: DesignSystem.spacingL),

          _buildSectionHeader(
            context,
            'Training Pipeline Stages',
            'What happens when training is triggered',
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildTrainingPipelineStages(context),
        ],
      ),
    );
  }

  Widget _buildTrainingReadinessCard(
    BuildContext context,
    int labeled,
    int minRequired,
    int accepted,
    int dismissed,
    int ignored,
    bool sufficient,
    int minPerClass,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = (labeled / minRequired).clamp(0.0, 1.0);
    final classBalance = accepted >= minPerClass && dismissed >= minPerClass;
    final remaining = minRequired - labeled;

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sufficient ? Icons.check_circle : Icons.schedule,
                color: sufficient
                    ? DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.success,
                      )
                    : DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ),
                size: 28,
              ),
              const SizedBox(width: DesignSystem.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sufficient
                          ? 'Sufficient for Training'
                          : 'Insufficient for Training',
                      style: DesignSystem.title(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: sufficient
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.success,
                              )
                            : DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.warning,
                              ),
                      ),
                    ),
                    Text(
                      sufficient
                          ? 'All requirements met. Training can be initiated via /admin/ml/train'
                          : '$remaining more labeled samples needed (minimum $minRequired)',
                      style: DesignSystem.body(context).copyWith(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingL),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              sufficient
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.primary,
                    ),
            ),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Row(
            children: [
              Expanded(
                child: _buildRequirementItem(
                  context,
                  'Total Labeled',
                  '$labeled / $minRequired',
                  progress >= 1.0,
                ),
              ),
              Expanded(
                child: _buildRequirementItem(
                  context,
                  'Accepted (positive)',
                  '$accepted / $minPerClass',
                  accepted >= minPerClass,
                ),
              ),
              Expanded(
                child: _buildRequirementItem(
                  context,
                  'Dismissed (negative)',
                  '$dismissed / $minPerClass',
                  dismissed >= minPerClass,
                ),
              ),
              Expanded(
                child: _buildRequirementItem(
                  context,
                  'Ignored (negative)',
                  '$ignored / $minPerClass',
                  true,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: classBalance
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    ).withValues(alpha: 0.1)
                  : DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.warning,
                    ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
              border: Border.all(
                color: classBalance
                    ? DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.success,
                      ).withValues(alpha: 0.3)
                    : DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.warning,
                      ).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  classBalance
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  color: classBalance
                      ? DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.success,
                        )
                      : DesignSystem.getSemanticColor(
                          context,
                          SemanticColor.warning,
                        ),
                  size: 20,
                ),
                const SizedBox(width: DesignSystem.spacingS),
                Text(
                  classBalance
                      ? 'Class balance requirement MET (≥5 per class)'
                      : 'Class balance requirement NOT MET (need ≥5 accepted AND ≥5 dismissed)',
                  style: DesignSystem.body(context).copyWith(
                    fontWeight: FontWeight.w500,
                    color: classBalance
                        ? DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.success,
                          )
                        : DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.warning,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementItem(
    BuildContext context,
    String label,
    String value,
    bool met,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              value,
              style: DesignSystem.body(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              met ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: met
                  ? DesignSystem.getSemanticColor(
                      context,
                      SemanticColor.success,
                    )
                  : DesignSystem.getSemanticColor(context, SemanticColor.error),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeedbackDistributionCard(
    BuildContext context,
    int accepted,
    int dismissed,
    int ignored,
    Map<String, dynamic> classDist,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final positive = classDist['positive'] ?? accepted;
    final negative = classDist['negative'] ?? (dismissed + ignored);

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildClassStat(
                  context,
                  'Positive (Accepted + Helpful)',
                  positive.toString(),
                  DesignSystem.getSemanticColor(context, SemanticColor.success),
                  Icons.thumb_up,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
              Expanded(
                child: _buildClassStat(
                  context,
                  'Negative (Dismissed + Ignored + Not Helpful)',
                  negative.toString(),
                  DesignSystem.getSemanticColor(context, SemanticColor.error),
                  Icons.thumb_down,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingL),
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(DesignSystem.radiusM),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRawCount(
                  context,
                  'Accepted',
                  accepted,
                  DesignSystem.getSemanticColor(context, SemanticColor.success),
                ),
                _buildRawCount(
                  context,
                  'Dismissed',
                  dismissed,
                  DesignSystem.getSemanticColor(context, SemanticColor.error),
                ),
                _buildRawCount(
                  context,
                  'Ignored',
                  ignored,
                  DesignSystem.getSemanticColor(context, SemanticColor.warning),
                ),
                _buildRawCount(
                  context,
                  'Helpful',
                  _trainingData['helpful_count'] ?? 0,
                  DesignSystem.getSemanticColor(context, SemanticColor.info),
                ),
                _buildRawCount(
                  context,
                  'Not Helpful',
                  _trainingData['not_helpful_count'] ?? 0,
                  DesignSystem.getSemanticColor(
                    context,
                    SemanticColor.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassStat(
    BuildContext context,
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: DesignSystem.spacingS),
        Text(
          value,
          style: DesignSystem.titleXXXL(context)
              .copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: DesignSystem.spacingS),
        Text(
          label,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRawCount(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          label,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          count.toString(),
          style: DesignSystem.body(context)
              .copyWith(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }

  Widget _buildLabelingRulesTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rules = [
      {
        'action': 'accepted',
        'label': '1 (Positive)',
        'description': 'User explicitly accepted the recommendation',
      },
      {
        'action': 'helpful',
        'label': '1 (Positive)',
        'description': 'User marked recommendation as helpful',
      },
      {
        'action': 'dismissed',
        'label': '0 (Negative)',
        'description': 'User explicitly dismissed the recommendation',
      },
      {
        'action': 'ignored',
        'label': '0 (Negative)',
        'description': 'Recommendation expired without user action',
      },
      {
        'action': 'not_helpful',
        'label': '0 (Negative)',
        'description': 'User marked recommendation as not helpful',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'User Action',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Training Label',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Description',
                    style: DesignSystem.labelLarge(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...rules.asMap().entries.map((entry) {
            final index = entry.key;
            final r = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final isPositive = r['label']!.contains('Positive');
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      r['action']!,
                      style: DesignSystem.caption(context).copyWith(
                        color: isPositive
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.success,
                              )
                            : DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.error,
                              ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isPositive
                                    ? DesignSystem.getSemanticColor(
                                        context,
                                        SemanticColor.success,
                                      )
                                    : DesignSystem.getSemanticColor(
                                        context,
                                        SemanticColor.error,
                                      ))
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          DesignSystem.radiusS,
                        ),
                      ),
                      child: Text(
                        r['label']!,
                        style: DesignSystem.labelMedium(context).copyWith(
                          color: isPositive
                              ? DesignSystem.getSemanticColor(
                                  context,
                                  SemanticColor.success,
                                )
                              : DesignSystem.getSemanticColor(
                                  context,
                                  SemanticColor.error,
                                ),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      r['description']!,
                      style: DesignSystem.body(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTrainingRequirementsCard(
    BuildContext context,
    int minRequired,
    int minPerClass,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'From ml_training_pipeline.py',
            style: DesignSystem.caption(context).copyWith(fontSize: 12),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildRequirementRow(
            context,
            'MINIMUM_TRAINING_SAMPLES',
            minRequired.toString(),
            'Minimum total labeled feedback records required',
          ),
          _buildRequirementRow(
            context,
            'MIN_PER_CLASS',
            minPerClass.toString(),
            'Minimum samples per class (positive & negative)',
          ),
          _buildRequirementRow(
            context,
            'DATASET_CONTEXT',
            'production',
            'Excludes test/demo users & dev_demo/is_test_data flags',
          ),
          _buildRequirementRow(
            context,
            'ALGORITHM',
            'LogisticRegression',
            'With ColumnTransformer: StandardScaler + OneHotEncoder',
          ),
          _buildRequirementRow(
            context,
            'CV_STRATEGY',
            'StratifiedKFold(5)',
            'GroupKFold by user if >50 samples',
          ),
          _buildRequirementRow(
            context,
            'RANDOM_STATE',
            '42',
            'Reproducible training',
          ),
          _buildRequirementRow(
            context,
            'MAX_ITER',
            '1000',
            'LogisticRegression convergence',
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(
    BuildContext context,
    String constant,
    String value,
    String description,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              constant,
              style: DesignSystem.caption(context).copyWith(
                fontSize: 12,
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.primary,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              value,
              style: DesignSystem.body(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: DesignSystem.body(
                context,
              ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingHistoryCard(
    BuildContext context,
    List<dynamic> history,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: history.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(DesignSystem.spacingXL),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                    const SizedBox(height: DesignSystem.spacingM),
                    Text(
                      'No Training History',
                      style: DesignSystem.title(context).copyWith(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: DesignSystem.spacingS),
                    Text(
                      'No model training has been attempted yet',
                      style: DesignSystem.body(context).copyWith(
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: _asMapList(history)
                  .map((h) => _buildHistoryItem(context, h))
                  .toList(),
            ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, Map<String, dynamic> h) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final success = h['success'] ?? false;
    final metrics = _asStringKeyedMap(h['metrics']);
    final f1 = metrics?['f1'];
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle : Icons.error,
            color: success
                ? DesignSystem.getSemanticColor(context, SemanticColor.success)
                : DesignSystem.getSemanticColor(context, SemanticColor.error),
          ),
          const SizedBox(width: DesignSystem.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h['model_version'] ?? 'Unknown',
                  style: DesignSystem.body(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  '${h['training_date'] ?? ''} • ${h['samples'] ?? 0} samples • ${h['duration_seconds'] ?? 0}s',
                  style: DesignSystem.body(context).copyWith(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (metrics != null)
            Text(
              'F1: ${f1 is num ? f1.toStringAsFixed(3) : 'N/A'}',
              style: DesignSystem.caption(context),
            ),
        ],
      ),
    );
  }

  Widget _buildTrainingPipelineStages(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stages = [
      {
        'stage': '1. Data Extraction',
        'description': '_extract_training_data() — temporal-safe join, excludes test/demo users',
        'function': 'ml_training_pipeline.py',
      },
      {
        'stage': '2. Feature Engineering',
        'description': 'Map extracted features to V2 schema (10 features), handle missing values',
        'function': 'feature_schema.py + ml_training_pipeline.py',
      },
      {
        'stage': '3. Preprocessing',
        'description': 'ColumnTransformer: SimpleImputer(0.0) + StandardScaler (numeric), OneHotEncoder (categorical)',
        'function': '_build_preprocessing_pipeline()',
      },
      {
        'stage': '4. Model Training',
        'description': 'LogisticRegression(random_state=42, max_iter=1000) in Pipeline with preprocessor',
        'function': 'train_model()',
      },
      {
        'stage': '5. Cross-Validation',
        'description': 'StratifiedKFold(5) or GroupKFold by user — accuracy, precision, recall, F1, ROC-AUC',
        'function': '_evaluate_with_cv()',
      },
      {
        'stage': '6. Test Set Evaluation',
        'description':
            '80/20 stratified split — independent test metrics without leakage',
        'function': 'train_model()',
      },
      {
        'stage': '7. Artifact Storage',
        'description': 'joblib.dump(pipeline, ml_models/model_<uuid>.pkl) + MLModel DB record',
        'function': 'train_model()',
      },
      {
        'stage': '8. Admin Activation',
        'description': 'Explicit /admin/ml/activate call — sets is_active=true, deactivates others',
        'function': 'activate_model() / ml_admin.py',
      },
    ];

    return Column(
      children: stages
          .map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: DesignSystem.spacingM),
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.background,
                      )
                    : Colors.white,
                borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: DesignSystem.getSemanticColor(
                            context,
                            SemanticColor.primary,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            DesignSystem.radiusS,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            s['stage']!.split('.')[0],
                            style: DesignSystem.labelMedium(context).copyWith(
                              color: DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.primary,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignSystem.spacingM),
                      Expanded(
                        child: Text(
                          s['stage']!,
                          style: DesignSystem.title(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignSystem.spacingS),
                  Text(
                    s['description']!,
                    style: DesignSystem.body(context).copyWith(
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: DesignSystem.spacingS),
                  Text(
                    'Backend: ${s['function']}',
                    style: DesignSystem.caption(context).copyWith(
                      fontSize: 11,
                      color: DesignSystem.getSemanticColor(
                        context,
                        SemanticColor.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTrainingActionsCard(
    BuildContext context,
    bool sufficient,
    int labeledCount,
    int minRequired,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canTrain = sufficient && !_isTraining;
    final jobStatus = _lastTrainingJob?['status']?.toString() ?? 'None';
    final jobDataset = _lastTrainingJob?['dataset_context']?.toString() ?? '';
    final jobId = _lastTrainingJob?['job_id']?.toString() ?? '';
    final jobMessage = _lastTrainingJob?['message']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Train Model',
                  style: DesignSystem.titleLarge(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: canTrain ? _trainModel : null,
                icon: _isTraining
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.model_training, size: 16),
                label: Text(_isTraining ? 'Training...' : 'Train Model'),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          if (!sufficient)
            Text(
              'Training unavailable: labeled dataset has $labeledCount/$minRequired samples. Collect more feedback to unlock training.',
              style: DesignSystem.body(context).copyWith(
                color: DesignSystem.getSemanticColor(
                  context,
                  SemanticColor.warning,
                ),
              ),
            ),
          if (sufficient)
            Text(
              'Training is available. Click "Train Model" to schedule a candidate training job.',
              style: DesignSystem.body(context),
            ),
          const SizedBox(height: DesignSystem.spacingM),
          Row(
            children: [
              Expanded(
                child: _buildTrainingActionItem(
                  context,
                  'Current Job Status',
                  jobStatus == 'None' ? 'No job scheduled' : jobStatus,
                  Icons.pending_actions,
                ),
              ),
              Expanded(
                child: _buildTrainingActionItem(
                  context,
                  'Last Training Result',
                  jobMessage.isEmpty ? 'No result yet' : jobMessage,
                  Icons.history,
                ),
              ),
              Expanded(
                child: _buildTrainingActionItem(
                  context,
                  'Validation Status',
                  'PENDING (requires admin activation)',
                  Icons.verified_user,
                ),
              ),
            ],
          ),
          if (jobId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DesignSystem.spacingM),
              child: Text(
                'Job ID: $jobId • Dataset: ${jobDataset.isEmpty ? 'production' : jobDataset}',
                style: DesignSystem.caption(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrainingActionItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingM),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: DesignSystem.getSemanticColor(context, SemanticColor.info)),
              const SizedBox(width: DesignSystem.spacingS),
              Text(
                label,
                style: DesignSystem.caption(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingS),
          Text(
            value,
            style: DesignSystem.body(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==================== TAB 7: PREDICTION INSPECTOR ====================
  Widget _buildPredictionInspectorTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Prediction Inspector',
            'Inspect an actual recommendation decision with full trace',
          ),
          const SizedBox(height: DesignSystem.spacingM),

          _buildInspectorInput(context),
          const SizedBox(height: DesignSystem.spacingL),

          if (_inspectorLoading) ...[
            _buildLoadingState(context),
          ] else if (_inspectorError != null) ...[
            _buildErrorCard(context, _inspectorError!),
          ] else if (_predictionInspectorData.isNotEmpty) ...[
            _buildInspectorResults(context),
          ] else ...[
            _buildInspectorEmptyState(context),
          ],
        ],
      ),
    );
  }

  Widget _buildInspectorInput(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter Recommendation ID',
            style: DesignSystem.title(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'e.g., 550e8400-e29b-41d4-a716-446655440000',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DesignSystem.spacingM,
                      vertical: DesignSystem.spacingM,
                    ),
                  ),
                  style: DesignSystem.caption(context),
                ),
              ),
              const SizedBox(width: DesignSystem.spacingM),
              ElevatedButton.icon(
                onPressed: () {
                  final id = controller.text.trim();
                  if (id.isNotEmpty) {
                    _loadPredictionInspector(id);
                  }
                },
                icon: const Icon(Icons.search),
                label: const Text('Inspect'),
              ),
            ],
          ),
          const SizedBox(height: DesignSystem.spacingM),
          Text(
            'Recommendation IDs are stored in the recommendation_feedback table. Use a recent ID from your own recommendations or admin logs.',
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorResults(BuildContext context) {
    final data = _predictionInspectorData;
    final mlUsed = data['ml_used'] ?? false;
    final mlProbability = data['prediction_probability'];
    final heuristicScore = data['recommendation_score'];
    final candidateScores = data['candidate_scores'] ?? [];
    final featuresInput = data['context_features'];
    final features = _asStringKeyedMap(featuresInput);
    final recommendationType = data['recommendation_type'];
    final reason = data['reason'];
    final modelVersion = data['model_version_used'];
    final userAction = data['user_action'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInspectorSection(context, 'Recommendation Summary', [
          _buildInspectorRow(
            context,
            'Recommendation ID',
            data['recommendation_id'] ?? 'N/A',
            isCode: true,
          ),
          _buildInspectorRow(
            context,
            'Selected Type',
            recommendationType ?? 'N/A',
          ),
          _buildInspectorRow(
            context,
            'Final Score',
            heuristicScore?.toStringAsFixed(4) ?? 'N/A',
          ),
          _buildInspectorRow(context, 'Reason', reason ?? 'N/A'),
          _buildInspectorRow(context, 'Model Version', modelVersion ?? 'N/A'),
          _buildInspectorRow(
            context,
            'User Action',
            userAction ?? 'Pending',
            badge: true,
          ),
        ]),
        const SizedBox(height: DesignSystem.spacingL),

        _buildInspectorSection(context, 'ML Inference Status', [
          _buildInspectorRow(
            context,
            'ML Used',
            mlUsed ? 'YES' : 'NO',
            badge: mlUsed,
          ),
          _buildInspectorRow(
            context,
            'ML Probability (P=accepted)',
            mlProbability != null
                ? mlProbability.toStringAsFixed(4)
                : 'N/A (heuristic only)',
          ),
          if (!mlUsed)
            _buildInspectorRow(
              context,
              'Why ML Not Used',
              _getMLNotUsedReason(data),
              isMultiline: true,
            ),
        ]),
        const SizedBox(height: DesignSystem.spacingL),

        _buildInspectorSection(context, 'Extracted Features', [
          if (featuresInput != null && features == null)
            _buildInspectorRow(
              context,
              'Error',
              'Context features data malformed or invalid type (${featuresInput.runtimeType})',
            )
          else if (features == null || features.isEmpty)
            _buildInspectorRow(
              context,
              'Status',
              'No extracted features available',
            )
          else
            ...features.entries
                .map(
                  (e) => _buildInspectorRow(context, e.key, e.value.toString()),
                )
                .toList(),
        ]),
        const SizedBox(height: DesignSystem.spacingL),

        _buildInspectorSection(context, 'Candidate Scores & Ranking', [
          _buildCandidateScoresTable(context, candidateScores),
        ]),
        const SizedBox(height: DesignSystem.spacingL),

        if (data['detected_patterns'] != null) ...[
          _buildInspectorSection(context, 'Detected Behavioral Patterns', [
            _buildPatternsTable(context, data['detected_patterns']),
          ]),
          const SizedBox(height: DesignSystem.spacingL),
        ],
      ],
    );
  }

  Widget _buildInspectorSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusL),
                topRight: Radius.circular(DesignSystem.radiusL),
              ),
            ),
            child: Text(
              title,
              style: DesignSystem.title(context)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorRow(
    BuildContext context,
    String label,
    String value, {
    bool isCode = false,
    bool badge = false,
    bool isMultiline = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: DesignSystem.body(context).copyWith(
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          badge
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getBadgeColor(value).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(DesignSystem.radiusS),
                  ),
                  child: Text(
                    value,
                    style: DesignSystem.labelMedium(context).copyWith(
                      color: _getBadgeColor(value),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignSystem.spacingM),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(DesignSystem.radiusM),
                  ),
                  child: Text(
                    value,
                    style: (isCode ? DesignSystem.caption : DesignSystem.body)(
                      context,
                    ).copyWith(color: isDark ? Colors.white : Colors.black87),
                    maxLines: isMultiline ? null : 1,
                    overflow: isMultiline
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                  ),
                ),
        ],
      ),
    );
  }

  Color _getBadgeColor(String value) {
    switch (value.toLowerCase()) {
      case 'yes':
        return Colors.green;
      case 'no':
        return Colors.red;
      case 'accepted':
        return Colors.green;
      case 'dismissed':
        return Colors.red;
      case 'ignored':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getMLNotUsedReason(Map<String, dynamic> data) {
    final reasons = <String>[];
    if (data['ml_enabled'] != true)
      reasons.add('ML_RECOMMENDATIONS_ENABLED=false');
    if (data['active_model'] == null) reasons.add('No active model deployed');
    if (data['cold_start'] == true)
      reasons.add('Cold start (insufficient labeled feedback)');
    if (data['model_error'] != null)
      reasons.add('Model error: ${data['model_error']}');
    return reasons.isEmpty ? 'Unknown reason' : reasons.join('; ');
  }

  Widget _buildCandidateScoresTable(
    BuildContext context,
    List<dynamic> scores,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (scores.isEmpty) {
      return Text(
        'No candidate scores available',
        style: DesignSystem.body(context)
            .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
      );
    }

    final sortedScores = List<Map<String, dynamic>>.from(scores)
      ..sort(
        (a, b) => (b['final_score'] as num).compareTo(a['final_score'] as num),
      );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusM),
                topRight: Radius.circular(DesignSystem.radiusM),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Rank',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Candidate',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Heuristic',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ML Enh.',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Final',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Selected',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          ...sortedScores.asMap().entries.map((entry) {
            final index = entry.key;
            final s = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final isSelected = index == 0;
            return Container(
              color: rowColor,
              padding: const EdgeInsets.all(DesignSystem.spacingM),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      '#${index + 1}',
                      style: DesignSystem.body(context).copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      s['candidate_type'] ?? '',
                      style: DesignSystem.caption(context)
                          .copyWith(fontSize: 11),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (s['heuristic_score'] as num?)?.toStringAsFixed(4) ??
                          'N/A',
                      style: DesignSystem.body(context),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      s['ml_enhancement'] != null
                          ? (s['ml_enhancement'] as num).toStringAsFixed(4)
                          : '—',
                      style: DesignSystem.body(context).copyWith(
                        color: s['ml_enhancement'] != null
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.success,
                              )
                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      (s['final_score'] as num?)?.toStringAsFixed(4) ?? 'N/A',
                      style: DesignSystem.body(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Expanded(
                    child: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: DesignSystem.getSemanticColor(
                              context,
                              SemanticColor.success,
                            ),
                            size: 20,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildPatternsTable(BuildContext context, List<dynamic> patterns) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detectedPatterns = patterns
        .where((p) => p['detected'] == true)
        .toList();

    if (detectedPatterns.isEmpty) {
      return Text(
        'No patterns detected',
        style: DesignSystem.body(context)
            .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
      ),
      child: Column(
        children: detectedPatterns
            .map(
              (p) => Container(
                padding: const EdgeInsets.all(DesignSystem.spacingM),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _getPatternColor(p['evidence_strength'])
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          DesignSystem.radiusS,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          p['evidence_strength'][0],
                          style: DesignSystem.body(context).copyWith(
                            color: _getPatternColor(p['evidence_strength']),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignSystem.spacingM),
                    Expanded(
                      child: Text(
                        p['pattern_id'] ?? '',
                        style: DesignSystem.caption(context)
                            .copyWith(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: DesignSystem.spacingM),
                    Text(
                      p['description'] ?? '',
                      style: DesignSystem.body(context).copyWith(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Color _getPatternColor(String evidence) {
    switch (evidence) {
      case 'HIGH':
        return Colors.red;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildInspectorEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingXL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
            const SizedBox(height: DesignSystem.spacingL),
            Text(
              'No Recommendation Inspected',
              style: DesignSystem.titleXXL(context)
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: DesignSystem.spacingM),
            Text(
              'Enter a Recommendation ID above to see the full decision trace including extracted features, candidate scores, ML inference, and user feedback.',
              style: DesignSystem.body(
                context,
              ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: DesignSystem.getSemanticColor(
          context,
          SemanticColor.error,
        ).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: DesignSystem.getSemanticColor(
            context,
            SemanticColor.error,
          ).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error,
            color: DesignSystem.getSemanticColor(context, SemanticColor.error),
          ),
          const SizedBox(width: DesignSystem.spacingM),
          Expanded(
            child: Text(
              error,
              style: DesignSystem.body(context)
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPER WIDGETS ====================
  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: DesignSystem.titleXXL(context).copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: DesignSystem.body(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, List<Widget> rows) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSystem.spacingL),
      decoration: BoxDecoration(
        color: isDark
            ? DesignSystem.getSemanticColor(context, SemanticColor.background)
            : Colors.white,
        borderRadius: BorderRadius.circular(DesignSystem.radiusL),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(children: rows),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSystem.spacingM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: DesignSystem.labelMedium(context).copyWith(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: DesignSystem.body(context)
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusGrid(BuildContext context, List<Widget> cards) {
    return Wrap(
      spacing: DesignSystem.spacingM,
      runSpacing: DesignSystem.spacingM,
      children: cards.map((c) => SizedBox(width: 220, child: c)).toList(),
    );
  }
}

// ==================== SUPPORTING CLASSES ====================
class _PerformanceMetricCardData {
  const _PerformanceMetricCardData({
    required this.label,
    required this.value,
    required this.description,
    required this.icon,
  });

  final String label;
  final String value;
  final String description;
  final IconData icon;
}

class _HowItWorksStage {
  final int number;
  final String title;
  final String description;
  final List<String> inputs;
  final String processing;
  final String outputs;
  final String service;

  _HowItWorksStage({
    required this.number,
    required this.title,
    required this.description,
    required this.inputs,
    required this.processing,
    required this.outputs,
    required this.service,
  });
}

// ==================== INTERACTIVE SCORING CALCULATOR ====================
class _ScoringCalculatorWidget extends StatefulWidget {
  @override
  State<_ScoringCalculatorWidget> createState() =>
      _ScoringCalculatorWidgetState();
}

class _ScoringCalculatorWidgetState extends State<_ScoringCalculatorWidget> {
  // Feature inputs
  double sessionLength = 45;
  double timeSinceBreak = 50;
  double completionRate = 0.6;
  double fatigue = 0.5;
  double recovery = 0.5;
  double workload = 0.5;
  double focus = 0.5;
  int stressCount = 0;
  int preferredInterval = 30;
  bool hasActiveBreak = false;
  double lastBreakDuration = 0;
  bool coldStart = true;

  // Pattern flags
  bool patternSkippedBreaks = false;
  bool patternInsufficientRecovery = false;
  bool patternFatigueStress = false;
  bool patternDecliningFocus = false;
  bool patternOverwork = false;

  Map<String, double> _lastScores = {};
  void _calculate() {
    final scores = <String, double>{};
    final candidates = ['SHORT_BREAK', 'WALK', 'HYDRATE', 'STRETCH', 'LUNCH'];

    for (final candidate in candidates) {
      scores[candidate] = _scoreCandidate(candidate);
    }

    setState(() {
      _lastScores = scores;
    });
  }

  double _scoreCandidate(String candidateType) {
    // Eligibility gates
    if (hasActiveBreak) return 0.0;
    if (lastBreakDuration >= 60.0 && timeSinceBreak < 180.0) return 0.0;

    double score = 0.5; // baseline

    // Session length factor
    if (sessionLength > 30) score += 0.15;

    // Time since break factor
    if (timeSinceBreak >= preferredInterval * 0.8) score += 0.15;

    // Completion rate factor
    if (completionRate > 0.8) score -= 0.05;

    // Wellbeing factors
    if (fatigue > 0.6 &&
        ['SHORT_BREAK', 'WALK', 'STRETCH'].contains(candidateType))
      score += 0.12;
    if (fatigue < 0.3 && ['SHORT_BREAK', 'WALK'].contains(candidateType))
      score -= 0.05;

    if (recovery < 0.4 &&
        ['WALK', 'STRETCH', 'SHORT_BREAK'].contains(candidateType))
      score += 0.10;
    if (recovery > 0.7 && timeSinceBreak < 20) score -= 0.10;

    if (workload < 0.4 && ['SHORT_BREAK', 'LUNCH'].contains(candidateType))
      score += 0.10;

    if (stressCount > 0 && ['WALK', 'STRETCH'].contains(candidateType)) {
      score += (0.05 * stressCount).clamp(0.0, 0.15);
    }

    // Behavioral patterns (only when not cold start)
    if (!coldStart) {
      if (patternSkippedBreaks && candidateType == 'SHORT_BREAK') score += 0.15;
      if (patternInsufficientRecovery &&
          ['WALK', 'SHORT_BREAK'].contains(candidateType))
        score += 0.12;
      if (patternFatigueStress && ['WALK', 'STRETCH'].contains(candidateType))
        score += 0.15;
      if (patternDecliningFocus && candidateType == 'SHORT_BREAK')
        score += 0.10;
      if (patternOverwork && ['LUNCH', 'SHORT_BREAK'].contains(candidateType))
        score += 0.12;
    }

    // Candidate baselines
    const baselines = {
      'SHORT_BREAK': 0.0,
      'WALK': -0.02,
      'HYDRATE': -0.05,
      'STRETCH': -0.02,
      'LUNCH': -0.10,
    };
    score += baselines[candidateType] ?? 0.0;

    return score.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inputs
        Wrap(
          spacing: DesignSystem.spacingM,
          runSpacing: DesignSystem.spacingM,
          children: [
            _buildCalculatorInput(
              context,
              'Session Length (min)',
              sessionLength,
              0,
              480,
              (v) => setState(() => sessionLength = v),
            ),
            _buildCalculatorInput(
              context,
              'Time Since Break (min)',
              timeSinceBreak,
              0,
              9999,
              (v) => setState(() => timeSinceBreak = v),
            ),
            _buildCalculatorInput(
              context,
              'Completion Rate',
              completionRate,
              0,
              1,
              (v) => setState(() => completionRate = v),
              step: 0.1,
            ),
            _buildCalculatorInput(
              context,
              'Fatigue (0-1)',
              fatigue,
              0,
              1,
              (v) => setState(() => fatigue = v),
              step: 0.1,
            ),
            _buildCalculatorInput(
              context,
              'Recovery (0-1)',
              recovery,
              0,
              1,
              (v) => setState(() => recovery = v),
              step: 0.1,
            ),
            _buildCalculatorInput(
              context,
              'Workload (0-1)',
              workload,
              0,
              1,
              (v) => setState(() => workload = v),
              step: 0.1,
            ),
            _buildCalculatorInput(
              context,
              'Stress Count',
              stressCount.toDouble(),
              0,
              10,
              (v) => setState(() => stressCount = v.round()),
            ),
            _buildCalculatorInput(
              context,
              'Preferred Interval (min)',
              preferredInterval.toDouble(),
              5,
              120,
              (v) => setState(() => preferredInterval = v.round()),
            ),
          ],
        ),
        const SizedBox(height: DesignSystem.spacingM),

        // Boolean toggles
        Wrap(
          spacing: DesignSystem.spacingM,
          runSpacing: DesignSystem.spacingM,
          children: [
            _buildCalculatorToggle(
              context,
              'Active Break',
              hasActiveBreak,
              (v) => setState(() => hasActiveBreak = v),
            ),
            _buildCalculatorToggle(
              context,
              'Cold Start',
              coldStart,
              (v) => setState(() => coldStart = v),
            ),
          ],
        ),
        const SizedBox(height: DesignSystem.spacingM),

        // Pattern toggles
        Text(
          'Behavioral Patterns (require evidence MEDIUM/HIGH)',
          style: DesignSystem.labelMedium(context)
              .copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
        ),
        const SizedBox(height: DesignSystem.spacingS),
        Wrap(
          spacing: DesignSystem.spacingM,
          runSpacing: DesignSystem.spacingM,
          children: [
            _buildCalculatorToggle(
              context,
              'Skipped Breaks',
              patternSkippedBreaks,
              (v) => setState(() => patternSkippedBreaks = v),
            ),
            _buildCalculatorToggle(
              context,
              'Insufficient Recovery',
              patternInsufficientRecovery,
              (v) => setState(() => patternInsufficientRecovery = v),
            ),
            _buildCalculatorToggle(
              context,
              'Fatigue+Stress',
              patternFatigueStress,
              (v) => setState(() => patternFatigueStress = v),
            ),
            _buildCalculatorToggle(
              context,
              'Declining Focus',
              patternDecliningFocus,
              (v) => setState(() => patternDecliningFocus = v),
            ),
            _buildCalculatorToggle(
              context,
              'Overwork',
              patternOverwork,
              (v) => setState(() => patternOverwork = v),
            ),
          ],
        ),
        const SizedBox(height: DesignSystem.spacingM),

        ElevatedButton.icon(
          onPressed: _calculate,
          icon: const Icon(Icons.calculate),
          label: const Text('Calculate Scores'),
        ),
        const SizedBox(height: DesignSystem.spacingL),

        // Results
        if (_lastScores.isNotEmpty) ...[
          Text(
            'Calculated Scores (Heuristic Only)',
            style: DesignSystem.title(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: DesignSystem.spacingM),
          _buildCalculatorResults(context, _lastScores),
        ],
      ],
    );
  }

  Widget _buildCalculatorInput(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged, {
    double step = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: DesignSystem.body(
              context,
            ).copyWith(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: step == 1
                      ? (max - min).round()
                      : ((max - min) / step).round(),
                  label: value.toStringAsFixed(step == 1 ? 0 : 1),
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  value.toStringAsFixed(step == 1 ? 0 : 1),
                  style: DesignSystem.caption(context).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorToggle(
    BuildContext context,
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label, style: DesignSystem.body(context)),
      ],
    );
  }

  Widget _buildCalculatorResults(
    BuildContext context,
    Object? scoresInput,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scores = _asStringKeyedDoubleMap(scoresInput);
    if (scores == null) {
      return _buildMalformedErrorCard(context, 'Scores', scoresInput);
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(DesignSystem.radiusM),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSystem.spacingM),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(DesignSystem.radiusM),
                topRight: Radius.circular(DesignSystem.radiusM),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Candidate',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Score',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Status',
                    style: DesignSystem.body(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          ...sorted.asMap().entries.map((entry) {
            final index = entry.key;
            final e = entry.value;
            final rowColor = index.isEven
                ? (isDark ? Colors.transparent : Colors.grey.shade50)
                : (isDark ? Colors.white10 : Colors.transparent);
            final isTop = index == 0;
            return Container(
              color: rowColor,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSystem.spacingM,
                vertical: DesignSystem.spacingS,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: DesignSystem.caption(context).copyWith(
                        fontSize: 12,
                        fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                        color: isTop
                            ? DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value.toStringAsFixed(4),
                      style: DesignSystem.body(context).copyWith(
                        fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: isTop
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: DesignSystem.getSemanticColor(
                                context,
                                SemanticColor.success,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(
                                DesignSystem.radiusS,
                              ),
                            ),
                            child: Text(
                              'SELECTED',
                              style: DesignSystem.body(context).copyWith(
                                color: DesignSystem.getSemanticColor(
                                  context,
                                  SemanticColor.success,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key] = entry.value;
  }
  return result;
}

Map<String, double>? _asStringKeyedDoubleMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, double>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! num) return null;
    result[entry.key] = (entry.value as num).toDouble();
  }
  return result;
}

Widget _buildMalformedErrorCard(BuildContext context, String fieldName, Object? rawValue) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.all(DesignSystem.spacingM),
    decoration: BoxDecoration(
      color: isDark ? Colors.red.shade900.withValues(alpha: 0.2) : Colors.red.shade50,
      borderRadius: BorderRadius.circular(DesignSystem.radiusL),
      border: Border.all(color: Colors.red.shade300),
    ),
    child: Text(
      rawValue == null
          ? '$fieldName data unavailable.'
          : '$fieldName data malformed or invalid type (${rawValue.runtimeType}).',
      style: DesignSystem.body(context).copyWith(
        color: isDark ? Colors.red.shade200 : Colors.red.shade700,
      ),
    ),
  );
}
