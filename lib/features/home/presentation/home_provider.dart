import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/domain/entity/multimedia_item.dart';
import '../../../../core/extensions/extension_manager.dart';

final homeDataProvider = FutureProvider<Map<String, List<MultimediaItem>>>((
  ref,
) async {
  final activeProvider = ref.watch(activeProviderStateProvider);

  if (activeProvider == null) {
    throw Exception(
      'No provider selected. Please select a provider in settings.',
    );
  }

  final items = await activeProvider.getHome();
  if (items.isEmpty) {
    throw Exception('No data returned from provider.');
  }

  // Only keep alive after successful load to allow retries on error
  ref.keepAlive();
  return items;
});
