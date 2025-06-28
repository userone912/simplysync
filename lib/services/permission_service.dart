import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStoragePermission() async {
    // Request storage permission
    PermissionStatus status = await Permission.storage.status;
    
    if (status.isDenied) {
      status = await Permission.storage.request();
    }
    
    // For Android 11 and above, we need to request MANAGE_EXTERNAL_STORAGE
    if (status.isDenied) {
      status = await Permission.manageExternalStorage.request();
    }
    
    return status.isGranted;
  }

  static Future<bool> requestNotificationPermission() async {
    PermissionStatus status = await Permission.notification.status;
    
    if (status.isDenied) {
      status = await Permission.notification.request();
    }
    
    return status.isGranted;
  }

  static Future<bool> requestAllPermissions() async {
    final Map<Permission, PermissionStatus> permissions = await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.notification,
    ].request();
    
    bool allGranted = true;
    
    permissions.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
    });
    
    return allGranted;
  }

  static Future<Map<Permission, PermissionStatus>> checkAllPermissions() async {
    return await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.notification,
    ].request();
  }

  static Future<bool> hasStoragePermission() async {
    final storageStatus = await Permission.storage.status;
    final manageStorageStatus = await Permission.manageExternalStorage.status;
    
    return storageStatus.isGranted || manageStorageStatus.isGranted;
  }

  static Future<bool> hasNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
