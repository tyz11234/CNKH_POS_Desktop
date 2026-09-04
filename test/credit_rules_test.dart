import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';

void main() {
  test('Staff cannot edit QR; Admin can', () {
    const staff = AppUser(username: 'staff', role: AppRole.staff);
    const admin = AppUser(username: 'admin', role: AppRole.admin);
    expect(staff.canEditQr, isFalse);
    expect(admin.canEditQr, isTrue);
    expect(staff.canDiscount, isTrue); // demo cashiering
  });
}
