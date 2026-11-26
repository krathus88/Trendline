import 'package:supabase_flutter/supabase_flutter.dart';

/// The recipes the user has starred: their own or their household's, each
/// member's favourites their own.
abstract interface class RecipeFavouritesRepository {
  /// The starred recipes' IDs.
  Future<Set<String>> fetchAll();

  Future<void> add(String recipeId);

  Future<void> remove(String recipeId);
}

class SupabaseRecipeFavouritesRepository
    implements RecipeFavouritesRepository {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<Set<String>> fetchAll() async {
    final rows = await _db.from('recipe_favourites').select('recipe_id');
    return {for (final r in rows) r['recipe_id'] as String};
  }

  @override
  Future<void> add(String recipeId) async {
    // Starring twice is harmless: the primary key keeps one row.
    await _db
        .from('recipe_favourites')
        .upsert({'recipe_id': recipeId}, ignoreDuplicates: true);
  }

  @override
  Future<void> remove(String recipeId) async {
    await _db.from('recipe_favourites').delete().eq('recipe_id', recipeId);
  }
}
