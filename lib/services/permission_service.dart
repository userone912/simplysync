import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

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

  /// Test if the app can write to a specific directory
  static Future<bool> canWriteToDirectory(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      
      // Check if directory exists
      if (!await directory.exists()) {
        return false;
      }

      // Try to create a test file
      final testFileName = '.simplysync_write_test_${DateTime.now().millisecondsSinceEpoch}';
      final testFile = File('${directory.path}/$testFileName');
      
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
