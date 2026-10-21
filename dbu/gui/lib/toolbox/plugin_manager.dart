// ignore_for_file: non_constant_identifier_names

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : plugin_manager.dart
 */

library toolbox;

import 'package:flutter/foundation.dart';
import 'ez_output.dart';

/// Abstract Interface for ezDBUtility Plugins
/// Enforces the lifecycle hooks and platform constraints.
abstract class EzPlugin {
  /// Plugin identifier name
  String get m_strPluginName;

  /// Supported platform matrix for elegant fallback/hiding
  Set<TargetPlatform> get m_setSupportedPlatforms;

  /// Lifecycle: [ Register ]
  Future<bool> onRegister();

  /// Lifecycle: [ Load ]
  Future<bool> onLoad();

  /// Lifecycle: [ Unregister ]
  Future<bool> onUnregister();

  /// Lifecycle: [ Unload ]
  Future<bool> onUnload();
}

/// Singleton Plugin Registry & Lifecycle Manager
class PluginManager {
  // Singleton pattern setup
  static final PluginManager _instance = PluginManager._internal();
  PluginManager._internal();

  static PluginManager get instance => _instance;

  // Member Variables strictly following naming convention (m_ + type + name)
  final Map<String, EzPlugin> m_mapRegistry = <String, EzPlugin>{};
  final Map<String, bool> m_mapLoadedStatus = <String, bool>{};

  /// Lifecycle Hook 1: [ Register ]
  Future<bool> registerPlugin(EzPlugin plugin) async {
    String strName = plugin.m_strPluginName;

    if (m_mapRegistry.containsKey(strName)) {
      ezOutput('[WARN] Plugin [$strName] is already registered.');
      return false;
    }

    // Check platform compatibility gracefully
    if (!plugin.m_setSupportedPlatforms.contains(defaultTargetPlatform)) {
      ezOutput('[INFO] Plugin [$strName] does not support current platform ($defaultTargetPlatform). Hiding gracefully.');
      return false;
    }

    ezOutput('[INFO] Registering Plugin: $strName...');
    bool bSuccess = await plugin.onRegister();

    if (bSuccess) {
      m_mapRegistry[strName] = plugin;
      m_mapLoadedStatus[strName] = false;
      ezOutput('[INFO] Plugin [$strName] registered successfully.');
    } else {
      ezOutput('[ERROR] Plugin [$strName] failed during registration.');
    }

    return bSuccess;
  }

  /// Lifecycle Hook 2: [ Load ]
  Future<bool> loadPlugin(String strName) async {
    if (!m_mapRegistry.containsKey(strName)) {
      ezOutput('[ERROR] Cannot load Plugin [$strName] because it is not registered.');
      return false;
    }

    if (m_mapLoadedStatus[strName] == true) {
      ezOutput('[INFO] Plugin [$strName] is already loaded.');
      return true;
    }

    ezOutput('[INFO] Loading Plugin: $strName...');
    EzPlugin plugin = m_mapRegistry[strName]!;
    bool bSuccess = await plugin.onLoad();

    if (bSuccess) {
      m_mapLoadedStatus[strName] = true;
      ezOutput('[INFO] Plugin [$strName] loaded and operational.');
    } else {
      ezOutput('[ERROR] Plugin [$strName] failed to load.');
    }

    return bSuccess;
  }

  /// Lifecycle Hook 3: [ Unregister ]
  Future<bool> unregisterPlugin(String strName) async {
    if (!m_mapRegistry.containsKey(strName)) {
      return false;
    }

    ezOutput('[INFO] Unregistering Plugin: $strName...');
    EzPlugin plugin = m_mapRegistry[strName]!;
    bool bSuccess = await plugin.onUnregister();

    if (bSuccess) {
      ezOutput('[INFO] Plugin [$strName] unregistered successfully.');
    } else {
      ezOutput('[ERROR] Plugin [$strName] failed to unregister properly.');
    }

    return bSuccess;
  }

  /// Lifecycle Hook 4: [ Unload ]
  Future<bool> unloadPlugin(String strName) async {
    if (!m_mapRegistry.containsKey(strName)) {
      return false;
    }

    ezOutput('[INFO] Unloading Plugin: $strName...');
    EzPlugin plugin = m_mapRegistry[strName]!;

    // Ensure it's unregistered before unloading
    await unregisterPlugin(strName);

    bool bSuccess = await plugin.onUnload();

    if (bSuccess) {
      m_mapRegistry.remove(strName);
      m_mapLoadedStatus.remove(strName);
      ezOutput('[INFO] Plugin [$strName] completely unloaded and removed from registry.');
    } else {
      ezOutput('[ERROR] Plugin [$strName] failed to unload completely.');
    }

    return bSuccess;
  }

  /// Gracefully shutdown all plugins
  Future<void> disposeAll() async {
    ezOutput('[INFO] Initiating global plugin shutdown sequence...');
    List<String> lstPluginNames = m_mapRegistry.keys.toList();

    for (String strName in lstPluginNames) {
      await unloadPlugin(strName);
    }
    ezOutput('[INFO] All plugins disposed.');
  }
}
