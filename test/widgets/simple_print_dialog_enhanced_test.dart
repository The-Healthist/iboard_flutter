import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/widgets/print/simple_print_dialog_enhanced.dart';

void main() {
  group('enhanced print dialog job parsing', () {
    test('normalizes map-shaped job responses and skips malformed rows', () {
      final jobs = normalizePrinterJobsById({
        101: {
          'job_id': '101',
          'status': 'pending',
        },
        'bad': 'not-a-job',
        '102': {
          'cups_job_id': 102,
          'state_code': 5,
        },
      });

      expect(jobs.keys, ['101', '102']);
      expect(jobs['101']['job_id'], '101');
      expect(jobs['102']['cups_job_id'], 102);
    });

    test('normalizes list-shaped job responses using job identifiers', () {
      final jobs = normalizePrinterJobsById([
        {
          'job_id': '201',
          'status': 'pending',
        },
        'bad',
        {
          'cups_job_id': 202,
          'completed': 'true',
        },
        {
          'status': 'unknown',
        },
      ]);

      expect(jobs.keys, ['201', '202', '3']);
      expect(jobs['202']['completed'], 'true');
    });

    test('reads job state from flexible job values', () {
      final jobs = normalizePrinterJobsById([
        {
          'cups_job_id': '301',
          'state_code': '5',
        },
        {
          'job_id': 302,
          'completed': 1,
        },
      ]);

      expect(printerJobStateFromJobs(jobs, 301), 'processing');
      expect(printerJobStateFromJobs(jobs, 302), 'completed');
      expect(printerJobStateFromJobs(jobs, 999), 'unknown');
    });

    test('finds new jobs and parses string ids safely', () {
      final jobs = normalizePrinterJobsById([
        {
          'cups_job_id': '401',
        },
        {
          'job_id': '402',
        },
      ]);

      expect(findNewPrinterJobId({'401'}, jobs), 402);
      expect(findNewPrinterJobId({'401', '402'}, jobs), isNull);
    });
  });
}
