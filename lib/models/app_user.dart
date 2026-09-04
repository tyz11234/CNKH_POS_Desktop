enum AppRole { admin, staff }

class AppUser {
  final String username;
  final AppRole role;
  final String displayName;

  const AppUser({
    required this.username,
    required this.role,
    this.displayName = '',
  });

  bool get isAdmin => role == AppRole.admin;

  /// Demo: Admin always; Staff also allowed for local demo cashiering.
  bool get canDiscount => true;

  bool get canEditQr => isAdmin;

  String get roleLabelZh => isAdmin ? '管理员' : '员工';
  String get roleLabelEn => isAdmin ? 'Admin' : 'Staff';
  String get roleBadge => '$roleLabelZh / $roleLabelEn';
}
