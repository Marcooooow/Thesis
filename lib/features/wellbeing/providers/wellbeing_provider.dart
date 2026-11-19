import 'package:flutter/foundation.dart';
import '../models/wellbeing_models.dart';
import '../services/wellbeing_service.dart';

class WellbeingProvider extends ChangeNotifier {
  final WellbeingService _service = WellbeingService();

  WeeklyOverviewResponse? _overview;
  EmployeeDetailResponse? _selectedEmployeeDetail;
  bool _isLoading = false;
  bool _isLoadingDetail = false;
  String? _error;
  DateTime? _selectedWeekStart;
  String? _selectedTeamId;

  WeeklyOverviewResponse? get overview => _overview;
  EmployeeDetailResponse? get selectedEmployeeDetail => _selectedEmployeeDetail;
  bool get isLoading => _isLoading;
  bool get isLoadingDetail => _isLoadingDetail;
  String? get error => _error;
  DateTime get selectedWeekStart => _selectedWeekStart ?? (_overview?.weekStart ?? _getMonday(DateTime.now()));
  String? get selectedTeamId => _selectedTeamId;

  static DateTime _getMonday(DateTime date) {
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));
  }

  void setSelectedWeek(DateTime weekStart) {
    _selectedWeekStart = _getMonday(weekStart);
    fetchWeeklyOverview();
  }

  void setSelectedTeam(String? teamId) {
    _selectedTeamId = teamId;
    fetchWeeklyOverview();
  }

  Future<void> fetchWeeklyOverview() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _overview = await _service.getWeeklyOverview(
        weekStart: _selectedWeekStart,
        teamId: _selectedTeamId,
      );
      if (_overview != null && _selectedWeekStart == null) {
        _selectedWeekStart = _overview!.weekStart;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchEmployeeDetail(String employeeId) async {
    _isLoadingDetail = true;
    _error = null;
    notifyListeners();

    try {
      _selectedEmployeeDetail = await _service.getEmployeeDetail(
        employeeId,
        weekStart: _selectedWeekStart,
      );
      _isLoadingDetail = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoadingDetail = false;
      notifyListeners();
    }
  }

  void clearSelectedEmployee() {
    _selectedEmployeeDetail = null;
    notifyListeners();
  }
}
