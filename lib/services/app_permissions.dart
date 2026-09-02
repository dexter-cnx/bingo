import 'package:permission_handler/permission_handler.dart';

enum AppPermissionResult { granted, denied, permanentlyDenied }

class AppPermissions {
  const AppPermissions._();

  static Future<AppPermissionResult> requestMicrophone() async {
    return _request(Permission.microphone);
  }

  static Future<AppPermissionResult> requestCamera() async {
    return _request(Permission.camera);
  }

  static Future<AppPermissionResult> _request(Permission permission) async {
    final current = await permission.status;
    if (current.isGranted || current.isLimited) {
      return AppPermissionResult.granted;
    }
    if (current.isPermanentlyDenied || current.isRestricted) {
      return AppPermissionResult.permanentlyDenied;
    }
    final requested = await permission.request();
    if (requested.isGranted || requested.isLimited) {
      return AppPermissionResult.granted;
    }
    if (requested.isPermanentlyDenied || requested.isRestricted) {
      return AppPermissionResult.permanentlyDenied;
    }
    return AppPermissionResult.denied;
  }
}
