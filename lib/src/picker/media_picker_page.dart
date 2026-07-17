import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:hero_media_viewer/hero_media_viewer.dart';
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
  bool _albumMenuOpen = false;
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
        final bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(240, 240),
        );
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

  /// 图片与视频都使用同一套 Hero overlay；选择状态只由缩略图右上角控制。
  Future<void> _previewAsset(AssetEntity asset, Rect startRect) async {
    final file = await asset.file;
    if (file == null || !mounted) return;
    final thumbnailBytes =
        _thumbs[asset.id] ??
        await asset.thumbnailDataWithSize(const ThumbnailSize(512, 512));
    if (!mounted) return;

    final thumbnail =
        thumbnailBytes == null ? null : MemoryImage(thumbnailBytes);
    final aspectRatio =
        asset.width > 0 && asset.height > 0 ? asset.width / asset.height : null;
    final item =
        asset.type == AssetType.video
            ? MediaItem.video(
              id: asset.id,
              videoPath: file.path,
              thumbnail: thumbnail,
              aspectRatio: aspectRatio,
            )
            : MediaItem.image(
              id: asset.id,
              imageProvider: FileImage(file),
              thumbnail: thumbnail,
              aspectRatio: aspectRatio,
            );
    showMediaHeroOverlay(
      context: context,
      items: [item],
      initialIndex: 0,
      startRect: startRect,
      showCloseButton: true,
      videoBuilder: (ctx, videoSource, thumb, index, isFocus) {
        if (!isFocus) {
          return thumb != null
              ? Center(child: Image(image: thumb, fit: BoxFit.contain))
              : const ColoredBox(color: Colors.black);
        }
        return _HeroVideoPreview(videoSource: videoSource, thumbnail: thumb);
      },
    );
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
      final kind =
          asset.type == AssetType.video ? MediaKind.video : MediaKind.image;
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
      final isVideo =
          lower.endsWith('.mp4') ||
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

  void _toggleAlbumMenu() {
    if (_albums.isEmpty) return;
    setState(() => _albumMenuOpen = !_albumMenuOpen);
  }

  Future<void> _selectAlbum(AssetPathEntity picked) async {
    if (picked.id == _selectedAlbum?.id) {
      setState(() => _albumMenuOpen = false);
      return;
    }
    setState(() {
      _albumMenuOpen = false;
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _toggleAlbumMenu,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _selectedAlbum?.name ?? widget.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedRotation(
                turns: _albumMenuOpen ? 0.5 : 0,
                // 与窗帘弹簧呼应：箭头带一点回摆而不是平直停住。
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                child: const Icon(Icons.arrow_drop_down),
              ),
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
      body: Stack(
        children: [
          _buildBody(),
          if (_albums.isNotEmpty)
            _AlbumDropdownOverlay(
              visible: _albumMenuOpen,
              albums: _albums,
              selectedAlbumId: _selectedAlbum?.id,
              onDismiss: () => setState(() => _albumMenuOpen = false),
              onSelect: _selectAlbum,
            ),
        ],
      ),
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
      itemBuilder:
          (_, i) => _AssetTile(
            asset: _assets[i],
            thumb: _thumbs[_assets[i].id],
            selectedIndex:
                _selected.contains(_assets[i])
                    ? _selected.toList().indexOf(_assets[i]) + 1
                    : null,
            onToggle: () => _toggle(_assets[i]),
            onPreview: (startRect) => _previewAsset(_assets[i], startRect),
            onVisible: () {
              if (!_thumbs.containsKey(_assets[i].id)) {
                _preloadThumbs([_assets[i]]);
              }
            },
          ),
    );
  }
}

/// 窗帘式相册下拉：面板高度由弹簧拉开（带轻微过冲回弹），条目随揭示按
/// 牌堆顺序错峰滑入，各自跟随同一条弹簧完成回弹；收起走独立的临界阻尼
/// 弹簧快速合拢，条目保持落位不重播入场动画。
class _AlbumDropdownOverlay extends StatefulWidget {
  const _AlbumDropdownOverlay({
    required this.visible,
    required this.albums,
    required this.selectedAlbumId,
    required this.onDismiss,
    required this.onSelect,
  });

  final bool visible;
  final List<AssetPathEntity> albums;
  final String? selectedAlbumId;
  final VoidCallback onDismiss;
  final ValueChanged<AssetPathEntity> onSelect;

  @override
  State<_AlbumDropdownOverlay> createState() => _AlbumDropdownOverlayState();
}

class _AlbumDropdownOverlayState extends State<_AlbumDropdownOverlay>
    with SingleTickerProviderStateMixin {
  // 展开欠阻尼带过冲；收起临界阻尼快速合拢，不做反向表演。
  static final _openSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 290,
    ratio: 0.72,
  );
  static final _closeSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 480,
    ratio: 1,
  );
  static const _itemHeight = 56.0;
  static const _itemSlideIn = 14.0;

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  double _target = 0;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      _animateTo(1);
    }
  }

  @override
  void didUpdateWidget(covariant _AlbumDropdownOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _animateTo(widget.visible ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 弹簧从当前值续接目标，快速连点标题时动画自然掉头而不是重启。
  void _animateTo(double target) {
    _target = target;
    _controller.animateWith(
      SpringSimulation(
        target == 1 ? _openSpring : _closeSpring,
        _controller.value,
        target,
        0,
      ),
    );
  }

  /// 条目按行错峰跟随主弹簧；越靠后的条目对过冲的放大越明显，形成级联
  /// 回弹。收起时全部视为已落位，只由窗帘合拢带走。
  double _itemProgress(int index) {
    if (_target == 0) return 1;
    final start = (index * 0.07).clamp(0.0, 0.45);
    return math.max(0.0, (_controller.value - start) / (1 - start));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Semantics(
          hidden: !widget.visible,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value = _controller.value;
              final settled = value.clamp(0.0, 1.0).toDouble();
              if (!widget.visible && value <= 0.001) {
                return const SizedBox.shrink();
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final desiredHeight = widget.albums.length * _itemHeight;
                  final maxHeight = (constraints.maxHeight * 0.52).clamp(
                    _itemHeight,
                    360.0,
                  );
                  final menuHeight = desiredHeight.clamp(
                    _itemHeight,
                    maxHeight,
                  );

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onDismiss,
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: 0.42 * settled,
                            ),
                          ),
                        ),
                      ),
                      Material(
                        color: theme.colorScheme.surface,
                        elevation: 6 * settled,
                        shadowColor: Colors.black26,
                        child: SizedBox(
                          // 高度直接吃弹簧值：过冲段底缘越过终点再弹回，
                          // 形成"拉开窗帘"的余量感。
                          height: menuHeight * math.max(0.0, value),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: widget.albums.length,
                            separatorBuilder:
                                (_, _) => Divider(
                                  height: 1,
                                  indent: 16,
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.36,
                                  ),
                                ),
                            itemBuilder: (_, i) {
                              final album = widget.albums[i];
                              final selected =
                                  album.id == widget.selectedAlbumId;
                              final progress = _itemProgress(i);
                              return Opacity(
                                opacity:
                                    (progress * 1.8).clamp(0.0, 1.0).toDouble(),
                                child: Transform.translate(
                                  offset: Offset(
                                    0,
                                    -_itemSlideIn * (1 - progress),
                                  ),
                                  child: SizedBox(
                                    height: _itemHeight,
                                    child: ListTile(
                                      title: Text(
                                        album.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              selected
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      selected: selected,
                                      selectedTileColor: Colors.transparent,
                                      onTap: () => widget.onSelect(album),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AssetTile extends StatefulWidget {
  final AssetEntity asset;
  final Uint8List? thumb;
  final int? selectedIndex;
  final VoidCallback onToggle;
  final ValueChanged<Rect> onPreview;
  final VoidCallback onVisible;

  const _AssetTile({
    required this.asset,
    required this.thumb,
    required this.selectedIndex,
    required this.onToggle,
    required this.onPreview,
    required this.onVisible,
  });

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  final _thumbnailKey = GlobalKey();

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
      key: _thumbnailKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final box =
            _thumbnailKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        widget.onPreview(box.localToGlobal(Offset.zero) & box.size);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.thumb != null)
            Image.memory(widget.thumb!, fit: BoxFit.cover)
          else
            Container(color: Colors.black12),
          if (isVideo) const Center(child: _VideoPlayIndicator(size: 34)),
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
            right: 4,
            top: 4,
            child: Semantics(
              button: true,
              selected: selected,
              label: selected ? 'Deselect media' : 'Select media',
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  onTap: widget.onToggle,
                  radius: 20,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black38,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child:
                        selected
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
              ),
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

class _VideoPlayIndicator extends StatelessWidget {
  const _VideoPlayIndicator({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: size * 0.12,
              offset: Offset(0, size * 0.04),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(left: size * 0.045),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: size * 0.54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroVideoPreview extends StatefulWidget {
  const _HeroVideoPreview({required this.videoSource, this.thumbnail});

  final String videoSource;
  final ImageProvider? thumbnail;

  @override
  State<_HeroVideoPreview> createState() => _HeroVideoPreviewState();
}

class _HeroVideoPreviewState extends State<_HeroVideoPreview> {
  var _playerRequested = false;

  @override
  Widget build(BuildContext context) {
    if (_playerRequested) {
      return HeroVideoPlayer(
        videoSource: widget.videoSource,
        thumbnail: widget.thumbnail,
      );
    }
    return _VideoPoster(
      image: widget.thumbnail,
      onPlay: () => setState(() => _playerRequested = true),
    );
  }
}

class _VideoPoster extends StatelessWidget {
  const _VideoPoster({required this.image, required this.onPlay});

  final ImageProvider? image;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '播放视频',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            if (image != null) Image(image: image!, fit: BoxFit.contain),
            // 预览画布必须透明：Hero 拖动时只显示视频封面，不额外产生一块
            // 黑色的全屏视频底板。
            const Center(child: _VideoPlayIndicator(size: 44)),
          ],
        ),
      ),
    );
  }
}
