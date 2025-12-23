import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import '../models/channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class PlaylistService {
  static const String _prefKeyUrl = 'custom_playlist_url';
  static const String _prefKeyFilePath = 'custom_playlist_file_path';
  static const String _prefKeySourceType = 'playlist_source_type'; // 'url' or 'file'
  static const String _cacheFileName = 'playlist_cache.m3u';

  Future<List<Channel>> fetchPlaylist({bool force = false}) async {
    String content = "";
    try {
      final prefs = await SharedPreferences.getInstance();
      final sourceType = prefs.getString(_prefKeySourceType) ?? 'url';

      if (sourceType == 'file') {
         // FILE MODE (Always read file, it's local and fast)
         final path = prefs.getString(_prefKeyFilePath);
         if (path != null && path.isNotEmpty) {
            print("Reading from local file: $path");
            final file = File(path);
            if (await file.exists()) {
               final bytes = await file.readAsBytes();
               content = utf8.decode(bytes); // Force UTF-8
               print("Loaded local file (${content.length} chars)");
            } else {
               print("File not found: $path");
            }
         }
      } else {
         // URL MODE
         // 1. Try Cache First (if not forced)
         if (!force) {
           content = await _readFromCache() ?? "";
           if (content.isNotEmpty) {
             print("Loaded playlist from Cache.");
             return parseM3U(content);
           }
         }

         // 2. Fetch from Network (if forced or cache empty)
         final url = prefs.getString(_prefKeyUrl);
         if (url != null && url.isNotEmpty) {
           try {
             print("Fetching from stored URL: $url");
             final response = await http.get(Uri.parse(url));
             if (response.statusCode == 200) {
               content = utf8.decode(response.bodyBytes);
               await _saveToCache(content);
               print("Playlist Updated from Network");
             } else {
                throw Exception("Status ${response.statusCode}");
             }
           } catch (e) {
             print("Network fetch failed ($e)");
             if (content.isEmpty) {
                content = await _readFromCache() ?? "";
             }
           }
         }
      }
      
      // Fallback
      if (content.isEmpty && sourceType == 'url') {
         content = await _readFromCache() ?? "";
      }

      // Last Resort: Assets
      if (content.isEmpty) {
        print("Loading default asset playlist...");
        content = await rootBundle.loadString('assets/playlist.m3u');
      }

      return parseM3U(content);
    } catch (e) {
      print('Error fetching playlist: $e');
      return [];
    }
  }

  Future<void> savePlaylistSource(String type, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySourceType, type);
    if (type == 'url') {
      await prefs.setString(_prefKeyUrl, value);
    } else {
      await prefs.setString(_prefKeyFilePath, value);
    }
  }
  
  Future<Map<String, String>> getPlaylistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'type': prefs.getString(_prefKeySourceType) ?? 'url',
      'url': prefs.getString(_prefKeyUrl) ?? '',
      'path': prefs.getString(_prefKeyFilePath) ?? '',
    };
  }

  // Deprecated singular getters/setters in favor of unified method above, but keeping for compatibility if needed
  Future<void> savePlaylistUrl(String url) async => savePlaylistSource('url', url);
  Future<String?> getPlaylistUrl() async => (await getPlaylistSettings())['url'];

  Future<void> _saveToCache(String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      await file.writeAsString(content);
    } catch (e) {
      print("Cache write error: $e");
    }
  }

  Future<String?> _readFromCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_cacheFileName');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print("Cache read error: $e");
    }
    return null;
  }

  // Check account expiration using logic from Electron App
  Future<String?> checkExpiration(String sampleUrl) async {
    try {
      final parts = sampleUrl.split('/');
      
      String host = "";
      String user = "";
      String pass = "";

      if (parts.length == 6) {
         host = "${parts[0]}//${parts[2]}";
         user = parts[3];
         pass = parts[4];
      } else if (parts.length == 7) {
         host = "${parts[0]}//${parts[2]}";
         user = parts[4];
         pass = parts[5];
      } else {
        return null;
      }

      final apiUrl = Uri.parse("$host/player_api.php?username=$user&password=$pass");
      print("Check Auth: $apiUrl");

      final response = await http.get(apiUrl);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data != null && data['user_info'] != null) {
          final expTimestamp = data['user_info']['exp_date']; // Unix Timestamp
          if (expTimestamp != null) {
             final date = DateTime.fromMillisecondsSinceEpoch(int.parse(expTimestamp.toString()) * 1000);
             return "${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}";
          }
        }
      }
    } catch (e) {
      print("Auth Check Failed: $e");
    }
    return null;
  }

  List<Channel> parseM3U(String content) {
    List<Channel> channels = [];
    final lines = content.split('\n');
    
    String? currentName;
    String? currentGroup;
    String? currentLogo;
    String? currentTvgName;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final nameParts = line.split(',');
        currentName = nameParts.length > 1 ? nameParts.sublist(1).join(',').trim() : nameParts.last.trim();

        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentGroup = groupMatch?.group(1) ?? 'Ungrouped';

        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        currentLogo = logoMatch?.group(1);

         final tvgNameMatch = RegExp(r'tvg-name="([^"]*)"').firstMatch(line);
         currentTvgName = tvgNameMatch?.group(1);

      } else if (!line.startsWith('#')) {
        if (currentName != null) {
          // Detect Type
          ChannelType type = ChannelType.unknown;
          if (line.contains('/movie/')) {
            type = ChannelType.movie;
          } else if (line.contains('/series/')) {
            type = ChannelType.series;
          } else {
            type = ChannelType.live;
          }

          channels.add(Channel(
            name: currentName,
            url: line,
            group: currentGroup ?? 'Ungrouped',
            logoUrl: currentLogo,
            tvgName: currentTvgName,
            type: type,
          ));
          currentName = null;
          currentGroup = null;
          currentLogo = null;
          currentTvgName = null;
        }
      }
    }
    return channels;
  }
}
