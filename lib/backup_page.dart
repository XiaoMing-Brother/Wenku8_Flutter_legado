import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'feature_pages.dart';
import 'library_backup.dart';
import 'library_state.dart';
import 'local_platform.dart';

class LibraryBackupPage extends StatefulWidget {
  const LibraryBackupPage({super.key, required this.state});
  final LibraryState state;
  @override
  State<LibraryBackupPage> createState() => _LibraryBackupPageState();
}

class _LibraryBackupPageState extends State<LibraryBackupPage> {
  String? _busy;
  String? _error;
  LibraryBackup? _preview;
  bool _preferences = false;

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() {
      _busy = label;
      _error = null;
    });
    // Present the progress state before serializing/merging an explicit backup.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await action();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '操作未完成，请检查文件或本地存储后重试');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _export({bool clipboard = false}) => _run('正在生成备份…', () async {
    final text = await (await widget.state.createBackup()).encode();
    if (clipboard) {
      if (text.length > 256 * 1024) throw const FormatException('备份较大，请使用文件导出');
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showNovelFeedback(context, '备份已复制');
    } else {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await LocalPlatform.exportBackup(
        text,
        'wenku8-backup-$date.json',
      );
      if (mounted && saved) showNovelFeedback(context, '备份文件已保存');
    }
  });

  Future<void> _import({bool clipboard = false}) => _run('正在读取备份…', () async {
    final text = clipboard
        ? (await Clipboard.getData(Clipboard.kTextPlain))?.text
        : await LocalPlatform.importBackup();
    if (text == null) {
      if (clipboard) throw const FormatException('剪贴板中没有备份文本');
      return; // System picker cancellation is not an error.
    }
    final backup = await LibraryBackup.parse(text);
    if (mounted) {
      setState(() {
        _preview = backup;
        _preferences = false;
      });
    }
  });

  Future<void> _restore() => _run('正在合并本地记录…', () async {
    final backup = _preview;
    if (backup == null) return;
    await widget.state.restoreBackup(backup, importPreferences: _preferences);
    if (mounted) {
      setState(() => _preview = null);
      showNovelFeedback(context, '备份已合并，较新的阅读进度已保留');
    }
  });

  Future<void> _openPageActions(BuildContext anchor) async {
    if (_busy != null) return;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (LocalPlatform.fileActions) ...[
            GlassMenuItem(
              key: const ValueKey('backup-export-file'),
              label: '导出备份文件',
              icon: CupertinoIcons.arrow_up_doc,
              onPressed: () => Navigator.pop(menu, 'exportFile'),
            ),
            GlassMenuItem(
              key: const ValueKey('backup-import-file'),
              label: '选择备份文件',
              icon: CupertinoIcons.arrow_down_doc,
              order: 1,
              onPressed: () => Navigator.pop(menu, 'importFile'),
            ),
          ],
          GlassMenuItem(
            key: const ValueKey('backup-copy'),
            label: '复制备份文本',
            icon: CupertinoIcons.doc_on_clipboard,
            order: 2,
            onPressed: () => Navigator.pop(menu, 'copy'),
          ),
          GlassMenuItem(
            key: const ValueKey('backup-paste'),
            label: '从剪贴板读取备份',
            icon: CupertinoIcons.doc_text,
            order: 3,
            onPressed: () => Navigator.pop(menu, 'paste'),
          ),
        ],
      ),
    );
    if (!anchor.mounted || !mounted || action == null) return;
    switch (action) {
      case 'exportFile':
        await _export();
        break;
      case 'importFile':
        await _import();
        break;
      case 'copy':
        await _export(clipboard: true);
        break;
      case 'paste':
        await _import(clipboard: true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _busy == null,
    child: ArchiveFeaturePage(
      title: '备份与恢复',
      code: 'SYSTEM / DATA TRANSFER',
      canPop: _busy == null,
      actions: [
        GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => GlassIconButton(
              key: const ValueKey('backup-actions'),
              icon: CupertinoIcons.ellipsis,
              label: '备份操作',
              onPressed: _busy == null ? () => _openPageActions(anchor) : null,
            ),
          ),
        ),
      ],
      child: LoadedContentSequence(
        generation: _preview,
        child: ListView(
          key: const ValueKey('backup-scroll'),
          padding: featurePadding(context),
          children: [
            const ArchiveSection(title: '带走你的阅读记录', code: 'SYSTEM / BACKUP'),
            const SizedBox(height: 12),
            const AppText('备份书架、阅读进度、书签、阅读历史、最近搜索和偏好。离线正文不包含在备份中。'),
            const SizedBox(height: 24),
            ContentPanel(
              child: const AppText(
                '从右上角菜单导出备份文件、选择备份文件、复制备份文本或从剪贴板读取备份。',
                style: TextStyle(height: 1.6),
              ),
            ),
            if (_busy != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  children: [
                    Expanded(child: AppText(_busy!)),
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 120,
                      height: 64,
                      child: LoadingSkeleton(layout: SkeletonLayout.actions),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Semantics(
                  liveRegion: true,
                  child: AppText(
                    _error!,
                    key: const ValueKey('backup-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (_preview case final backup?) ...[
              const SizedBox(height: 24),
              LoadedContentItem(
                index: 0,
                child: sectionHeader(
                  context,
                  '恢复预览',
                  '',
                  code: 'SYSTEM / RESTORE PREVIEW',
                ),
              ),
              const SizedBox(height: 14),
              LoadedContentItem(
                index: 1,
                child: ContentPanel(
                  key: const ValueKey('backup-preview'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText('备份时间 ${_date(backup.createdAt)}'),
                      const SizedBox(height: 12),
                      AppText(
                        '${backup.shelfCount} 本书架收藏 · ${backup.positionCount} 条阅读进度\n${backup.bookmarkCount} 个书签 · ${backup.historyCount} 本阅读记录',
                      ),
                      const SizedBox(height: 14),
                      const AppText('恢复将合并到本机，不清空已有书架和书签；同一本书保留更新时间较新的进度。'),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Expanded(child: AppText('同时恢复外观与阅读偏好')),
                          AppControls.toggle(
                            context,
                            key: const ValueKey('backup-import-preferences'),
                            value: _preferences,
                            onChanged: _busy == null
                                ? (value) =>
                                      setState(() => _preferences = value)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GlassTextButton(
                        key: const ValueKey('backup-confirm'),
                        onPressed: _busy == null ? _restore : null,
                        child: const AppText('确认合并恢复'),
                      ),
                      GlassTextButton(
                        onPressed: _busy == null
                            ? () => setState(() => _preview = null)
                            : null,
                        child: const AppText('取消恢复'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  String _date(int timestamp) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        timestamp,
      ).toLocal().toString().substring(0, 16);
    } catch (_) {
      return '未记录';
    }
  }
}
