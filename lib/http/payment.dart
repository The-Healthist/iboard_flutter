import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// iSmartPOS 支付系統客戶端
/// 基於 AWS API Gateway 的支付和物業管理系統接口集成
class PaymentClient {
  static const String _defaultBaseUrl =
      'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1';
  final String _baseUrl;
  final Logger _logger = Logger();

  static const Duration _requestTimeout = Duration(seconds: 30);

  PaymentClient({String? baseUrl})
      : _baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  /**[
  {
    "building_id": "9077004",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(4座)",
    "oc_id": "90770040000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077005",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(5座)",
    "oc_id": "90770050000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077006",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(6座)",
    "oc_id": "90770060000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077007",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(7座)",
    "oc_id": "90770070000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077008",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(8座)",
    "oc_id": "90770080000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077009",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(9座)",
    "oc_id": "90770090000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077010",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(10座)",
    "oc_id": "90770100000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  },
  {
    "building_id": "9077011",
    "area": "新界",
    "partition": "洪水橋",
    "street": "丹桂村路",
    "streetno": "80",
    "court": "玉桂園",
    "buildname": "Osmanthus Garden",
    "buildname_chi": "玉桂園(11座)",
    "oc_id": "90770110000",
    "state_remark": "司於 2025 年5月1日正式獲委任為本大廈物業經理人，按法團提供的資料，本月結單「應繳總額」已反映2025年4月或以前的管理費結欠，如有不符帳項，敬希與管理處聯絡作進一步核對，多謝合作。一切結欠款項，法團保留追討權利。",
    "remark": "",
    "block": "",
    "building_type": "res",
    "mf_mask": "",
    "prescriptive_bill": 1,
    "is_active": 1,
    "estate_id": "bdest_6i1PcqCmag4Ei0KJCRoDaOLgy9ejc8hP"
  }
] */
  /// 1, 獲取全部「大廈」
  /// Endpoint: GET /v1/get-building-list
  Future<List<Map<String, dynamic>>> getBuildingList() async {
    final Uri url = _buildUri('/get-building-list');

    _logger.i(' 獲取全部大廈列表');

    try {
      final response = await http.get(url).timeout(_requestTimeout);
      return _handleArrayResponse(response, '獲取大廈列表');
    } catch (e) {
      _logger.e(' 獲取大廈列表失敗: $e');
      rethrow;
    }
  }

