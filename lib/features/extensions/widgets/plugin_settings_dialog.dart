import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/models/extension_plugin.dart';
import '../../../core/storage/extension_repository.dart';

class PluginSettingsDialog extends ConsumerStatefulWidget {
  final ExtensionPlugin plugin;

  const PluginSettingsDialog({super.key, required this.plugin});

  @override
  ConsumerState<PluginSettingsDialog> createState() => _PluginSettingsDialogState();
}

class _PluginSettingsDialogState extends ConsumerState<PluginSettingsDialog> {
  final Map<String, dynamic> _values = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  Future<void> _loadValues() async {
    final storage = ref.read(extensionRepositoryProvider);
    final schema = widget.plugin.settingsSchema ?? [];
    
    for (var item in schema) {
      if (item is Map<String, dynamic>) {
        final id = item['id'];
        final defaultValue = item['default'];
        if (id != null) {
          final savedValue = storage.getExtensionData("${widget.plugin.packageName}:$id");
          _values[id] = savedValue ?? defaultValue;
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateValue(String id, dynamic value) async {
    setState(() {
      _values[id] = value;
    });
    final storage = ref.read(extensionRepositoryProvider);
    await storage.setExtensionData("${widget.plugin.packageName}:$id", value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }

    final schema = widget.plugin.settingsSchema ?? [];

    return AlertDialog(
      title: Text("${widget.plugin.name} Settings"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: schema.map((item) {
              if (item is! Map<String, dynamic>) return const SizedBox.shrink();
              return _buildSettingItem(item);
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }

  Widget _buildSettingItem(Map<String, dynamic> item) {
    final String? id = item['id'];
    final String name = item['name'] ?? id ?? "Unknown";
    final String type = item['type'] ?? "text";
    final String? description = item['description'];

    if (id == null) return const SizedBox.shrink();

    switch (type) {
      case 'toggle':
        return SwitchListTile(
          title: Text(name),
          subtitle: description != null ? Text(description) : null,
          value: _values[id] == true,
          onChanged: (val) => _updateValue(id, val),
        );
      case 'select':
        final List<dynamic> options = item['options'] ?? [];
        return ListTile(
          title: Text(name),
          subtitle: description != null ? Text(description) : null,
          trailing: DropdownButton<String>(
            value: _values[id]?.toString() ?? (options.isNotEmpty ? options.first.toString() : null),
            items: options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt.toString(),
                child: Text(opt.toString()),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) _updateValue(id, val);
            },
          ),
        );
      case 'text':
      default:
        return ListTile(
          title: Text(name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null) Text(description),
              TextFormField(
                initialValue: _values[id]?.toString(),
                decoration: const InputDecoration(isDense: true),
                onFieldSubmitted: (val) => _updateValue(id, val),
              ),
            ],
          ),
        );
    }
  }
}
