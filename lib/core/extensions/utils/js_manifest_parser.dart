import 'dart:convert';
import 'package:flutter/foundation.dart';

class JsManifestParser {
  static final _manifestRegex = RegExp(
    r'getManifest\s*\(\s*\)\s*\{\s*return\s*(\{[\s\S]*?\});',
    multiLine: true,
  );
  static final _unquotedKeyRegex = RegExp(r'(\w+)\s*:');
  static final _unquotedValueRegex = RegExp(r':\s*([a-zA-Z_$][a-zA-Z0-9_$]*)');
  static final _trailingCommaRegex = RegExp(r',\s*\}');

  /// Extracts and parses the `getManifest()` return object from a JavaScript file content.
  /// 
  /// Handles:
  /// - Unquoted keys (e.g. `key: "value"`)
  /// - Unquoted variable values (e.g. `"baseUrl": mainUrl` -> `"baseUrl": "mainUrl"`)
  /// - Trailing commas
  static Map<String, dynamic>? parse(String content) {
    try {
      final match = _manifestRegex.firstMatch(content);

      if (match != null) {
        String jsonStr = match.group(1)!;

        jsonStr = jsonStr.replaceAllMapped(
          _unquotedKeyRegex,
          (m) => '"${m[1]}":',
        );

        jsonStr = jsonStr.replaceAllMapped(
          _unquotedValueRegex,
          (m) {
            final val = m.group(1)!;
            if (['true', 'false', 'null'].contains(val)) return ': $val';
            return ': "$val"';
          },
        );

        jsonStr = jsonStr.replaceAll(_trailingCommaRegex, '}');

        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("JsManifestParser: Error parsing manifest: $e");
    }
    return null;
  }
}
