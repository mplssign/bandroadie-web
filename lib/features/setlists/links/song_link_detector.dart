import 'song_link.dart';

/// Detects the link type from a URL string.
///
/// Uses hostname and pattern matching to classify URLs.
/// Returns [SongLinkType.generic] if no match is found.
SongLinkType detectLinkType(String url) {
  // Try to parse the URL
  final uri = Uri.tryParse(url.toLowerCase());

  if (uri == null) {
    // If URL cannot be parsed, return generic
    return SongLinkType.generic;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();

  // Check for YouTube
  if (host.contains('youtube.com') ||
      host.contains('youtu.be') ||
      host.contains('m.youtube.com')) {
    return SongLinkType.youtube;
  }

  // Check for Spotify
  if (host.contains('spotify.com') || host.contains('open.spotify.com')) {
    return SongLinkType.spotify;
  }

  // Check for Apple Music
  if (host.contains('music.apple.com') || host.contains('itunes.apple.com')) {
    return SongLinkType.appleMusic;
  }

  // Check for Amazon Music
  if (host.contains('music.amazon.com') ||
      url.toLowerCase().contains('amazon.com/music')) {
    return SongLinkType.amazonMusic;
  }

  // Check for SoundCloud
  if (host.contains('soundcloud.com')) {
    return SongLinkType.soundcloud;
  }

  // Check for Google Docs
  if (host.contains('docs.google.com') && path.contains('/document')) {
    return SongLinkType.googleDocs;
  }

  // Check for Google Sheets
  if (host.contains('docs.google.com') && path.contains('/spreadsheets')) {
    return SongLinkType.googleSheets;
  }

  // Check for PDF (case-insensitive extension check)
  if (url.toLowerCase().endsWith('.pdf')) {
    return SongLinkType.pdf;
  }

  // Default to generic for unrecognized URLs
  return SongLinkType.generic;
}
