import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/quiz_backup.dart';
import '../services/backup_browser.dart';
import '../services/backup_sandbox_service.dart';
import '../services/backup_service.dart';
import '../services/backup_validation_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen(
      {super.key,
      this.source,
      this.sandbox,
      this.downloadFactory,
      this.pickFile});

  final BackupSource? source;
  final BackupSandboxService? sandbox;
  final BackupDownload Function(Uint8List)? downloadFactory;
  final Future<Uint8List?> Function()? pickFile;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _deviceLabel = TextEditingController(text: 'この端末');
  BackupSource? _source;
  BackupSandboxService? _sandbox;
  BackupDownload? _download;
  QuizBackup? _prepared;
  QuizBackup? _selected;
  BackupValidationReport? _report;
  BackupRestoreResult? _restored;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    try {
      _source = widget.source ?? createBrowserBackupSource();
      _sandbox = widget.sandbox ?? createBrowserBackupSandbox();
    } catch (_) {
      _error = 'この機能にはIndexedDBが利用できるWebブラウザが必要です。';
    }
  }

  @override
  void dispose() {
    _deviceLabel.dispose();
    _download?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '処理を完了できませんでした: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() => _run(() async {
        _download?.dispose();
        setState(() {
          _download = null;
          _prepared = null;
          _selected = null;
          _restored = null;
          _report = null;
        });
        final result = await BackupService(_source!).capture(_deviceLabel.text);
        if (!mounted) return;
        final download = (widget.downloadFactory ??
            BackupDownload.new)(result.backup.encode());
        setState(() {
          _download = download;
          _prepared = result.backup;
          _selected = null;
          _restored = null;
          _report = result.validation;
          _message = '書き出し用データを作成し、JSON変換前後の原文一致を確認しました。'
              'ファイルはまだ保存していません。';
        });
      });

  void _save() {
    try {
      final backup = _prepared!;
      final stamp =
          backup.createdAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      _download!.save('quiz-study-$stamp.quiz-backup.json');
      setState(() {
        _error = null;
        _message = 'ブラウザに保存を依頼しました。保存完了はまだ未確認です。'
            '保存したファイルを下のボタンで選び直してください。';
      });
    } catch (error) {
      setState(() => _error = '保存を開始できませんでした: $error');
    }
  }

  Future<Uint8List?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.size > QuizBackup.maxFileBytes) {
      throw const FormatException('ファイルの上限は64 MiBです。');
    }
    if (file.bytes == null) throw const FormatException('ファイルを読み込めませんでした。');
    return file.bytes;
  }

  Future<void> _loadFile() => _run(() async {
        // A failed or cancelled selection must not leave an earlier file verified.
        setState(() {
          _selected = null;
          _restored = null;
          _report = null;
        });
        final bytes = await (widget.pickFile ?? _pickFile)();
        if (bytes == null) return;
        final backup = QuizBackup.decode(bytes);
        final report = BackupValidationService().validate(backup.snapshot);
        if (!mounted) return;
        setState(() {
          _selected = backup;
          _report = report;
          _message = '選択ファイルのSHA-256を確認しました。隔離復元はまだ実行していません。';
          if (_prepared != null) {
            _message = '${_message!}\n現在作成したデータとの一致: '
                '${_prepared!.checksum == backup.checksum ? '一致' : '別のバックアップです'}';
          }
        });
      });

  Future<void> _verify() => _run(() async {
        setState(() => _restored = null);
        final result = await _sandbox!.verify(_selected!, _source!);
        if (!mounted) return;
        setState(() {
          _restored = result;
          _message = result.sourceUnchanged
              ? '選択ファイルの隔離復元・再読込で原文と音声の完全一致を確認しました。'
                  '処理前後の現行保存データも一致しています。検証DBは削除済みです。'
              : '隔離復元の内容は一致しましたが、処理中に現行データが変化しました。'
                  '他のタブでの学習を止め、再検証してください。検証DBは削除済みです。';
        });
      });

  @override
  Widget build(BuildContext context) {
    final available = _source != null && _sandbox != null && !_busy;
    final report = _report;
    return PopScope<void>(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('バックアップ・復元検証')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('現行データの削除・上書き・移行は行いません。'
                '復元は別の検証DBだけで行います。'),
            const SizedBox(height: 12),
            SelectableText('現在の保存領域: ${_source?.origin ?? '利用できません'}'),
            const SizedBox(height: 8),
            const Text('PC ChromeとiPhone Safariは別々に書き出してください。'
                'localhostのデータは公開サイトのデータとは異なります。'
                '他のタブでの学習を止め、各保存領域で実行してください。'),
            const SizedBox(height: 20),
            TextField(
              controller: _deviceLabel,
              enabled: available,
              decoration: const InputDecoration(
                  labelText: '端末名（例: PC Chrome / iPhone Safari）',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('prepare-backup'),
              onPressed: available ? _prepare : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('1. 現在のデータからバックアップを作成'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('download-backup'),
              onPressed: available && _prepared != null ? _save : null,
              icon: const Icon(Icons.download),
              label: const Text('2. ファイルを保存'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('load-backup'),
              onPressed: available ? _loadFile : null,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('3. 保存したバックアップファイルを選択'),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              SelectableText('選択ファイル: ${_selected!.deviceLabel}\n'
                  '取得元: ${_selected!.origin}\n取得日時（UTC）: ${_selected!.createdAt.toIso8601String()}'),
              if (_selected!.origin != _source?.origin)
                const Text('取得元と現在の保存領域は異なります。'
                    'この検証で取得元のブラウザを確認・復元することはありません。'),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('verify-backup'),
              onPressed: available &&
                      _selected != null &&
                      report?.canVerifyRestore == true
                  ? _verify
                  : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('4. 別DBへの復元・再読込を検証'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator()
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              SelectableText(_message!)
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              SelectableText(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (report != null) ...[
              const SizedBox(height: 20),
              Text('保存内容の診断', style: Theme.of(context).textTheme.titleLarge),
              const Text('履歴・問題別進捗・一周内の回答は重複するため、合算しません。'),
              for (final entry in report.counts.entries)
                Text('${entry.key}: ${entry.value}'),
              for (final error in report.errors)
                Text('エラー: $error',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final warning in report.warnings) Text('注意: $warning'),
              if (report.errors.isNotEmpty)
                const Text('原文の退避は可能ですが、整合性エラーがあるため復元検証はできません。'),
            ],
            if (_restored != null) ...[
              const SizedBox(height: 16),
              SelectableText('検証した隔離DB（削除済み）: ${_restored!.databaseName}\n'
                  '保存内容のSHA-256: ${_restored!.snapshotDigest}'),
            ],
            const SizedBox(height: 24),
            const Text('この機能は本番への復元を行いません。'
                'バックアップには解答やコメントなどの個人データを含みます。'
                'Gitリポジトリ・docs・公開フォルダの外へ保存してください。'
                'SHA-256は欠損検出用で、作成者の証明や暗号化ではありません。'),
          ],
        ),
      ),
    );
  }
}
