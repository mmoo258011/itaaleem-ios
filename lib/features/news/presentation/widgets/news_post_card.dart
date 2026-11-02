import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/arabic_time.dart';
import 'package:itaaleem/core/widgets/linkified_text.dart';
import 'package:itaaleem/features/app_config/in_app_web_screen.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/player_selection_sheet.dart';
import 'package:itaaleem/features/news/domain/news_post.dart';
import 'package:itaaleem/features/news/presentation/widgets/news_gallery_viewer.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_video_screen.dart';

/// One channel post as a bubble: images, text, link card, video, then the
/// time/views line and the reactions row under it.
class NewsPostCard extends StatelessWidget {
  const NewsPostCard({
    super.key,
    required this.post,
    required this.reactionsAvailable,
    required this.onReact,
    this.highlighted = false,
  });

  final NewsPost post;
  final List<String> reactionsAvailable;
  final ValueChanged<String> onReact;

  /// Briefly tinted when opened from a push for this post.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasMedia = post.images.isNotEmpty || post.video != null;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            color: highlighted
                ? scheme.primaryContainer
                : scheme.surfaceContainerLowest,
            borderRadius: radius,
            border: Border.all(
              color: post.isPinned
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (post.images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: _ImageAlbum(images: post.images),
                ),
              if (post.video != null)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: _VideoThumb(video: post.video!, title: post.body),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  hasMedia ? AppSpacing.sm : AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (post.body.trim().isNotEmpty)
                      LinkifiedText(
                        post.body.trim(),
                        style: text.bodyLarge?.copyWith(
                          height: 1.6,
                          color: scheme.onSurface,
                        ),
                        onLink: (url) => openConfigLink(context, url),
                      ),
                    if (post.link != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _LinkPreview(link: post.link!),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    _MetaLine(post: post),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (reactionsAvailable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _ReactionsRow(
              available: reactionsAvailable,
              counts: post.reactions,
              mine: post.myReaction,
              onReact: onReact,
            ),
          ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.post});

  final NewsPost post;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 11.5,
    );
    final at = post.publishedAt;
    return Row(
      children: [
        if (post.isPinned) ...[
          Icon(Icons.push_pin_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 2),
          Text('مثبّت', style: style?.copyWith(color: scheme.primary)),
          const SizedBox(width: AppSpacing.sm),
        ],
        const Spacer(),
        Semantics(
          label: '${post.viewsCount} مشاهدة',
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text(compactCount(post.viewsCount), style: style),
            ],
          ),
        ),
        if (at != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(arabicRelativeTime(at), style: style),
        ],
      ],
    );
  }
}

/// 1 image: as is (ratio clamped); 2: side by side; 3: one tall + two;
/// 4+: 2×2 with «+N» on the last tile. Space is reserved from
/// width/height before anything loads.
class _ImageAlbum extends StatelessWidget {
  const _ImageAlbum({required this.images});

  final List<NewsImage> images;

  @override
  Widget build(BuildContext context) {
    const gap = 3.0;
    Widget tile(int i, {String? overlay}) => _Thumb(
      image: images[i],
      overlay: overlay,
      onTap: () => NewsGalleryViewer.open(context, images, i),
    );

    final radius = BorderRadius.circular(AppRadius.md);
    final Widget album;
    switch (images.length) {
      case 1:
        album = AspectRatio(
          aspectRatio: images.first.aspectRatio.clamp(0.75, 1.9),
          child: tile(0),
        );
      case 2:
        album = AspectRatio(
          aspectRatio: 2,
          child: Row(
            children: [
              Expanded(child: tile(0)),
              const SizedBox(width: gap),
              Expanded(child: tile(1)),
            ],
          ),
        );
      case 3:
        album = AspectRatio(
          aspectRatio: 1.5,
          child: Row(
            children: [
              Expanded(flex: 2, child: tile(0)),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: tile(1)),
                    const SizedBox(height: gap),
                    Expanded(child: tile(2)),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        final more = images.length - 4;
        album = AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: tile(0)),
                    const SizedBox(width: gap),
                    Expanded(child: tile(1)),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: tile(2)),
                    const SizedBox(width: gap),
                    Expanded(
                      child: tile(3, overlay: more > 0 ? '+$more' : null),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
    return ClipRRect(borderRadius: radius, child: album);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.onTap, this.overlay});

  final NewsImage image;
  final VoidCallback onTap;
  final String? overlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: overlay == null
          ? 'عرض الصورة'
          : 'عرض الصورة، و${overlay!.substring(1)} صور كمان',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: image.thumbUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (_, _) =>
                  ColoredBox(color: scheme.surfaceContainerHigh),
              errorWidget: (_, _, _) => ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (overlay != null)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Text(
                    overlay!,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoThumb extends StatelessWidget {
  const _VideoThumb({required this.video, required this.title});

  final NewsVideo video;
  final String title;

  Future<void> _play(BuildContext context) async {
    final kind = await pickYoutubePlayer(context);
    if (kind == null || !context.mounted) return;
    final firstLine = title.trim().split('\n').first;
    context.push<void>(
      lessonVideoPath,
      extra: LessonVideoArgs(
        title: firstLine.isEmpty ? 'فيديو' : firstLine,
        videoUrl: video.url,
        playerKind: kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'تشغيل الفيديو',
      child: GestureDetector(
        onTap: () => _play(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: video.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      ColoredBox(color: scheme.surfaceContainerHigh),
                  errorWidget: (_, _, _) =>
                      ColoredBox(color: scheme.surfaceContainerHigh),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black38],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 12),
                      ],
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: scheme.onPrimary,
                      size: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkPreview extends StatelessWidget {
  const _LinkPreview({required this.link});

  final NewsLink link;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final host = Uri.tryParse(link.url)?.host.replaceFirst('www.', '') ?? '';
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => openConfigLink(context, link.url, title: link.title),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.link_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title ?? link.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: link.title == null
                          ? TextDirection.ltr
                          : null,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (host.isNotEmpty)
                      Text(
                        host,
                        textDirection: TextDirection.ltr,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({
    required this.available,
    required this.counts,
    required this.mine,
    required this.onReact,
  });

  final List<String> available;
  final Map<String, int> counts;
  final String? mine;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final emoji in available)
          _ReactionChip(
            emoji: emoji,
            count: counts[emoji] ?? 0,
            selected: emoji == mine,
            scheme: scheme,
            onTap: () => onReact(emoji),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.scheme,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.full);
    return Semantics(
      button: true,
      selected: selected,
      label: '$emoji ${count > 0 ? count : ''}',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.15 : 1,
                    duration: const Duration(milliseconds: 160),
                    child: Text(emoji, style: const TextStyle(fontSize: 16)),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      compactCount(count),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
