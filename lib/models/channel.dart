enum ChannelType { live, movie, series, unknown }

class Channel {
  final String name;
  final String url;
  final String group;
  final String? logoUrl;
  final String? tvgName;
  final ChannelType type;

  Channel({
    required this.name,
    required this.url,
    this.group = 'Ungrouped',
    this.logoUrl,
    this.tvgName,
    this.type = ChannelType.unknown,
  });

  @override
  String toString() {
    return 'Channel(name: $name, type: $type, group: $group)';
  }
}
