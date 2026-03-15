// lib/screens/Profile_page/gallery_picker_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:Ratedly/screens/Profile_page/media_edit_screen.dart';
import 'package:Ratedly/screens/Profile_page/add_post_screen.dart';

class GalleryPickerScreen extends StatefulWidget {
  final VoidCallback? onPostUploaded;

  const GalleryPickerScreen({Key? key, this.onPostUploaded}) : super(key: key);

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  List<AssetEntity> _assets = [];
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 60;

  // Preview of selected asset
  AssetEntity? _previewAsset;
  Uint8List? _previewBytes;
  bool _isLoadingPreview = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _requestAndLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreAssets();
    }
  }

  Future<void> _requestAndLoad() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    await _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
    );

    // Sort: "All" / "Recents" first
    albums.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      if (aName == 'recents' || aName == 'all') return -1;
      if (bName == 'recents' || bName == 'all') return 1;
      return aName.compareTo(bName);
    });

    if (mounted) {
      setState(() => _albums = albums);
      if (albums.isNotEmpty) {
        _selectedAlbum = albums.first;
        await _loadAssets();
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAssets() async {
    if (_selectedAlbum == null) return;
    setState(() {
      _isLoading = true;
      _assets = [];
      _page = 0;
      _hasMore = true;
      _previewAsset = null;
      _previewBytes = null;
    });

    final assets = await _selectedAlbum!.getAssetListPaged(
      page: 0,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _assets = assets;
        _page = 1;
        _hasMore = assets.length == _pageSize;
        _isLoading = false;
      });

      // Auto-preview first asset
      if (assets.isNotEmpty) _loadPreview(assets.first);
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_selectedAlbum == null || !_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    final more = await _selectedAlbum!.getAssetListPaged(
      page: _page,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _assets.addAll(more);
        _page++;
        _hasMore = more.length == _pageSize;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadPreview(AssetEntity asset) async {
    setState(() {
      _previewAsset = asset;
      _isLoadingPreview = true;
      _previewBytes = null;
    });

    if (asset.type == AssetType.video) {
      // For video just show thumbnail
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(600, 600),
        quality: 90,
      );
      if (mounted) {
        setState(() {
          _previewBytes = thumb;
          _isLoadingPreview = false;
        });
      }
    } else {
      final bytes = await asset.originBytes;
      if (mounted) {
        setState(() {
          _previewBytes = bytes;
          _isLoadingPreview = false;
        });
      }
    }
  }

  Future<void> _onConfirm() async {
    if (_previewAsset == null) return;

    if (_previewAsset!.type == AssetType.video) {
      final file = await _previewAsset!.originFile;
      if (file != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddPostScreen(
              initialVideoFile: file,
              onPostUploaded: widget.onPostUploaded,
            ),
          ),
        );
      }
    } else {
      final bytes = await _previewAsset!.originBytes;
      if (bytes != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaEditScreen(
              imageBytes: bytes,
              onPostUploaded: widget.onPostUploaded,
            ),
          ),
        );
      }
    }
  }

  Future<void> _onAlbumChanged(AssetPathEntity album) async {
    setState(() => _selectedAlbum = album);
    await _loadAssets();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SizedBox(height: topPadding),

          // ── Top bar ──────────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),

                  // Album picker dropdown
                  GestureDetector(
                    onTap: _showAlbumPicker,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedAlbum?.name ?? 'Gallery',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white, size: 20),
                      ],
                    ),
                  ),

                  // Next button
                  GestureDetector(
                    onTap: _previewAsset != null ? _onConfirm : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: _previewAsset != null
                            ? Colors.white
                            : Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Next',
                        style: TextStyle(
                          color: _previewAsset != null
                              ? Colors.black
                              : Colors.black54,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Large preview of selected asset ──────────────────────────────
          AspectRatio(
            aspectRatio: 1,
            child: _isLoadingPreview
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _previewBytes != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_previewBytes!, fit: BoxFit.cover),
                          if (_previewAsset?.type == AssetType.video)
                            const Center(
                              child: Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 48),
                            ),
                        ],
                      )
                    : Container(color: const Color(0xFF1C1C1E)),
          ),

          // ── Grid of all media ─────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _assets.isEmpty
                    ? Center(
                        child: Text(
                          'No media found',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 15),
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(top: 2),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: _assets.length + (_isLoadingMore ? 3 : 0),
                        itemBuilder: (ctx, i) {
                          if (i >= _assets.length) {
                            return Container(color: const Color(0xFF1C1C1E));
                          }
                          final asset = _assets[i];
                          final isSelected = _previewAsset?.id == asset.id;
                          return _AssetThumbnail(
                            asset: asset,
                            isSelected: isSelected,
                            onTap: () => _loadPreview(asset),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showAlbumPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _albums.length,
              itemBuilder: (ctx, i) {
                final album = _albums[i];
                final isSelected = _selectedAlbum?.id == album.id;
                return ListTile(
                  onTap: () {
                    Navigator.pop(ctx);
                    _onAlbumChanged(album);
                  },
                  title: Text(
                    album.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// =============================================================================
// ASSET THUMBNAIL
// =============================================================================

class _AssetThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final bool isSelected;
  final VoidCallback onTap;

  const _AssetThumbnail({
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final thumb = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
      quality: 80,
    );
    if (mounted) setState(() => _thumb = thumb);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          _thumb != null
              ? Image.memory(_thumb!, fit: BoxFit.cover)
              : Container(color: const Color(0xFF2C2C2E)),

          // Selected overlay
          if (widget.isSelected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),

          // Video indicators
          if (widget.asset.type == AssetType.video) ...[
            // Duration — bottom left
            Positioned(
              bottom: 4,
              left: 5,
              child: Text(
                _formatDuration(widget.asset.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 3,
                        color: Colors.black54),
                  ],
                ),
              ),
            ),
            // Play icon — top right
            const Positioned(
              top: 5,
              right: 5,
              child:
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
