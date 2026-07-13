import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'multi_screen_presentation_platform_interface.dart';

/// An implementation of [MultiScreenPresentationPlatform] that uses method channels.
class MethodChannelMultiScreenPresentation extends MultiScreenPresentationPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('multi_screen_presentation');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
