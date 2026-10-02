import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';

/// Calculate and save at one SQLite serialization point, including cash credit
/// deposits and excluding voided sales. UI totals are display-only.
Future<void> saveAuthoritativeDailyClosing(
  DatabaseExecutor txn, {
  required String businessDate,
  required DateTime closedAt,
  required int openingCashCents,
  required int countedCashCents,
  required String closedBy,
  required String notes,
}) async {
  final parsed = DateTime.tryParse(businessDate);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != businessDate) {
    throw ArgumentError('营业日期无效');
  }
  final cash = Sqflite.firstIntValue(await txn.rawQuery('''
    SELECT COALESCE(SUM(CASE WHEN payment_method='CASH' THEN total_cents
      WHEN payment_method='CREDIT' AND deposit_method='CASH' THEN paid_cents
      ELSE 0 END),0) FROM sales
    WHERE voided=0 AND substr(sold_at,1,10)=?
  ''', [businessDate])) ?? 0;
  final previous = await txn.query('daily_closings', columns: ['id'],
      where: 'business_date=?', whereArgs: [businessDate]);
  await txn.insert('daily_closings', {
    'id': previous.isEmpty ? AppDatabase.newId() : previous.single['id'],
    'business_date': businessDate,
    'opening_cash_cents': openingCashCents,
    'counted_cash_cents': countedCashCents,
    'system_cash_cents': cash,
    'notes': notes,
    'closed_at': closedAt.toIso8601String(),
    'closed_by': closedBy,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
