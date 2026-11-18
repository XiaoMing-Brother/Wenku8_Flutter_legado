import 'package:flutter/services.dart';

import 'dict_rule.dart';

class DictRuleEngineUnavailable implements Exception {
  const DictRuleEngineUnavailable();

  @override
  String toString() => '当前构建未接入在线字典规则引擎';
}

/// Stable boundary to the Android rule engine. Rule syntax stays native so
/// JavaScript/CSS extraction behaves exactly like an imported book source.
class DictRuleTransport {
  const DictRuleTransport({
    this.channel = const MethodChannel('org.mewx.wenku8/dict_rules'),
  });

  final MethodChannel channel;

  Future<bool> available() async {
    try {
      return await channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String> lookup(DictRule rule, String word) async {
    try {
      final value = await channel.invokeMethod<String>('lookup', {
        'name': rule.name,
        'urlRule': rule.urlRule,
        'showRule': rule.showRule,
        'key': word,
      });
      return value ?? '';
    } on MissingPluginException {
      throw const DictRuleEngineUnavailable();
    } on PlatformException catch (error) {
      throw FormatException(
        error.message?.trim().isNotEmpty == true ? error.message! : '字典规则请求失败',
      );
    }
  }
}
