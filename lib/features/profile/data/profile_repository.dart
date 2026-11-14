import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<UserProfile?> getByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select()
        .ilike('username', username)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return _hydrate(Map<String, dynamic>.from(row));
  }

  Future<UserProfile?> getById(String id) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return _hydrate(Map<String, dynamic>.from(row));
  }

  Future<UserProfile> _hydrate(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final results = await Future.wait([
      _client
          .from('profile_mentions')
          .select(
            'custom_tag,mentioned:profiles!profile_mentions_mentioned_profile_id_fkey(username,display_name,avatar_url)',
          )
          .eq('profile_id', id)
          .order('position'),
    ]);

    final mentions = (results[0] as List).map((value) {
      final mentioned = value['mentioned'] as Map<String, dynamic>;
      return ProfileMention(
        username: mentioned['username'] as String,
        displayName: mentioned['display_name'] as String,
        avatarUrl: mentioned['avatar_url'] as String?,
        tag: value['custom_tag'] as String,
      );
    }).toList();

    return UserProfile(
      id: id,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
      bio: row['bio'] as String? ?? '',
      bioAlignment: BioAlignment.fromDatabase(row['bio_alignment'] as String?),
      avatarUrl: row['avatar_url'] as String?,
      bannerUrl: row['banner_url'] as String?,
      zodiac: row['zodiac'] as String?,
      mentions: mentions,
      backgroundColor: profileColorFromHex(
        row['profile_background_color'] as String?,
        Colors.white,
      ),
      accentColor: profileColorFromHex(
        row['profile_accent_color'] as String?,
        const Color(0xFF000000),
      ),
    );
  }

  Future<void> save(String profileId, ProfileDraft draft) async {
    await _client
        .from('profiles')
        .update({
          'display_name': draft.displayName,
          'bio': draft.bio,
          'bio_alignment': draft.bioAlignment.name,
          'avatar_url': draft.avatarUrl,
          'banner_url': draft.bannerUrl,
          'profile_background_color': profileColorToHex(draft.backgroundColor),
          'profile_accent_color': profileColorToHex(draft.accentColor),
        })
        .eq('id', profileId);

    final mentionRows = <Map<String, dynamic>>[];
    final selectedMentions = draft.mentions.take(1).toList();
    for (var index = 0; index < selectedMentions.length; index++) {
      final mention = selectedMentions[index];
      final target = await _client
          .from('profiles')
          .select('id')
          .ilike('username', mention.username)
          .maybeSingle();
      if (target == null) {
        throw ProfileSaveException('User @${mention.username} was not found.');
      }
      if (target['id'] == profileId) {
        throw const ProfileSaveException('You cannot mention yourself.');
      }
      mentionRows.add({
        'profile_id': profileId,
        'mentioned_profile_id': target['id'],
        'custom_tag': mention.tag,
        'position': index,
      });
    }

    await _client.from('profile_mentions').delete().eq('profile_id', profileId);
    if (mentionRows.isNotEmpty) {
      await _client.from('profile_mentions').insert(mentionRows);
    }
  }
}

class ProfileSaveException implements Exception {
  const ProfileSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
