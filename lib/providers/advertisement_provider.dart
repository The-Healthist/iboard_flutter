import 'package:flutter/material.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:logger/logger.dart';

class AdvertisementProvider extends ChangeNotifier {
  final Logger _logger = Logger();
  final ApiClient _apiClient;
  final AppDataProvider _appDataProvider;

  List<AdModel> _advertisements = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<AdModel> get advertisements => _advertisements;
  List<AdModel> get topAdvertisements => _advertisements
      .where((ad) =>
          ad.display == AdDisplayType.top ||
          ad.display == AdDisplayType.topfull)
      .toList();
  List<AdModel> get fullAdvertisements => _advertisements
      .where((ad) =>
          ad.display == AdDisplayType.full ||
          ad.display == AdDisplayType.topfull)
      .toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  AdvertisementProvider(this._apiClient, this._appDataProvider) {
    _logger.i('AdvertisementProvider initialized.');
    // Optionally fetch advertisements immediately or provide a method to do so.
    // fetchAdvertisements(); // Example: Fetch on init if desired
  }

  // Interface to fetch/update advertisements
  Future<void> fetchAdvertisements() async {
    if (_appDataProvider.token == null) {
      _error = "Authentication token is missing. Cannot fetch advertisements.";
      _logger.w(_error);
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _logger.i('Fetching advertisements from building...');
      // Using getAdvertisementsBuilding as per httpapi.json for general advertisements
      final responseData = await _apiClient.getAdvertisementsBuilding();

      if (responseData.containsKey('data') && responseData['data'] is List) {
        final List<dynamic> advertisementListJson = responseData['data'];
        _advertisements = advertisementListJson
            .map((jsonItem) =>
                AdModel.fromJson(jsonItem as Map<String, dynamic>))
            .toList();
        _logger.i(
            'Successfully fetched and parsed ${_advertisements.length} advertisements.');
        _logger.i(
            'Top ads: ${topAdvertisements.length}, Full ads: ${fullAdvertisements.length}');
      } else {
        _logger.w(
            'Fetched advertisements data is not in the expected format: $responseData');
        _advertisements = []; // Clear if format is wrong
        _error = "Failed to parse advertisements data.";
      }
    } on ApiException catch (e) {
      _logger.e('Failed to fetch advertisements (ApiException)',
          error: e, stackTrace: e.errorData is StackTrace ? e.errorData : null);
      _error = 'Failed to fetch advertisements: ${e.message}';
      _advertisements = []; // Clear on error
    } catch (e, stackTrace) {
      _logger.e('An unexpected error occurred while fetching advertisements',
          error: e, stackTrace: stackTrace);
      _error = 'An unexpected error occurred: $e';
      _advertisements = []; // Clear on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Interface to get a specific advertisement by ID (if needed)
  AdModel? getAdvertisementById(int id) {
    try {
      return _advertisements.firstWhere((ad) => ad.id == id);
    } catch (e) {
      return null; // Not found
    }
  }

  // Get advertisements by display type
  List<AdModel> getAdvertisementsByDisplay(AdDisplayType display) {
    return _advertisements.where((ad) => ad.display == display).toList();
  }

  // Potentially add methods to add/update/delete advertisements if the API supports it
  // and if such functionality is required by the app.
  // For now, focusing on fetching and displaying.
}
