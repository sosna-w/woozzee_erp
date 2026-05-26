import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/image_data.dart';
import '../utils/photo_cache_manager.dart';

class ProductSlide extends StatefulWidget {
  final Map<String, dynamic> product;
  final int productIndex;
  final int totalProducts;
  final List<ImageData> images;
  final bool isPreloadingThis;
  final String animationSpeed;
  final double filmSpeed;
  final bool isAnimationPaused;
  final String backgroundMode;
  final VoidCallback onClearCache;

  const ProductSlide({
    super.key,
    required this.product,
    required this.productIndex,
    required this.totalProducts,
    required this.images,
    required this.isPreloadingThis,
    required this.animationSpeed,
    required this.filmSpeed,
    required this.isAnimationPaused,
    required this.backgroundMode,
    required this.onClearCache,
  });

  @override
  State<ProductSlide> createState() => _ProductSlideState();
}

class _ProductSlideState extends State<ProductSlide> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _filmAnimationController;
  final ScrollController _scrollController = ScrollController();

  late double _imageWidth;
  late double _totalFilmWidth;

  final Map<int, File> _cachedFiles = {};
  final PhotoCacheManager _photoCache = PhotoCacheManager();
  bool _isFilesLoaded = false;
  bool _isInitialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _filmAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeDimensions();
      _loadCachedFiles().then((_) {
        if (mounted && widget.images.isNotEmpty) _startFilmAnimation();
      });
      _isInitialized = true;
    }
  }

  void _initializeDimensions() {
    final screenHeight = MediaQuery.of(context).size.height;
    _imageWidth = screenHeight * (900 / 1200);
    if (widget.images.isNotEmpty) {
      _totalFilmWidth = _imageWidth * widget.images.length * 2;
    }
  }

  @override
  void didUpdateWidget(ProductSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      final screenHeight = MediaQuery.of(context).size.height;
      _imageWidth = screenHeight * (900 / 1200);
      _totalFilmWidth = widget.images.isNotEmpty ? _imageWidth * widget.images.length * 2 : 0;
      _loadCachedFiles().then((_) {
        if (mounted && widget.images.isNotEmpty) _startFilmAnimation();
      });
    }
    if (oldWidget.filmSpeed != widget.filmSpeed || oldWidget.isAnimationPaused != widget.isAnimationPaused) {
      _filmAnimationController.stop();
      if (!widget.isAnimationPaused && widget.filmSpeed > 0 && widget.images.isNotEmpty) {
        _startFilmAnimation();
      }
    }
  }

  @override
  void dispose() {
    _filmAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedFiles() async {
    if (widget.images.isEmpty) {
      _isFilesLoaded = true;
      return;
    }
    try {
      final nmId = widget.images[0].nmId;
      for (int i = 0; i < widget.images.length; i++) {
        final cachedFile = await _photoCache.getPhotoFile(nmId, i);
        if (cachedFile != null && await cachedFile.exists()) {
          _cachedFiles[i] = cachedFile;
        }
      }
    } catch (e) {
      // ignore
    } finally {
      _isFilesLoaded = true;
      if (mounted) setState(() {});
    }
  }

  void _startFilmAnimation() {
    if (!mounted || widget.images.isEmpty || widget.filmSpeed <= 0) return;
    final totalWidth = _totalFilmWidth;
    if (totalWidth <= 0) return;

    final durationInSeconds = totalWidth / widget.filmSpeed;
    final duration = Duration(milliseconds: (durationInSeconds * 1000).round());
    _filmAnimationController.duration = duration;

    final animation = Tween<double>(begin: 0, end: totalWidth).animate(
      CurvedAnimation(parent: _filmAnimationController, curve: Curves.linear),
    );
    animation.removeListener(_animationListener);
    animation.addListener(_animationListener);
    _filmAnimationController.repeat();
  }

  void _animationListener() {
    if (mounted) {
      _scrollController.jumpTo(_filmAnimationController.value * _totalFilmWidth);
    }
  }

  Widget _buildFilmStrip() {
    if (widget.images.isEmpty) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(child: Text('Нет фотографий', style: TextStyle(color: Colors.white))),
      );
    }
    final screenHeight = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenHeight,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.images.length * 2,
        itemBuilder: (context, index) {
          final imageIndex = index % widget.images.length;
          final imageData = widget.images[imageIndex];
          return SizedBox(
            width: _imageWidth,
            height: screenHeight,
            child: _buildImageWidget(imageData, isDuplicate: index >= widget.images.length),
          );
        },
      ),
    );
  }

  Widget _buildImageWidget(ImageData imageData, {bool isDuplicate = false}) {
    final cachedFile = _cachedFiles[imageData.imageIndex];
    if (cachedFile != null) {
      return SizedBox(
        width: _imageWidth,
        height: imageData.height,
        child: Image.file(
          cachedFile,
          fit: BoxFit.fitHeight,
          key: isDuplicate ? ValueKey('${imageData.key}_dup') : imageData.key,
        ),
      );
    }
    return SizedBox(
      width: _imageWidth,
      height: imageData.height,
      child: Image.network(
        imageData.imageUrl,
        fit: BoxFit.fitHeight,
        key: isDuplicate ? ValueKey('${imageData.key}_dup') : imageData.key,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade900,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey.shade900,
          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 60)),
        ),
      ),
    );
  }

  Widget _buildBackgroundEffects() {
    switch (widget.backgroundMode) {
      case 'легкое размытие':
        return BackdropFilter(filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2), child: Container(color: Colors.transparent));
      case 'размытие':
        return BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: Container(color: Colors.transparent));
      case 'сильное размытие':
        return BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent));
      case 'легкое затемнение':
        return Container(color: Colors.black.withOpacity(0.2));
      case 'затемнение':
        return Container(color: Colors.black.withOpacity(0.5));
      case 'сильное затемнение':
        return Container(color: Colors.black.withOpacity(0.8));
      case 'размытие + затемнение':
        return Stack(children: [
          BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.transparent)),
          Container(color: Colors.black.withOpacity(0.8)),
        ]);
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.isPreloadingThis || !_isFilesLoaded) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 20),
              Text('Загрузка изображений...', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (widget.images.isNotEmpty) _buildFilmStrip(),
          if (widget.backgroundMode != 'обычный' && widget.images.isNotEmpty) _buildBackgroundEffects(),
          if (widget.backgroundMode == 'обычный')
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}