  /** 2.eg{
  "buildname": "DEMO1 BUILDING",
  "buildname_chi": "測試1大廈",
  "cli_name": "The Incorporated Owners of DEMO1 BUILDING",
  "cli_chi_name": "測試1大廈業主立案法團",
  "cli_addr": "九龍 青山道489-491號 香港工業中心 C座 3/F C20室",
  "cli_chiadd": "九龍 青山道489-491號 香港工業中心 C座 3/F C20室",
  "prescriptive_bill": true
} */
  /// 2, 獲取指定「大廈」「細明」
  /// Endpoint: POST /v1/building-infos
  /// Body: {"blg_id": "string"}
  Future<Map<String, dynamic>> getBuildingInfos({required String blgId}) async {
    final Uri url = _buildUri('/building-infos');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    _logger.i(' 獲取大廈細明，大廈ID: $blgId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取大廈細明');
    } catch (e) {
      _logger.e(' 獲取大廈細明失敗: $e');
      rethrow;
    }
  }

  /* 3.eg[
  {
    "id": 18,
    "pay_type": "POS_CARD",
    "pay_type_name_chi": "信用卡",
    "markup": 0.027,
    "building_id": "0999900",
    "receiver_id": "LIPM"
  },
  {
    "id": 19,
    "pay_type": "POS_ALIWE",
    "pay_type_name_chi": "微信/支付寶",
    "markup": 0.025,
    "building_id": "0999900",
    "receiver_id": "LIPM"
  },
  {
    "id": 20,
    "pay_type": "POS_BANK",
    "pay_type_name_chi": "銀行轉帳",
    "markup": 0,
    "building_id": "0999900",
    "receiver_id": "LIPM"
  },
  {
    "id": 21,
    "pay_type": "POS_CHEQUE",
    "pay_type_name_chi": "支票",
    "markup": 0,
    "building_id": "0999900",
    "receiver_id": "LIPM"
  },
  {
    "id": 22,
    "pay_type": "POS_CASH",
    "pay_type_name_chi": "現金",
    "markup": 0,
    "building_id": "0999900",
    "receiver_id": "LIPM"
  }
] */
  /// 3, 請求指定「大廈」「手續費」
  /// Endpoint: POST /v1/pos/building-tran-types
  /// Body: {"blg_id": "string"}
  Future<Map<String, dynamic>> getBuildingTransactionTypes(
      {required String blgId}) async {
    final Uri url = _buildUri('/pos/building-tran-types');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取大廈手續費');
    } catch (e) {
      _logger.e(' 獲取大廈手續費失敗: $e');
      rethrow;
    }
  }

  /* 4.eg[
  {
    "unit_id": "09999000011",
    "block": "",
    "floor": "G",
    "unit": "A",
    "simpleadd": "測試1大廈 G/F A"
  },
  {
    "unit_id": "09999000012",
    "block": "",
    "floor": "G",
    "unit": "B",
    "simpleadd": "測試1大廈 G/F B"
  },
  {
    "unit_id": "09999000013",
    "block": "",
    "floor": "G",
    "unit": "C",
    "simpleadd": "測試1大廈 G/F C"
  },
  {
    "unit_id": "09999000111",
    "block": "",
    "floor": "01",
    "unit": "A",
    "simpleadd": "測試1大廈 1/F A"
  },
  {
    "unit_id": "09999000112",
    "block": "",
    "floor": "01",
    "unit": "B",
    "simpleadd": "測試1大廈 1/F B"
  },
  {
    "unit_id": "09999000113",
    "block": "",
    "floor": "01",
    "unit": "C",
    "simpleadd": "測試1大廈 1/F C"
  },
  {
    "unit_id": "09999000211",
    "block": "",
    "floor": "02",
    "unit": "A",
    "simpleadd": "測試1大廈 2/F A"
  },
  {
    "unit_id": "09999000212",
    "block": "",
    "floor": "02",
    "unit": "B",
    "simpleadd": "測試1大廈 2/F B"
  },
  {
    "unit_id": "09999000213",
    "block": "",
    "floor": "02",
    "unit": "C",
    "simpleadd": "測試1大廈 2/F C"
  },
  {
    "unit_id": "09999000311",
    "block": "",
    "floor": "03",
    "unit": "A",
    "simpleadd": "測試1大廈 3/F A"
  },
  {
    "unit_id": "09999000312",
    "block": "",
    "floor": "03",
    "unit": "B",
    "simpleadd": "測試1大廈 3/F B"
  },
  {
    "unit_id": "09999000411",
    "block": "",
    "floor": "04",
    "unit": "A",
    "simpleadd": "測試1大廈 4/F A"
  },
  {
    "unit_id": "09999000412",
    "block": "",
    "floor": "04",
    "unit": "B",
    "simpleadd": "測試1大廈 4/F B"
  },
  {
    "unit_id": "09999000413",
    "block": "",
    "floor": "04",
    "unit": "C",
    "simpleadd": "測試1大廈 4/F C"
  },
  {
    "unit_id": "09999000414",
    "block": "",
    "floor": "04",
    "unit": "D",
    "simpleadd": "測試1大廈 4/F D"
  },
  {
    "unit_id": "09999000415",
    "block": "",
    "floor": "04",
    "unit": "E",
    "simpleadd": "測試1大廈 4/F E"
  },
  {
    "unit_id": "09999000416",
    "block": "",
    "floor": "04",
    "unit": "F",
    "simpleadd": "測試1大廈 4/F F"
  },
  {
    "unit_id": "09999000417",
    "block": "",
    "floor": "04",
    "unit": "G",
    "simpleadd": "測試1大廈 4/F G"
  },
  {
    "unit_id": "09999000418",
    "block": "",
    "floor": "04",
    "unit": "H",
    "simpleadd": "測試1大廈 4/F H"
  },
  {
    "unit_id": "09999000419",
    "block": "",
    "floor": "04",
    "unit": "I",
    "simpleadd": "測試1大廈 4/F I"
  },
  {
    "unit_id": "09999000420",
    "block": "",
    "floor": "04",
    "unit": "J",
    "simpleadd": "測試1大廈 4/F J"
  },
  {
    "unit_id": "09999000421",
    "block": "",
    "floor": "04",
    "unit": "K",
    "simpleadd": "測試1大廈 4/F K"
  },
  {
    "unit_id": "09999000422",
    "block": "",
    "floor": "04",
    "unit": "L",
    "simpleadd": "測試1大廈 4/F L"
  },
  {
    "unit_id": "09999000423",
    "block": "",
    "floor": "04",
    "unit": "M",
    "simpleadd": "測試1大廈 4/F M"
  },
  {
    "unit_id": "09999000424",
    "block": "",
    "floor": "04",
    "unit": "N",
    "simpleadd": "測試1大廈 4/F N"
  },
  {
    "unit_id": "09999000425",
    "block": "",
    "floor": "04",
    "unit": "O",
    "simpleadd": "測試1大廈 4/F O"
  },
  {
    "unit_id": "09999000426",
    "block": "",
    "floor": "04",
    "unit": "P",
    "simpleadd": "測試1大廈 4/F P"
  },
  {
    "unit_id": "09999000427",
    "block": "",
    "floor": "04",
    "unit": "Q",
    "simpleadd": "測試1大廈 4/F Q"
  },
  {
    "unit_id": "09999000428",
    "block": "",
    "floor": "04",
    "unit": "R",
    "simpleadd": "測試1大廈 4/F R"
  },
  {
    "unit_id": "09999000429",
    "block": "",
    "floor": "04",
    "unit": "S",
    "simpleadd": "測試1大廈 4/F S"
  },
  {
    "unit_id": "09999000430",
    "block": "",
    "floor": "04",
    "unit": "T",
    "simpleadd": "測試1大廈 4/F T"
  },
  {
    "unit_id": "09999000431",
    "block": "",
    "floor": "04",
    "unit": "U",
    "simpleadd": "測試1大廈 4/F U"
  },
  {
    "unit_id": "09999000432",
    "block": "",
    "floor": "04",
    "unit": "V",
    "simpleadd": "測試1大廈 4/F V"
  },
  {
    "unit_id": "09999000433",
    "block": "",
    "floor": "04",
    "unit": "W",
    "simpleadd": "測試1大廈 4/F W"
  },
  {
    "unit_id": "09999000434",
    "block": "",
    "floor": "04",
    "unit": "X",
    "simpleadd": "測試1大廈 4/F X"
  },
  {
    "unit_id": "09999000435",
    "block": "",
    "floor": "04",
    "unit": "Y",
    "simpleadd": "測試1大廈 4/F Y"
  }
] */
  /// 4, 獲取指定「大廈」全部「單位」
  /// Endpoint: POST /v1/building-flat-units
  /// Body: {"blg_id": "string"}
  Future<List<Map<String, dynamic>>> getBuildingFlatUnits(
      {required String blgId}) async {
    final Uri url = _buildUri('/building-flat-units');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    _logger.i(' 獲取大廈全部單位，大廈ID: $blgId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleArrayResponse(response, '獲取大廈單位');
    } catch (e) {
      _logger.e(' 獲取大廈單位失敗: $e');
      rethrow;
    }
  }

  /** 5.eg[
   * {
  "payment_objs": [
    {
      "payment_id": "acpb_aM8GHmRuJmRptc3oByphavt2d37y3q5O",
      "input_time": "2024-07-17 11:39:47",
      "tran_time": "2024-07-17 11:39:47",
      "trs_val": 5,
      "receipt_id": "20109092",
      "ref_no": "",
      "pay_type": "POS_BANK",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_yFJcghiUM6SZpKghsvUL7WsIIXjHqUk5",
      "input_time": "2024-07-17 10:59:38",
      "tran_time": "2024-07-17 10:59:38",
      "trs_val": 0.17,
      "receipt_id": "20109089",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_MAJhEjlMwZzEzGvivJZQy98IQ9tYLP3B",
      "input_time": "2024-07-17 11:30:19",
      "tran_time": "2024-07-17 11:30:19",
      "trs_val": 0.17,
      "receipt_id": "20109091",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_lHz0OcJgkwoBSDdNDAGU9o6wQQXFATP8",
      "input_time": "2024-07-16 14:18:23",
      "tran_time": "2024-07-16 14:18:23",
      "trs_val": 6.73,
      "receipt_id": "20109082",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 6.56,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_awZqE9ru4VjkRLlJ1eu0wXS6ynltvMxu",
      "input_time": "2024-07-16 13:44:01",
      "tran_time": "2024-07-16 13:44:01",
      "trs_val": 37.34,
      "receipt_id": "20109081",
      "ref_no": "",
      "pay_type": "POS_BANK",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 6,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 6,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2023/02",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/01",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/02",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_qH339u93FhWqPJah7X2oahucy2PnoNud",
      "input_time": "2024-07-16 14:25:45",
      "tran_time": "2024-07-16 14:25:45",
      "trs_val": 0.34,
      "receipt_id": "20109084",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 0.17,
          "remark": ""
        },
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2023/02",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_UPzkDDpkxiKK6rl1PvAjiAuothMImGkS",
      "input_time": "2024-07-16 14:26:50",
      "tran_time": "2024-07-16 14:26:50",
      "trs_val": 0.17,
      "receipt_id": "20109085",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_rm7cjbtgNKglB9bZFBflLN5m8d47oVjR",
      "input_time": "2024-07-16 14:23:33",
      "tran_time": "2024-07-16 14:23:33",
      "trs_val": 5,
      "receipt_id": "20109083",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_dWGLCUT8C8BtYtR7ouPYTHTKnaL97ps9",
      "input_time": "2024-07-17 16:26:44",
      "tran_time": "2024-07-17 16:26:44",
      "trs_val": 4.17,
      "receipt_id": "20109094",
      "ref_no": "",
      "pay_type": "POS_BANK",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2023/02",
          "trs_val": 0.17,
          "remark": ""
        },
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "prepaid",
          "trs_val": 1.9,
          "remark": ""
        },
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "prepaid",
          "trs_val": 2.1,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_IcLyLAn7DA1quRqa5AeJwqWQ7nLfZfB4",
      "input_time": "2024-07-16 14:29:23",
      "tran_time": "2024-07-16 14:29:23",
      "trs_val": 10,
      "receipt_id": "20109087",
      "ref_no": "",
      "pay_type": "POS_BANK",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2023/02",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/01",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_8EAhaP8k8k6ueOglzYqFRSITdF7gW56y",
      "input_time": "2024-07-16 14:28:17",
      "tran_time": "2024-07-16 14:28:17",
      "trs_val": 5,
      "receipt_id": "20109086",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/02",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_FtwBIJa8N52sZcJ9dqc7nyjHYpHBEV0v",
      "input_time": "2024-07-30 22:33:47",
      "tran_time": "2024-07-30 22:33:37",
      "trs_val": 0.17,
      "receipt_id": "20109598",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_ICJ1opWkA9xbgqBrJbabPGHW4y9MJuHm",
      "input_time": "2024-07-17 11:01:39",
      "tran_time": "2024-07-17 11:01:39",
      "trs_val": 0.17,
      "receipt_id": "20109090",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_pz75UmgD9VrErw2XaxXfA6TNMgu1pQEH",
      "input_time": "2024-07-22 20:56:17",
      "tran_time": "2024-07-22 20:56:10",
      "trs_val": 6.73,
      "receipt_id": "20109108",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/03",
          "trs_val": 0.17,
          "remark": ""
        },
        {
          "floor": "03",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 6.56,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_2rR3XMtX3NkSu8pTHNggnbusOkL3vCLr",
      "input_time": "2024-07-22 18:54:59",
      "tran_time": "2024-07-22 18:54:59",
      "trs_val": 15,
      "receipt_id": "20109107",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "01",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_PeOcc5cNw9skLD6eDSV4wMlZqs7fqEcC",
      "input_time": "2024-07-17 19:35:15",
      "tran_time": "2024-07-17 19:35:15",
      "trs_val": 5,
      "receipt_id": "20109095",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_VPdiOjjDIpFbCSg0FbZDDqrvXw8oK9jK",
      "input_time": "2024-07-17 16:12:57",
      "tran_time": "2024-07-17 16:12:57",
      "trs_val": 5,
      "receipt_id": "20109093",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_IqrfohmXeg13LqFvf0nvDXJFKSFOcqE5",
      "input_time": "2024-07-29 13:38:43",
      "tran_time": "2024-07-29 13:38:39",
      "trs_val": 5,
      "receipt_id": "20109481",
      "ref_no": "",
      "pay_type": "POS_CHEQUE",
      "status": "pending_validation",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_hs5gMKs3bBbGfVRuOauGCwXB01D0fnQP",
      "input_time": "2024-07-19 20:05:27",
      "tran_time": "2024-07-19 20:05:27",
      "trs_val": 15,
      "receipt_id": "20109105",
      "ref_no": "",
      "pay_type": "POS_CASH",
      "status": "in_cashier",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "prepaid",
          "trs_val": 5,
          "remark": ""
        }
      ]
    }
  ]
} */
  /// 5, 查詢指定「大廈」符合條件「歷史訂單」
  /// Endpoint: POST /v1/pos/get_transactions_by_date
  /// Body: {"blg_id": "string", "from_date": "string", "to_date": "string", "date_type": "string", "pay_method": "string"}
  Future<List<Map<String, dynamic>>> getTransactionsByDate({
    required String blgId,
    required String fromDate,
    required String toDate,
    required String dateType,
    required String payMethod,
  }) async {
    final Uri url = _buildUri('/pos/get_transactions_by_date');
    final Map<String, dynamic> requestBody = {
      'blg_id': blgId,
      'from_date': fromDate,
      'to_date': toDate,
      'date_type': dateType,
      'pay_method': payMethod,
    };

    _logger.i(' 查詢歷史訂單，大廈ID: $blgId, 日期範圍: $fromDate - $toDate');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleArrayResponse(response, '查詢歷史訂單');
    } catch (e) {
      _logger.e(' 查詢歷史訂單失敗: $e');
      rethrow;
    }
  }

  /* 6.eg[
  {
    "invoice_no": "0228100003202",
    "flat_code": "02281001914",
    "item_id": "管理費",
    "trs_to": "2025/09",
    "bill_dt": "2025-09-01",
    "net_amount": 1930,
    "remark": ""
  }
] */ // 这里的unit_id是上面的  /// 4, 獲取指定「大廈」全部「單位」 得到的unit_id,需要对应上
  /// 6, 獲取指定「單位」「待繳費帳單」
  /// Endpoint: POST /v1/building-flat-unit-bills
  /// Body: {"unit_id": "string"}
  Future<List<Map<String, dynamic>>> getBuildingFlatUnitBills(
      {required String unitId}) async {
    final Uri url = _buildUri('/building-flat-unit-bills');
    final Map<String, dynamic> requestBody = {'unit_id': unitId};

    _logger.i(' 獲取單位待繳費帳單，單位ID: $unitId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleArrayResponse(response, '獲取待繳費帳單');
    } catch (e) {
      _logger.e(' 獲取待繳費帳單失敗: $e');
      rethrow;
    }
  }

  /// 7, 上報「繳費請求」
  /// Endpoint: POST /v1/pos/report-payment
  /// Headers: device_id, pw
  /// Body: 完整的繳費信息
  /// eg{
  /* {
 "AMOUNT": "000000000010",
 "AUTH_NO": "027933",
 "BATCH_NO": "000103",
 "BUSINESS_ID": "100100001",
 "CARDNO": "5408062004333891",
 "CARD_ORGN": "02",
 "CURRENCY": "HKD",
 "DATE": "20230227",
 "MERCH_ID": "852999965130110",
 "MERCH_NAME": "領居物業科技管理 時安大廈",
 "REF_NO": "022752419257",
 "REJCODE": "00",
 "REJCODE_CN": "交易成功",
 "TER_ID": "00044116",
 "TIME": "195119",
 "TRACE_NO": "000126",
 "TRANS_CHANNEL": "",
 "TRANS_TICKET_NO": "2023022752419257",
 "TRANS_TRACE_NO": "test000019",
 "BILL_OBJ":[
  {
   "flat_code": "03141000511",
   "item_id": "管理費",
   "trs_to": "2023/02",
   "bill_dt": "2023-02-01",
   "net_amount": 1006.0,
   "invoice_no": "0314100003667"
  },
  {
   "flat_code": "03141000511",
   "item_id": "管理費",
   "trs_to": "2023/03",
   "bill_dt": "2023-03-01",
   "net_amount": 1006.0,
   "invoice_no": "0314100004008"
  }
 ]
} */
  Future<Map<String, dynamic>> reportPayment({
    required String deviceId,
    required String password,
    required Map<String, dynamic> paymentData,
  }) async {
    final Uri url = _buildUri('/pos/report-payment');

    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'device_id': deviceId,
      'pw': password,
    };

    _logger.i(' 上報繳費請求，設備ID: $deviceId');

    try {
      final response = await http
          .post(
            url,
            headers: headers,
            body: json.encode(paymentData),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '上報繳費請求');
    } catch (e) {
      _logger.e(' 上報繳費請求失敗: $e');
      rethrow;
    }
  }

  /*{
  "payment_objs_cheque": [
    {
      "payment_id": "acpb_PVNkMSwGl4QIpZxAnDJJIg2o6Nyy15Iq",
      "input_time": "2025-08-28 18:11:44",
      "trs_val": 5,
      "receipt_id": "20124564",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_EAtSAunwXZSy3TeVAhHKtKiAB55FqPHB",
      "input_time": "2025-05-18 18:37:22",
      "trs_val": 0.17,
      "receipt_id": "20119802",
      "ref_no": "53246",
      "payment_detail_objs": [
        {
          "floor": "03",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    }
  ],
  "payment_objs_cash": [
    {
      "payment_id": "acpb_tZS5YGUnLfE6x32aSVuTia3F9Wltc9MQ",
      "input_time": "2025-08-26 23:52:05",
      "trs_val": 10,
      "receipt_id": "20124483",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "B",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "G",
          "unit": "B",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_iedUL6kCilwvW6odV1ZoGffzRH4NjYfv",
      "input_time": "2025-08-26 23:42:08",
      "trs_val": 10,
      "receipt_id": "20124482",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "C",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "G",
          "unit": "C",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_cLX3pme0QzKkpg0nalD0FHToKeS4ZKcp",
      "input_time": "2025-08-24 22:56:55",
      "trs_val": 0.17,
      "receipt_id": "20124327",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2022/12",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_C9urkRi4pQskyGnwW08K1iMRHjQH1FUk",
      "input_time": "2025-08-24 23:32:39",
      "trs_val": 0.17,
      "receipt_id": "20124328",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2023/01",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_mmQSNUokxA4Nh4oo9gB7DLuDrG1xTtYQ",
      "input_time": "2025-08-26 22:52:35",
      "trs_val": 0.17,
      "receipt_id": "20124477",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2023/02",
          "trs_val": 0.17,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_zXeySDOhHFNV0tNu9HbEh1OivnV209yQ",
      "input_time": "2025-08-28 18:23:30",
      "trs_val": 5,
      "receipt_id": "20124566",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_yruZVQ99jgfB7x7dQl7heUTR0zapkOZi",
      "input_time": "2025-08-05 15:51:09",
      "trs_val": 5,
      "receipt_id": "20123426",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_cnY5OjaCBcVIFWF5SzXKvEbLVjKklqLe",
      "input_time": "2025-08-26 23:18:13",
      "trs_val": 5,
      "receipt_id": "20124479",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_DnaSPJpWVOSkgSC3bLfFZf9fx7x0oSMJ",
      "input_time": "2025-07-10 07:30:23",
      "trs_val": 5,
      "receipt_id": "20122179",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/04",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_DD4QbShRqDormVSlqA7qX2Mbj5m6nFur",
      "input_time": "2025-08-28 17:53:14",
      "trs_val": 5,
      "receipt_id": "20124563",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_KVT7vWX2IL5Tn6D0hV4uUsbmst64Rj6b",
      "input_time": "2025-08-26 23:39:12",
      "trs_val": 5,
      "receipt_id": "20124480",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_hs5gMKs3bBbGfVRuOauGCwXB01D0fnQP",
      "input_time": "2024-07-19 20:05:27",
      "trs_val": 15,
      "receipt_id": "20109105",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        },
        {
          "floor": "02",
          "unit": "B",
          "item_id": "管理費",
          "term": "prepaid",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_q0dJKA9NLQl0wiJZbViOJ3esQqgtQstS",
      "input_time": "2025-07-13 17:25:02",
      "trs_val": 5,
      "receipt_id": "20122253",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_tuUi7BuY5Q0rEiU6qZnmZlBYYKbfYFBp",
      "input_time": "2025-08-28 18:24:41",
      "trs_val": 5,
      "receipt_id": "20124567",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_vSmgUq2UH1yFvdkN1MbYgRtQ21ffNEIz",
      "input_time": "2025-08-05 15:51:36",
      "trs_val": 5,
      "receipt_id": "20123427",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "B",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_pJNCeOpA5VOR30mczADeBqc7hj1XhoCy",
      "input_time": "2025-08-26 23:11:15",
      "trs_val": 5,
      "receipt_id": "20124478",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "01",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_sWwa7m1S8SlFMh3ATPglAPSC7RAb4PzA",
      "input_time": "2025-07-10 06:15:15",
      "trs_val": 5,
      "receipt_id": "20122167",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_MseSNkAdkmNkpjJcoJ9fpHnuQwpiTAGR",
      "input_time": "2025-08-06 22:36:34",
      "trs_val": 5,
      "receipt_id": "20123428",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "02",
          "unit": "C",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_G7y4DivpcJBJ5CusI97Qmogfg7iliiQs",
      "input_time": "2025-07-10 06:16:42",
      "trs_val": 6.56,
      "receipt_id": "20122169",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "03",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/05",
          "trs_val": 6.56,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_pZsZBy7R444HjgX7zKegV53ui8GfVw0f",
      "input_time": "2025-07-08 15:46:18",
      "trs_val": 6.56,
      "receipt_id": "20122099",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "03",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/06",
          "trs_val": 6.56,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_Oi2TwCy78MfaesLp77ySf5zX3KO4FIbk",
      "input_time": "2025-08-07 15:39:03",
      "trs_val": 1,
      "receipt_id": "20123429",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "04",
          "unit": "A",
          "item_id": "管理費",
          "term": "2024/09",
          "trs_val": 1,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_jG2NmNenxmQz03J67Uys68yiPdlWgobm",
      "input_time": "2025-08-26 23:40:37",
      "trs_val": 5,
      "receipt_id": "20124481",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "04",
          "unit": "H",
          "item_id": "管理費",
          "term": "2024/09",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_ePFM8T2vYyTMt5UzHWXG4nlJup1zCy3R",
      "input_time": "2025-08-12 13:38:30",
      "trs_val": 5,
      "receipt_id": "20123691",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "04",
          "unit": "I",
          "item_id": "管理費",
          "term": "2024/09",
          "trs_val": 5,
          "remark": ""
        }
      ]
    },
    {
      "payment_id": "acpb_fG0UK8lgculbqLENKAc6o1UdHkRZJNh8",
      "input_time": "2025-08-28 18:13:17",
      "trs_val": 1000,
      "receipt_id": "20124565",
      "ref_no": "",
      "payment_detail_objs": [
        {
          "floor": "G",
          "unit": "A",
          "item_id": "管理費",
          "term": "prepaid",
          "trs_val": 1000,
          "remark": ""
        }
      ]
    }
  ]
}*/
  /// 8, 獲取指定「大廈」全部「待清機訂單」
  /// Endpoint: POST /v1/pos/get_transactions_in_cashier
  /// Body: {"blg_id": "string"}
  Future<List<Map<String, dynamic>>> getTransactionsInCashier(
      {required String blgId}) async {
    final Uri url = _buildUri('/pos/get_transactions_in_cashier');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    _logger.i(' 獲取待清機訂單，大廈ID: $blgId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleArrayResponse(response, '獲取待清機訂單');
    } catch (e) {
      _logger.e(' 獲取待清機訂單失敗: $e');
      rethrow;
    }
  }

  /// 9, 進行「待清機訂單」清機
  /// Endpoint: POST /v1/pos/update_transactions_status_in_cashier
  /// Body: {"payment_id_list": []}
  Future<Map<String, dynamic>> updateTransactionsStatusInCashier({
    required List<String> paymentIdList,
  }) async {
    final Uri url = _buildUri('/pos/update_transactions_status_in_cashier');
    final Map<String, dynamic> requestBody = {'payment_id_list': paymentIdList};

    _logger.i(' 執行清機操作，訂單數量: ${paymentIdList.length}');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '執行清機操作');
    } catch (e) {
      _logger.e(' 執行清機操作失敗: $e');
      rethrow;
    }
  }

  /*10.eg{[
  {
    "record_id": 31,
    "building_id": "0999900",
    "bankin_time": "2024-07-16 14:28:56",
    "pay_type": "POS_CHEQUE",
    "trs_val": 6.73
  },
  {
    "record_id": 32,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 11:03:33",
    "pay_type": "POS_CASH",
    "trs_val": 10
  },
  {
    "record_id": 33,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 11:04:03",
    "pay_type": "POS_CASH",
    "trs_val": 0.51
  },
  {
    "record_id": 34,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 11:32:38",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5.17
  },
  {
    "record_id": 35,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 11:32:49",
    "pay_type": "POS_CASH",
    "trs_val": 5.46
  },
  {
    "record_id": 36,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 16:28:42",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 37,
    "building_id": "0999900",
    "bankin_time": "2024-07-17 19:35:28",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 38,
    "building_id": "0999900",
    "bankin_time": "2024-07-22 20:56:53",
    "pay_type": "POS_CHEQUE",
    "trs_val": 6.73
  },
  {
    "record_id": 40,
    "building_id": "0999900",
    "bankin_time": "2024-07-26 06:28:10",
    "pay_type": "POS_CHEQUE",
    "trs_val": 15
  },
  {
    "record_id": 56,
    "building_id": "0999900",
    "bankin_time": "2024-07-30 22:32:56",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 101,
    "building_id": "0999900",
    "bankin_time": "2024-09-02 21:38:50",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 102,
    "building_id": "0999900",
    "bankin_time": "2024-09-02 21:51:17",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 103,
    "building_id": "0999900",
    "bankin_time": "2024-09-02 21:51:59",
    "pay_type": "POS_CHEQUE",
    "trs_val": 0.17
  },
  {
    "record_id": 295,
    "building_id": "0999900",
    "bankin_time": "2024-10-29 19:11:51",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 296,
    "building_id": "0999900",
    "bankin_time": "2024-10-29 19:14:20",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 297,
    "building_id": "0999900",
    "bankin_time": "2024-10-29 19:14:57",
    "pay_type": "POS_CHEQUE",
    "trs_val": 5
  },
  {
    "record_id": 2044,
    "building_id": "0999900",
    "bankin_time": "2025-07-26 13:59:33",
    "pay_type": "POS_CHEQUE",
    "trs_val": 32
  }
] */
  /// 10, 獲取指定「大廈」全部「歷史清機」
  /// Endpoint: POST /v1/pos/get_bank_in_record_list
  /// Body: {"blg_id": "string"}
  Future<List<Map<String, dynamic>>> getBankInRecordList(
      {required String blgId}) async {
    final Uri url = _buildUri('/pos/get_bank_in_record_list');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    _logger.i(' 獲取歷史清機記錄，大廈ID: $blgId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleArrayResponse(response, '獲取歷史清機記錄');
    } catch (e) {
      _logger.e(' 獲取歷史清機記錄失敗: $e');
      rethrow;
    }
  }

  /* 11.eg{[
  {
    "id": "acpb_lHz0OcJgkwoBSDdNDAGU9o6wQQXFATP8",
    "payment_id": "acpb_lHz0OcJgkwoBSDdNDAGU9o6wQQXFATP8",
    "input_time": "2024-07-16 14:18:23",
    "txamount": 6.73,
    "receipt_id": "20109082",
    "ref_no": "",
    "floor": "02",
    "unit": "A",
    "invoice_no": "0999900000007",
    "trs_val": 6.56,
    "item_id": "管理費",
    "term": "2022/12",
    "remark": "",
    "pay_type": "POS_CHEQUE"
  },
  {
    "id": "acpb_lHz0OcJgkwoBSDdNDAGU9o6wQQXFATP8",
    "payment_id": "acpb_lHz0OcJgkwoBSDdNDAGU9o6wQQXFATP8",
    "input_time": "2024-07-16 14:18:23",
    "txamount": 6.73,
    "receipt_id": "20109082",
    "ref_no": "",
    "floor": "02",
    "unit": "A",
    "invoice_no": "0999900000034",
    "trs_val": 0.17,
    "item_id": "管理費",
    "term": "2024/03",
    "remark": "",
    "pay_type": "POS_CHEQUE"
  }
] */
  /// 11, 獲取指定「歷史清機」「細明」
  /// Endpoint: POST /v1/pos/get_bank_in_record_details
  /// Body: {"blg_id": "string", "record_id": "string"}
  Future<Map<String, dynamic>> getBankInRecordDetails({
    required String blgId,
    required String recordId,
  }) async {
    final Uri url = _buildUri('/pos/get_bank_in_record_details');
    final Map<String, dynamic> requestBody = {
      'blg_id': blgId,
      'record_id': recordId,
    };

    _logger.i(' 獲取清機記錄細明，大廈ID: $blgId, 記錄ID: $recordId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取清機記錄細明');
    } catch (e) {
      _logger.e(' 獲取清機記錄細明失敗: $e');
      rethrow;
    }
  }

  /* 12.eg{[
  {
    "id": 3,
    "title": "富邦銀行-綜合",
    "account_no": "128-830-0-702-961-1",
    "is_default": 1,
    "building_id": "0241100"
  }
] */
  /// 12, 獲取大廈銀行賬戶信息
  /// Endpoint: POST /v1/building-bank-account
  /// Body: {"blg_id": "string"}
  Future<Map<String, dynamic>> getBuildingBankAccount(
      {required String blgId}) async {
    final Uri url = _buildUri('/building-bank-account');
    final Map<String, dynamic> requestBody = {'blg_id': blgId};

    _logger.i(' 獲取大廈銀行賬戶信息，大廈ID: $blgId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取大廈銀行賬戶信息');
    } catch (e) {
      _logger.e(' 獲取大廈銀行賬戶信息失敗: $e');
      rethrow;
    }
  }

  /// 13, 處理HTTP響應 - 單個對象
  Map<String, dynamic> _handleResponse(http.Response response, String apiName) {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _logger.i(' $apiName 成功 (狀態碼: ${response.statusCode})');

      if (decodedBody.isEmpty) {
        return {};
      }

      try {
        final decoded = json.decode(decodedBody);

        // 特殊處理：如果返回的是數組，包裝成對象格式
        if (decoded is List) {
          return {'transaction_types': decoded};
        }

        return decoded is Map<String, dynamic> ? decoded : {};
      } catch (e) {
        _logger.e(' 解析JSON響應失敗: $e');
        throw Exception('解析響應數據失敗: $e');
      }
    } else {
      _logger.w(' $apiName 失敗 (狀態碼: ${response.statusCode}), 響應: $decodedBody');
      throw Exception('API請求失敗，狀態碼: ${response.statusCode}');
    }
  }

  /// 14, 處理HTTP響應 - 數組
  List<Map<String, dynamic>> _handleArrayResponse(
      http.Response response, String apiName) {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _logger.i(' $apiName 成功 (狀態碼: ${response.statusCode})');

      if (decodedBody.isEmpty) {
        return [];
      }

      try {
        final decoded = json.decode(decodedBody);

        if (decoded is List) {
          return _mapsFromList(decoded);
        } else if (decoded is Map &&
            decoded.containsKey('data') &&
            decoded['data'] is List) {
          return _mapsFromList(decoded['data'] as List);
        } else {
          _logger.w(' 期望數組響應但收到: ${decoded.runtimeType}');
          return [];
        }
      } catch (e) {
        _logger.e(' 解析JSON數組響應失敗: $e');
        throw Exception('解析響應數據失敗: $e');
      }
    } else {
      _logger.w(' $apiName 失敗 (狀態碼: ${response.statusCode}), 響應: $decodedBody');
      throw Exception('API請求失敗，狀態碼: ${response.statusCode}');
    }
  }

  List<Map<String, dynamic>> _mapsFromList(List<dynamic> items) {
    final maps = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        maps.add(item);
      } else if (item is Map) {
        maps.add(item.map((key, value) => MapEntry(key.toString(), value)));
      }
    }
    return maps;
  }

  /// 15, 創建繳費數據模型
  /// 用於構建標準的繳費請求數據
  Map<String, dynamic> createPaymentData({
    required String amount,
    required String authNo,
    required String batchNo,
    required String businessId,
    required String cardNo,
    required String cardOrgn,
    required String currency,
    required String date,
    required String merchId,
    required String merchName,
    required String refNo,
    required String rejCode,
    required String rejCodeCn,
    required String terId,
    required String time,
    required String traceNo,
    required String transChannel,
    required String transTicketNo,
    required String transTraceNo,
    required List<Map<String, dynamic>> billObjs,
  }) {
    return {
      'AMOUNT': amount,
      'AUTH_NO': authNo,
      'BATCH_NO': batchNo,
      'BUSINESS_ID': businessId,
      'CARDNO': cardNo,
      'CARD_ORGN': cardOrgn,
      'CURRENCY': currency,
      'DATE': date,
      'MERCH_ID': merchId,
      'MERCH_NAME': merchName,
      'REF_NO': refNo,
      'REJCODE': rejCode,
      'REJCODE_CN': rejCodeCn,
      'TER_ID': terId,
      'TIME': time,
      'TRACE_NO': traceNo,
      'TRANS_CHANNEL': transChannel,
      'TRANS_TICKET_NO': transTicketNo,
      'TRANS_TRACE_NO': transTraceNo,
      'BILL_OBJ': billObjs,
    };
  }

  /// 16, 創建賬單對象模型
  /// 用於構建標準的賬單數據
  Map<String, dynamic> createBillObject({
    required String flatCode,
    required String itemId,
    required String trsTo,
    required String billDt,
    required double netAmount,
    required String invoiceNo,
  }) {
    return {
      'flat_code': flatCode,
      'item_id': itemId,
      'trs_to': trsTo,
      'bill_dt': billDt,
      'net_amount': netAmount,
      'invoice_no': invoiceNo,
    };
  }

  /// 17, 獲取物業管理費用狀態
  /// Endpoint: POST /v1/building_board/building-management-fee-status
  /// Body: {"ptype": "mf", "blg_id": "string"}
  Future<Map<String, dynamic>> getBuildingManagementFeeStatus({
    String? buildingId,
  }) async {
    final Uri url = _buildUri('/building_board/building-management-fee-status');
    final Map<String, dynamic> requestBody = {
      'ptype': 'mf',
      if (buildingId != null) 'blg_id': buildingId,
    };

    _logger.i(' 獲取物業管理費用狀態，大廈ID: $buildingId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取物業管理費用狀態');
    } catch (e) {
      _logger.e(' 獲取物業管理費用狀態失敗: $e');
      rethrow;
    }
  }

  /// 18, 獲取物業其他費用狀態
  /// Endpoint: POST /v1/building_board/building-other-fee-status
  /// Body: {"ptype": "mf", "blg_id": "string"}
  Future<Map<String, dynamic>> getBuildingOtherFeeStatus({
    String? buildingId,
  }) async {
    final Uri url = _buildUri('/building_board/building-other-fee-status');
    final Map<String, dynamic> requestBody = {
      'ptype': 'mf',
      if (buildingId != null) 'blg_id': buildingId,
    };

    _logger.i(' 獲取物業其他費用狀態，大廈ID: $buildingId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '獲取物業其他費用狀態');
    } catch (e) {
      _logger.e(' 獲取物業其他費用狀態失敗: $e');
      rethrow;
    }
  }

  /// 19, 創建微信支付請求
  /// 用於生成微信支付二維碼或支付鏈接
  Future<Map<String, dynamic>> createWechatPayment({
    required String buildingId,
    required String unitId,
    required double amount,
    required List<Map<String, dynamic>> bills,
    String? remark,
  }) async {
    final Uri url = _buildUri('/pos/create-wechat-payment');
    final Map<String, dynamic> requestBody = {
      'building_id': buildingId,
      'unit_id': unitId,
      'amount': amount.toStringAsFixed(2),
      'payment_method': 'WECHAT',
      'bills': bills,
      if (remark != null) 'remark': remark,
    };

    _logger.i(' 創建微信支付請求，單位ID: $unitId, 金額: $amount');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '創建微信支付請求');
    } catch (e) {
      _logger.e(' 創建微信支付請求失敗: $e');
      rethrow;
    }
  }

  /// 20, 創建支付寶支付請求
  /// 用於生成支付寶支付二維碼或支付鏈接
  Future<Map<String, dynamic>> createAlipayPayment({
    required String buildingId,
    required String unitId,
    required double amount,
    required List<Map<String, dynamic>> bills,
    String? remark,
  }) async {
    final Uri url = _buildUri('/pos/create-alipay-payment');
    final Map<String, dynamic> requestBody = {
      'building_id': buildingId,
      'unit_id': unitId,
      'amount': amount.toStringAsFixed(2),
      'payment_method': 'ALIPAY',
      'bills': bills,
      if (remark != null) 'remark': remark,
    };

    _logger.i(' 創建支付寶支付請求，單位ID: $unitId, 金額: $amount');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '創建支付寶支付請求');
    } catch (e) {
      _logger.e(' 創建支付寶支付請求失敗: $e');
      rethrow;
    }
  }

  /// 20.1, 創建雲閃付支付請求
  /// 用於生成雲閃付支付二維碼或支付鏈接
  Future<Map<String, dynamic>> createUnionpayPayment({
    required String buildingId,
    required String unitId,
    required double amount,
    required List<Map<String, dynamic>> bills,
    String? remark,
  }) async {
    final Uri url = _buildUri('/pos/create-unionpay-payment');
    final Map<String, dynamic> requestBody = {
      'building_id': buildingId,
      'unit_id': unitId,
      'amount': amount.toStringAsFixed(2),
      'payment_method': 'UNIONPAY',
      'bills': bills,
      if (remark != null) 'remark': remark,
    };

    _logger.i(' 創建雲閃付支付請求，單位ID: $unitId, 金額: $amount');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '創建雲閃付支付請求');
    } catch (e) {
      _logger.e(' 創建雲閃付支付請求失敗: $e');
      rethrow;
    }
  }

  /// 21, 查詢支付狀態
  /// 用於輪詢檢查支付是否完成
  Future<Map<String, dynamic>> queryPaymentStatus({
    required String paymentId,
  }) async {
    final Uri url = _buildUri('/pos/query-payment-status');
    final Map<String, dynamic> requestBody = {
      'payment_id': paymentId,
    };

    _logger.i(' 查詢支付狀態，支付ID: $paymentId');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
          .timeout(_requestTimeout);

      return _handleResponse(response, '查詢支付狀態');
    } catch (e) {
      _logger.e(' 查詢支付狀態失敗: $e');
      rethrow;
    }
  }

  /// 22, 創建支付小票數據
  /// 用於構建打印小票的數據結構
  Map<String, dynamic> createReceiptData({
    required String paymentId,
    required String buildingName,
    required String unitName,
    required String paymentMethod,
    required double totalAmount,
    required List<Map<String, dynamic>> bills,
    DateTime? paymentTime,
    String? transactionId,
    String? remark,
  }) {
    return {
      'payment_id': paymentId,
      'building_name': buildingName,
      'unit_name': unitName,
      'payment_method': paymentMethod,
      'total_amount': totalAmount,
      'bills': bills,
      'payment_time':
          paymentTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'transaction_id': transactionId,
      'remark': remark,
    };
  }
}
