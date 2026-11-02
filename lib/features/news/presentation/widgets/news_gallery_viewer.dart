import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/features/news/domain/news_post.dart';

/// Full-screen album for a post's images: swipe between them, pinch to zoom,
/// screen-protected (FLAG_SECURE / iOS capture guard) like every viewer in
/// the app. No save/share.
class NewsGalleryViewer extends StatefulWidget {
  const NewsGalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<NewsImage> images;
  final int initialIndex;

  static Future<void> open(
    BuildContext context,
    List<NewsImage> images,
    int index,
  ) => Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) =>
          NewsGalleryViewer(images: images, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<NewsGalleryViewer> createState() => _NewsGalleryViewerState();
}

class _NewsGalleryViewerState extends State<NewsGalleryViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// Swiping is off while an image is zoomed in (panning wins).
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    return SecureScreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: count,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (context, i) => _ZoomableImage(
                image: widget.images[i],
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (count > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: Text(
                          '${_index + 1} / $count',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.image, required this.onZoomChanged});

  final NewsImage image;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Double tap toggles 2.5× / fit.
      onDoubleTapDown: (d) {
        final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
        if (zoomed) {
          _controller.value = Matrix4.identity();
        } else {
          final p = d.localPosition;
          _controller.value = Matrix4.identity()
            ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1);
        }
      },
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.image.url,
            fit: BoxFit.contain,
            // The thumbnail is usually cached already: show it while the
            // full image loads.
            placeholder: (_, _) => CachedNetworkImage(
              imageUrl: widget.image.thumbUrl,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
            errorWidget: (_, _, _) => const Icon(
              Icons.broken_image_rounded,
              color: Colors.white38,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
