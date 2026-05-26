import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/photo_cache_manager.dart';

class ImagePreviewCell extends StatefulWidget {
  final String? imageUrl;
  final double width;

  const ImagePreviewCell({
    Key? key,
    this.imageUrl,
    this.width = 50,
  }) : super(key: key);

  @override
  State<ImagePreviewCell> createState() => _ImagePreviewCellState();
}

class _ImagePreviewCellState extends State<ImagePreviewCell> {
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;
  final PhotoCacheManager _cacheManager = PhotoCacheManager();

  @override
  void initState() {
    super.initState();
    _cacheManager.initialize();
  }

  void _showPreview(Offset globalPosition) {
    if (_overlayEntry != null) return;
    _hideTimer?.cancel();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: globalPosition.dx + 20,
        top: globalPosition.dy - 150,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.imageUrl != null
                  ? Image.network(
                widget.imageUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                ),
              )
                  : const Center(child: Icon(Icons.image_not_supported, size: 48)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hidePreview() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (event) {
        _cancelHide();
        _showPreview(event.position);
      },
      onExit: (_) => _hidePreview(),
      child: Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        width: widget.width,
        height: 50,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox.shrink();
        },
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}