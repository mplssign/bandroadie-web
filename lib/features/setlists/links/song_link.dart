import 'dart:convert';

/// Types of links that can be associated with a song.
enum SongLinkType {
  youtube,
  spotify,
  appleMusic,
  amazonMusic,
  soundcloud,
  googleDocs,
  googleSheets,
  pdf,
  generic,
}

/// A link associated with a song (YouTube, Spotify, PDF, etc.).
///
/// Stored as JSON in the `songs.youtube_links` column.
class SongLink {
  final String title;
  final String url;
  final SongLinkType type;

  const SongLink({
    required this.title,
    required this.url,
    required this.type,
  });

  /// Creates a [SongLink] from a JSON map.
  ///
  /// If the `type` field is missing or unrecognized, defaults to [SongLinkType.youtube]
  /// for backward compatibility with existing data.
  factory SongLink.fromJson(Map<String, dynamic> json) {
    final typeString = json['type'] as String?;
    final type = _parseType(typeString);

    return SongLink(
      title: json['title'] as String,
      url: json['url'] as String,
      type: type,
    );
  }

  /// Converts this [SongLink] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'type': type.name,
    };
  }

  /// Parses a list of [SongLink]s from a JSON string.
  ///
  /// Returns an empty list if [jsonString] is null or invalid.
  static List<SongLink> listFromJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((item) => SongLink.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }
  }

  /// Converts a list of [SongLink]s to a JSON string.
  static String listToJson(List<SongLink> links) {
    if (links.isEmpty) {
      return '[]';
    }
    return json.encode(links.map((link) => link.toJson()).toList());
  }

  /// Parses a type string to [SongLinkType].
  ///
  /// Returns [SongLinkType.youtube] if the string is null or unrecognized.
  static SongLinkType _parseType(String? typeString) {
    if (typeString == null) {
      return SongLinkType.youtube;
    }

    // Try to match the type string to an enum value
    for (final type in SongLinkType.values) {
      if (type.name == typeString) {
        return type;
      }
    }

    // Default to youtube for unrecognized types
    return SongLinkType.youtube;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SongLink &&
        other.title == title &&
        other.url == url &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(title, url, type);
}
