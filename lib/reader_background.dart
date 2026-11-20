import 'dart:io';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'personal_images.dart';
import 'reader_preferences.dart';
import 'reader_theme_presets.dart';

/// Kept behind the whole article. Scrolling, pagination and chrome ticks never
/// reopen the file or decode a screen capture. Only changing the image id does.
class ReaderBackground extends StatefulWidget {
  const ReaderBackground({
    super.key,
    required this.store,
    required this.preferences,
    required this.paper,
    required this.child,
    this.reduceMotion = false,
  });
  final ReaderBackgroundStore store;
  final ReaderPreferences preferences;
  final Color paper;
  final Widget child;
  final bool reduceMotion;
  @override
  State<ReaderBackground> createState() => _ReaderBackgroundState();
}

class _ReaderBackgroundState extends State<ReaderBackground> {
  Future<File?>? _file;
  Future<File?>? _themeFile;
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    _file = widget.store.file(widget.preferences.backgroundImage);
    final theme = widget.preferences.theme;
    _themeFile = theme == null
        ? null
        : widget.store.themeFile(theme.id).then<File?>((file) {
            if (file != null || theme.imageCandidates.isEmpty) return file;
            return widget.store.cacheThemeImage(
              theme.id,
              theme.imageCandidates,
            );
          });
  }

  @override
  void didUpdateWidget(ReaderBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.preferences.backgroundImage !=
            widget.preferences.backgroundImage ||
        oldWidget.preferences.theme?.id != widget.preferences.theme?.id ||
        oldWidget.preferences.theme?.imageUrl !=
            widget.preferences.theme?.imageUrl) {
      _resolve();
    }
  }

  double get _imageOpacity {
    final dark = widget.preferences.darkPaper(
      Theme.of(context).brightness == Brightness.dark,
    );
    return dark
        ? (1 - widget.preferences.backgroundOpacity).clamp(.55, 1.0)
        : 1 - widget.preferences.backgroundOpacity;
  }

  Widget _imageFile(File file) => Image.file(
    file,
    key: ValueKey(file.path),
    width: double.infinity,
    height: double.infinity,
    fit: widget.preferences.backgroundFit,
    color: widget.paper.withValues(alpha: _imageOpacity),
    colorBlendMode: BlendMode.srcOver,
    filterQuality: FilterQuality.low,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );

  Widget _themeImage(ReaderThemeSelection theme) {
    final urls = theme.imageCandidates;
    if (urls.isEmpty) return const SizedBox.expand();
    Widget image(int index) {
      if (index >= urls.length) return const SizedBox.expand();
      final url = urls[index];
      return Image.network(
        url,
        key: ValueKey(url),
        width: double.infinity,
        height: double.infinity,
        fit: widget.preferences.backgroundFit,
        color: widget.paper.withValues(alpha: _imageOpacity),
        colorBlendMode: BlendMode.srcOver,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => image(index + 1),
      );
    }

    return image(0);
  }

  Widget _background() {
    // 主题自带背景图优先于手动背景，避免选择主题后仍显示旧的自定义图片。
    final theme = widget.preferences.theme;
    if (theme != null && theme.imageCandidates.isNotEmpty) {
      return FutureBuilder<File?>(
        future: _themeFile,
        initialData: widget.store.resolvedThemeFile(theme.id),
        builder: (context, snapshot) => AnimatedSwitcher(
          duration: widget.reduceMotion ? Duration.zero : NovelMotion.enter,
          switchInCurve: NovelMotion.ease,
          switchOutCurve: NovelMotion.retract,
          child: snapshot.data == null
              ? _themeImage(theme)
              : _imageFile(snapshot.data!),
        ),
      );
    }
    final image = widget.preferences.backgroundImage;
    if (image != null) {
      return FutureBuilder<File?>(
        future: _file,
        initialData: widget.store.resolvedFile(image),
        builder: (context, snapshot) => AnimatedSwitcher(
          duration: widget.reduceMotion ? Duration.zero : NovelMotion.enter,
          switchInCurve: NovelMotion.ease,
          switchOutCurve: NovelMotion.retract,
          child: snapshot.data == null
              ? const SizedBox.expand()
              : _imageFile(snapshot.data!),
        ),
      );
    }
    return FutureBuilder<File?>(
      future: _file,
      initialData: widget.store.resolvedFile(null),
      builder: (context, snapshot) => AnimatedSwitcher(
        duration: widget.reduceMotion ? Duration.zero : NovelMotion.enter,
        switchInCurve: NovelMotion.ease,
        switchOutCurve: NovelMotion.retract,
        child: snapshot.data == null
            ? const SizedBox.expand()
            : _imageFile(snapshot.data!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.paper,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                key: const ValueKey('reader-background-layer'),
                child: _background(),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    ),
  );
}
