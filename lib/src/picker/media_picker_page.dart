import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/media_type.dart';
import '../models/picked_media.dart';

/// Cross-platform media picker page.
///
/// - iOS / Android: album grid via `photo_manager`
/// - Other platforms: `file_picker` file dialog
class MediaPickerPage extends StatefulWidget {
  final MediaPickType type;
  final int maxCount;
  final String title;

  const MediaPickerPage({
    super.key,
    this.type = MediaPickType.both,
    this.maxCount = 1,
    this.title = 'Select media',
  });

  static Future<bool> requestPermission() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return true;
    final ps = await PhotoManager.requestPermissionExtend();
    return ps.isAuth || ps.isLimited;
  }

  @override
  State<MediaPickerPage> createState() => _MediaPickerPageState();
}

class _MediaPickerPageState extends State<MediaPickerPage> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = [];
  final Set<AssetEntity> _selected = {};
  final Map<String, Uint8List?> _thumbs = {};
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _hasMore = true;
  int _page = 0;
  String? _error;

  RequestType get _requestType {
    switch (widget.type) {
      case MediaPickType.image:
        return RequestType.image;
      case MediaPickType.video:
        return RequestType.video;
      case MediaPickType.both:
        return RequestType.common;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (Platform.isIOS || Platform.isAndroid) {
      _bootstrapAlbum();
    } else {
      _pickFilesDesktop();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120) {
      _loadAssets();
    }
  }

  Future<void> _bootstrapAlbum() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await MediaPickerPage.requestPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'Photo library permission denied';
      });
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: _requestType,
      onlyAll: false,
    );
    if (!mounted) return;
    if (albums.isEmpty) {
      setState(() {
        _loading = false;
        _albums = [];
      });
      return;
    }
    _albums = albums;
    _selectedAlbum = albums.first;
    await _loadAssets(refresh: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAssets({bool refresh = false}) async {
    final album = _selectedAlbum;
    if (album == null) return;
    if (refresh) {
      _page = 0;
      _hasMore = true;
      _assets = [];
    }
    if (!_hasMore) return;

    const pageSize = 60;
    final start = _page * pageSize;
    final batch = await album.getAssetListRange(
      start: start,
      end: start + pageSize,
    );
    if (!mounted) return;
    setState(() {
      _assets = refresh ? batch : [..._assets, ...batch];
      _hasMore = batch.length >= pageSize;
      _page++;
    });
    _preloadThumbs(batch.take(18));
  }

  Future<void> _preloadThumbs(Iterable<AssetEntity> items) async {
    for (final asset in items) {
      if (_thumbs.containsKey(asset.id)) continue;
      try {
        final bytes =
            await asset.thumbnailDataWithSize(const ThumbnailSize(240, 240));
        if (!mounted) return;
        setState(() => _thumbs[asset.id] = bytes);
      } catch (_) {
        _thumbs[asset.id] = null;
      }
    }
  }

  void _toggle(AssetEntity asset) {
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else if (_selected.length < widget.maxCount) {
        _selected.add(asset);
      }
    });
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      Navigator.pop(context, <PickedMedia>[]);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final out = <PickedMedia>[];
    for (final asset in _selected) {
      final file = await asset.file;
      if (file == null) continue;
      final kind = asset.type == AssetType.video
          ? MediaKind.video
          : MediaKind.image;
      out.add(
        PickedMedia(
          kind: kind,
          path: file.path,
          name: asset.title,
          size: await file.length(),
          width: asset.width,
          height: asset.height,
          duration: asset.type == AssetType.video ? asset.videoDuration : null,
          thumbnailBytes: _thumbs[asset.id],
          assetId: asset.id,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context); // loading
    Navigator.pop(context, out);
  }

  Future<void> _pickFilesDesktop() async {
    final allowed = <String>[];
    if (widget.type != MediaPickType.video) {
      allowed.addAll(['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic']);
    }
    if (widget.type != MediaPickType.image) {
      allowed.addAll(['mp4', 'mov', 'm4v']);
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: widget.maxCount > 1,
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context, <PickedMedia>[]);
      return;
    }
    final files = result.files.take(widget.maxCount);
    final out = <PickedMedia>[];
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final lower = path.toLowerCase();
      final isVideo = lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.m4v');
      out.add(
        PickedMedia(
          kind: isVideo ? MediaKind.video : MediaKind.image,
          path: path,
          name: f.name,
          size: f.size,
        ),
      );
    }
    Navigator.pop(context, out);
  }

  Future<void> _switchAlbum() async {
    if (_albums.isEmpty) return;
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: _albums.length,
        itemBuilder: (_, i) {
          final album = _albums[i];
          return ListTile(
            title: Text(album.name),
            selected: album.id == _selectedAlbum?.id,
            onTap: () => Navigator.pop(ctx, album),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedAlbum = picked;
      _selected.clear();
      _loading = true;
    });
    await _loadAssets(refresh: true);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isIOS || Platform.isAndroid)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _switchAlbum,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _selectedAlbum?.name ?? widget.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _confirm,
            child: Text(
              _selected.isEmpty ? 'Done' : 'Done(${_selected.length})',
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _assets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _bootstrapAlbum,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_assets.isEmpty) {
      return const Center(child: Text('No media found'));
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) => _AssetTile(
        asset: _assets[i],
        thumb: _thumbs[_assets[i].id],
        selectedIndex: _selected.contains(_assets[i])
            ? _selected.toList().indexOf(_assets[i]) + 1
            : null,
        onTap: () => _toggle(_assets[i]),
        onVisible: () {
          if (!_thumbs.containsKey(_assets[i].id)) {
            _preloadThumbs([_assets[i]]);
          }
        },
      ),
    );
  }
}

class _AssetTile extends StatefulWidget {
  final AssetEntity asset;
  final Uint8List? thumb;
  final int? selectedIndex;
  final VoidCallback onTap;
  final VoidCallback onVisible;

  const _AssetTile({
    required this.asset,
    required this.thumb,
    required this.selectedIndex,
    required this.onTap,
    required this.onVisible,
  });

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onVisible());
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.asset.type == AssetType.video;
    final selected = widget.selectedIndex != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.thumb != null)
            Image.memory(widget.thumb!, fit: BoxFit.cover)
          else
            Container(color: Colors.black12),
          if (isVideo)
            Positioned(
              left: 6,
              bottom: 6,
              child: Text(
                _formatDuration(widget.asset.videoDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black38,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? Text(
                      '${widget.selectedIndex}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }
}
