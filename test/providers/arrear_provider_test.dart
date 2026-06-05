import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/arrear_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ArrearProvider cache and selection logic', () {
    test('loads cached data and keeps default empty-block units selectable',
        () async {
      SharedPreferences.setMockInitialValues({
        'management_fee_cache': jsonEncode({
          'blocks': [
            {
              'name': '',
              'floors': [
                {
                  'name': '01',
                  'units': [
                    {
                      'name': 'A',
                      'bills': [
                        {'2026-06': -120},
                      ],
                    },
                  ],
                },
              ],
            },
            {
              'name': '02',
              'floors': [
                {
                  'name': '03',
                  'units': [
                    {
                      'name': 'B',
                      'bills': [
                        {'2026-06': '已付'},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }),
        'other_fee_cache': jsonEncode({
          'blocks': [
            {
              'name': '',
              'floors': [
                {
                  'name': '01',
                  'units': [
                    {
                      'name': 'A',
                      'bills': [
                        {
                          'trs_to': '2026-05',
                          'trs_val': 50,
                          'item_id': 'shared',
                          'remark': 'lift',
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }),
      });

      final appDataProvider = AppDataProvider(baseUrl: 'http://example.test');
      final provider = ArrearProvider(
        apiClient: ApiClient(baseUrl: 'http://example.test'),
        appDataProvider: appDataProvider,
      );

      await provider.loadFromCache();

      expect(provider.blocks, ['02']);
      expect(provider.selectedBlock, '02');
      expect(provider.buildings, containsAll(['01', '03']));
      expect(provider.getFloors('01'), ['A']);

      provider.setSelectedFloor('01');
      expect(provider.selectedUnit, 'A');
      expect(provider.currentUnitDisplayName, '02座01樓A室');

      expect(provider.currentArrearage, {'2026-06': -120});
      expect(provider.hasOtherFees('01', 'A'), isTrue);
      expect(provider.hasOtherFeesForFloor('01'), isTrue);
      expect(provider.isOtherFeeDataEmpty, isFalse);

      provider.setFeeType(FeeType.other);

      final detailedFees = provider.currentDetailedArrearage;
      expect(detailedFees, hasLength(1));
      expect(detailedFees!.single.period, '2026-05');
      expect(detailedFees.single.itemId, 'shared');
      expect(provider.currentArrearage, {'2026-05': 50});

      provider.dispose();
      appDataProvider.dispose();
    });
  });
}
