import 'package:package_info_plus/package_info_plus.dart';

Future<String> loadAppVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}
