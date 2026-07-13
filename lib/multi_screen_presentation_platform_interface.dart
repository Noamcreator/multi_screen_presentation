import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'multi_screen_presentation_method_channel.dart';

abstract class MultiScreenPresentationPlatform extends PlatformInterface {
  /// Constructs a MultiScreenPresentationPlatform.
  MultiScreenPresentationPlatform() : super(token: _token);

  static final Object _token = Object();

  static MultiScreenPresentationPlatform _instance = MethodChannelMultiScreenPresentation();

  /// The default instance of [MultiScreenPresentationPlatform] to use.
  ///
  /// Defaults to [MethodChannelMultiScreenPresentation].
  static MultiScreenPresentationPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MultiScreenPresentationPlatform] when
  /// they register themselves.
  static set instance(MultiScreenPresentationPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
