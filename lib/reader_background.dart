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
    required this.night,
    this.preview = false,
    required this.child,
    this.reduceMotion = false,
  });
  final ReaderBackgroundStore store;
  final ReaderPreferences preferences;
  final Color paper;
  final Widget child;
  final bool reduceMotion;
  final bool night, preview;
  ReaderLook get look => preferences.lookFor(night);
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
    _file = widget.store.file(widget.look.backgroundImage);
    final theme = widget.look.theme;
    final store = widget.store;
    final preview = widget.preview;
    final texture = theme?.textureFor(widget.night);
    _themeFile =
        theme == null || texture != null || theme.imageCandidates.isEmpty
        ? null
        : store.themeFile(theme.id).then<File?>((file) {
            if (file != null || preview) return file;
            return store.cacheThemeImage(theme.id, theme.imageCandidates);
          });
  }

  @override
  void didUpdateWidget(ReaderBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.look.backgroundImage != widget.look.backgroundImage ||
        oldWidget.look.theme != widget.look.theme ||
        oldWidget.preview != widget.preview) {
      _resolve();
    }
  }

  double get _imageOpacity {
    final dark =
        ThemeData.estimateBrightnessForColor(widget.paper) == Brightness.dark;
    return dark
        ? (1 - widget.preferences.backgroundOpacity).clamp(.55, 1.0)
        : 1 - widget.preferences.backgroundOpacity;
  }

  Widget _imageFile(File file) => Image.file(
    file,
    key: ValueKey(file.path),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
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
        fit: BoxFit.cover,
        color: widget.paper.withValues(alpha: _imageOpacity),
        colorBlendMode: BlendMode.srcOver,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => image(index + 1),
      );
    }

    return image(0);
  }

  /// 内置纸纹已带完整日/夜色调，仅叠一层很淡的纸色让主题色更统一。
  Widget _textureImage(String asset) => Image.asset(
    asset,
    key: ValueKey(asset),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    color: widget.paper.withValues(alpha: .14),
    colorBlendMode: BlendMode.srcOver,
    filterQuality: FilterQuality.low,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const SizedBox.expand(),
  );

  Widget _background() {
    final texture = widget.look.theme?.textureFor(widget.night);
    if (texture != null) {
      return AnimatedSwitcher(
        duration: widget.reduceMotion ? Duration.zero : NovelMotion.enter,
        switchInCurve: NovelMotion.ease,
        switchOutCurve: NovelMotion.retract,
        child: _textureImage(texture),
      );
    }
    // 主题自带背景图优先于手动背景，避免选择主题后仍显示旧的自定义图片。
    final theme = widget.look.theme;
    if (theme != null && theme.imageCandidates.isNotEmpty) {
      return FutureBuilder<File?>(
        key: ValueKey(theme.imageUrl),
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
    final image = widget.look.backgroundImage;
    if (image != null) {
      return FutureBuilder<File?>(
        key: ValueKey(image),
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
