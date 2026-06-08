abstract class PaymentDataSource {
  Future<List<Map<String, dynamic>>> getBuildingList();
  Future<List<Map<String, dynamic>>> getBuildingFlatUnits({
    required String blgId,
  });
  Future<Map<String, dynamic>> getBuildingTransactionTypes({
    required String blgId,
  });
  Future<List<Map<String, dynamic>>> getBuildingFlatUnitBills({
    required String unitId,
  });
}
