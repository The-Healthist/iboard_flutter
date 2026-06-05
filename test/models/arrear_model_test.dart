import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/arrear_model.dart';

void main() {
  group('ManagementFeeModel.fromJson', () {
    test('skips malformed nested items instead of throwing', () {
      final model = ManagementFeeModel.fromJson({
        'blocks': [
          null,
          'bad block',
          {
            'name': '01',
            'floors': [
              1,
              {
                'name': '02',
                'units': [
                  false,
                  {
                    'name': 'A',
                    'bills': [
                      'bad bill',
                      {'2026-06': '-128.5'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(model.blocks, hasLength(1));
      expect(model.blocks.single.name, '01');
      expect(model.blocks.single.floors, hasLength(1));
      expect(model.blocks.single.floors.single.units, hasLength(1));

      final bill = model.blocks.single.floors.single.units.single.bills.single;
      expect(bill.period, '2026-06');
      expect(bill.value, '-128.5');
      expect(bill.amount, -128.5);
      expect(bill.statusDescription, '欠費 129');
    });
  });

  group('OtherFeeModel.fromJson', () {
    test('parses other fee bill metadata and string-keyed maps', () {
      final model = OtherFeeModel.fromJson({
        'blocks': [
          {
            'name': '',
            'floors': [
              {
                'name': '01',
                'units': [
                  {
                    'name': 'B',
                    'bills': [
                      {
                        'trs_to': '2026-06-01',
                        'trs_val': 80,
                        'item_id': 7,
                        'remark': 'cleaning',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final bill = model.blocks.single.floors.single.units.single.bills.single;
      expect(bill.period, '2026-06-01');
      expect(bill.value, 80);
      expect(bill.itemId, '7');
      expect(bill.remark, 'cleaning');
      expect(bill.isOtherFee, isTrue);
    });
  });

  group('ArrearModel.fromJson', () {
    test('uses safe defaults for invalid scalar fields', () {
      final before = DateTime.now();

      final model = ArrearModel.fromJson({
        'id': 1,
        'amount': 'bad amount',
        'due_date': 'not a date',
        'created_at': 'not a date',
        'updated_at': 'not a date',
        'deleted_at': 'not a date',
        'is_deleted': '1',
      });

      final after = DateTime.now();

      expect(model.id, '1');
      expect(model.amount, 0);
      expect(model.dueDate.isBefore(before), isFalse);
      expect(model.dueDate.isAfter(after), isFalse);
      expect(model.createdAt.isBefore(before), isFalse);
      expect(model.createdAt.isAfter(after), isFalse);
      expect(model.updatedAt.isBefore(before), isFalse);
      expect(model.updatedAt.isAfter(after), isFalse);
      expect(model.deletedAt, isNull);
      expect(model.isDeleted, isTrue);
    });
  });
}
