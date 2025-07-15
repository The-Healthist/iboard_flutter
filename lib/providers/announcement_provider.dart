import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart'; // Assuming AppDataProvider is here
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

class AnnouncementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider
      _appDataProvider; // To access token and deviceId if needed

  List<AnnouncementModel> _announcements = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<AnnouncementModel> get announcements => _announcements;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AnnouncementProvider(this._apiClient, this._appDataProvider) {
    _logger.i('AnnouncementProvider initialized.');
    // Optionally fetch announcements immediately or provide a method to do so.
    // fetchNotices(); // Example: Fetch on init if desired
  }

  // Interface to fetch/update announcements
  Future<void> fetchNotices() async {
    if (_appDataProvider.token == null) {
      _error = "Authentication token is missing. Cannot fetch notices.";
      _logger.w(_error);
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logger.i('Fetching notices from building...');
      // Using getNoticesBuilding as per httpapi.json for general notices
      final responseData = await _apiClient.getNoticesBuilding();

      if (responseData.containsKey('data') && responseData['data'] is List) {
        final List<dynamic> noticeListJson = responseData['data'];
        _announcements = noticeListJson
            .map((jsonItem) =>
                AnnouncementModel.fromJson(jsonItem as Map<String, dynamic>))
            .toList();
        _logger.i(
            'Successfully fetched and parsed ${_announcements.length} notices.');
      } else {
        _logger.w(
            'Fetched notices data is not in the expected format: $responseData');
        _announcements = []; // Clear if format is wrong
        _error = "Failed to parse notices data.";
      }
    } on ApiException catch (e) {
      _logger.e('Failed to fetch notices (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);
      _error = 'Failed to fetch notices: ${e.message}';
      _announcements = []; // Clear on error
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred while fetching notices',
          error: e, stackTrace: stackTrace);
      _error = 'An unexpected error occurred: $e';
      _announcements = []; // Clear on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Interface to get a specific announcement by ID (if needed)
  AnnouncementModel? getNoticeById(int id) {
    try {
      return _announcements.firstWhere((notice) => notice.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  // Potentially add methods to add/update/delete announcements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
