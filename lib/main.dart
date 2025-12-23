import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'services/playlist_service.dart';
import 'models/channel.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV Next Gen',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyScreen(),
    );
  }
}

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => MyScreenState();
}

class MyScreenState extends State<MyScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  
  // Playlist State
  List<Channel> allChannels = [];
  Map<String, List<Channel>> groupedChannels = {};
  List<String> categories = []; // Changed to List for ordering
  
  bool isLoading = true;
  Channel? selectedChannel;
  String? expirationDate;
  
  // Search & UI State
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = "";
  Key _listKey = UniqueKey();
  ChannelType _filterType = ChannelType.unknown; // unknown = ALL
  String _selectedCategory = "All"; // "All" or specific country like "TR"

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }


  
  // Actually, I will modify _loadPlaylist signature first.
  // But wait, the replaces needs to be contiguous. 
  
  // Let's replace _loadPlaylist signature.
  Future<void> _loadPlaylist({bool force = false}) async {
    try {
      final service = PlaylistService();
      final fetchedChannels = await service.fetchPlaylist(force: force);
      
      // ... (Logic remains similar but need to ensure I don't break it) ...
      
      // Extract Categories logic ...
      final Set<String> uniqueCats = {"All"};
      for (var c in fetchedChannels) {
        if (c.group.contains(' ➾ ')) {
          uniqueCats.add(c.group.split(' ➾ ')[0].trim());
        }
      }
      print("Unique Categories Found: ${uniqueCats.length}");
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Debug: Found ${uniqueCats.length} Country Categories"), duration: const Duration(seconds: 3)),
         );
      }

      // Sort
      final sortedList = uniqueCats.toList()..sort();
      sortedList.remove("All"); // Remove All to re-add at start

      setState(() {
        allChannels = fetchedChannels;
        categories = ["All", ...sortedList];
        isLoading = false;
      });
      
      _applyFilter();

      if (fetchedChannels.isNotEmpty) {
        final date = await service.checkExpiration(fetchedChannels.first.url);
        if (date != null) {
          setState(() {
            expirationDate = date;
          });
        }
      }
    } catch (e) {
      print("Error loading playlist: $e");
      setState(() {
        isLoading = false;
      });
    }
  }
  
  // And update manualRefresh to call it
  Future<void> _manualRefresh() async {
    setState(() { isLoading = true; });
    await _loadPlaylist(force: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Playlist Refreshed"), duration: Duration(seconds: 1)),
      );
    }
  }

  // And Stylize ToggleButtons


  void _applyFilter() {
    List<Channel> filtered = allChannels;
    
    // 1. Category Filter (Country)
    if (_selectedCategory != "All") {
       filtered = filtered.where((c) => c.group.startsWith("$_selectedCategory ➾ ")).toList();
    }

    // 2. Type Filter
    if (_filterType != ChannelType.unknown) {
        filtered = filtered.where((c) => c.type == _filterType).toList();
    }

    // 3. Search Filter
    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      filtered = filtered.where((c) {
        return c.name.toLowerCase().contains(term) ||
               (c.tvgName != null && c.tvgName!.toLowerCase().contains(term));
      }).toList();
    }

    // Grouping
    final groups = <String, List<Channel>>{};
    for (var c in filtered) {
       final g = c.group;
       if (!groups.containsKey(g)) groups[g] = [];
       groups[g]!.add(c);
    }
    
    final sortedKeys = groups.keys.toList()..sort();
    final sortedGroups = {for (var k in sortedKeys) k: groups[k]!};

    setState(() {
      groupedChannels = sortedGroups;
    });
  }

  void _onCategoryChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedCategory = newValue;
        _listKey = UniqueKey();
      });
      _applyFilter();
    }
  }

  void _onTypeChanged(ChannelType type) {
    setState(() {
      _filterType = type;
      _listKey = UniqueKey(); 
    });
    _applyFilter();
  }
  
  // ... (Icons helper same as before)
  IconData _getIconForType(ChannelType type) {
    switch (type) {
      case ChannelType.live: return Icons.tv;
      case ChannelType.movie: return Icons.movie;
      case ChannelType.series: return Icons.featured_video;
      default: return Icons.question_mark;
    }
  }

  void _onSearchChanged(String value) {
     setState(() {
       _searchTerm = value;
     });
     _applyFilter();
  }

  void _collapseAll() {
    setState(() {
      _listKey = UniqueKey();
    });
  }

  void _playChannel(Channel channel) {
    setState(() {
      selectedChannel = channel;
    });
    player.open(Media(channel.url));
  }



  void _showSettings() async {
    final service = PlaylistService();
    final settings = await service.getPlaylistSettings();
    
    String currentType = settings['type']!;
    final urlController = TextEditingController(text: settings['url']);
    String selectedFilePath = settings['path']!;
    
    // Local state for category selection within dialog
    String tempSelectedCategory = _selectedCategory; 

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Playlist Settings"),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       // COUNTRY FILTER (Moved here)
                      const Text("Select Country / Category:", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: categories.contains(tempSelectedCategory) ? tempSelectedCategory : "All",
                            isExpanded: true,
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setStateDialog(() {
                                  tempSelectedCategory = newValue;
                                });
                              }
                            },
                            items: categories.map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value, style: const TextStyle(fontSize: 14)),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 10),

                      // Source Toggle
                      Center(
                        child: ToggleButtons(
                          borderRadius: BorderRadius.circular(8),
                          borderColor: Colors.white54,
                          selectedBorderColor: Colors.blueAccent,
                          selectedColor: Colors.white,
                          fillColor: Colors.blueAccent.withOpacity(0.5),
                          color: Colors.white70,
                          isSelected: [currentType == 'url', currentType == 'file'],
                          onPressed: (index) {
                            setStateDialog(() {
                              currentType = index == 0 ? 'url' : 'file';
                            });
                          },
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("M3U URL")),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("Local File")),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
  
                      if (currentType == 'url') ...[
                        const Text("Enter M3U Playlist URL (Auto-Updates):"),
                        const SizedBox(height: 10),
                        TextField(
                          controller: urlController,
                          decoration: const InputDecoration(
                            hintText: "http://example.com/playlist.m3u",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ] else ...[
                        const Text("Select Local M3U File:"),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  selectedFilePath.isEmpty ? "No file selected" : selectedFilePath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: selectedFilePath.isEmpty ? Colors.grey : Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                FilePickerResult? result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['m3u', 'm3u8', 'txt'],
                                );
  
                                if (result != null && result.files.single.path != null) {
                                  setStateDialog(() {
                                    selectedFilePath = result.files.single.path!;
                                  });
                                }
                              },
                              child: const Text("Pick"),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                     final value = currentType == 'url' ? urlController.text.trim() : selectedFilePath;
                     
                     // Apply Category Change
                     if (tempSelectedCategory != _selectedCategory) {
                        _onCategoryChanged(tempSelectedCategory);
                     }
                     
                     if (value.isNotEmpty) {
                        await service.savePlaylistSource(currentType, value);
                        if (mounted) {
                          Navigator.pop(ctx);
                          _manualRefresh();
                        }
                     } else {
                        // Just close if only category changed
                        if (mounted) Navigator.pop(ctx);
                     }
                  },
                  child: const Text("Save & Update"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IPTV Next Gen')),
      body: Row(
        children: [
          // Sidebar
          SizedBox(
            width: 350,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  color: Colors.black12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Channels", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          Row(
                            children: [
                               IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _manualRefresh),
                               IconButton(icon: const Icon(Icons.settings, size: 20), onPressed: _showSettings),
                               IconButton(icon: const Icon(Icons.unfold_less, size: 20), onPressed: _collapseAll),
                            ],
                          )
                        ],
                      ),
                      if (expirationDate != null) Text("Expires: $expirationDate", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                      const SizedBox(height: 10),


                      
                      // TYPE FILTER BUTTONS
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                             _buildFilterChip("All", ChannelType.unknown),
                             _buildFilterChip("Live", ChannelType.live),
                             _buildFilterChip("Movies", ChannelType.movie),
                             _buildFilterChip("Series", ChannelType.series),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Search Bar
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search in $_selectedCategory...",
                          prefixIcon: const Icon(Icons.search),
                          isDense: true, filled: true, fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          suffixIcon: _searchTerm.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _onSearchChanged(""); }) : null,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // List
                Expanded(
                  child: isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        key: _listKey,
                        itemCount: groupedChannels.keys.length,
                        itemBuilder: (context, index) {
                          final groupName = groupedChannels.keys.elementAt(index);
                          final channels = groupedChannels[groupName]!;
                          final bool shouldExpand = _searchTerm.isNotEmpty;

                          return ExpansionTile(
                            key: PageStorageKey<String>(groupName),
                            initiallyExpanded: shouldExpand,
                            title: Text("$groupName (${channels.length})", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            children: channels.map((channel) {
                               return ListTile(
                                 selected: selectedChannel == channel,
                                 selectedTileColor: Colors.blue.withOpacity(0.2),
                                 dense: true,
                                 leading: Icon(_getIconForType(channel.type), size: 16, color: Colors.white54), // Show Type Icon
                                 title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                 onTap: () => _playChannel(channel),
                               );
                            }).toList(),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
          // Player
          Expanded(child: Center(child: SizedBox(width: MediaQuery.of(context).size.width, child: Video(controller: controller)))),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, ChannelType type) {
    final bool isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          if (selected) _onTypeChanged(type);
        },
      ),
    );
  }
}
