import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/quiz_backup.dart';
import '../services/backup_browser.dart';
import '../services/backup_sandbox_service.dart';
import '../services/backup_service.dart';
import '../services/backup_validation_service.dart';
import '../services/live_restore_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen(
      {super.key,
      this.source,
      this.sandbox,
      this.downloadFactory,
      this.pickFile,
      this.allowLiveRestore = false,
      this.restoreStore});

  final BackupSource? source;
  final BackupSandboxService? sandbox;
  final BackupDownload Function(Uint8List)? downloadFactory;
  final Future<Uint8List?> Function()? pickFile;
  final bool allowLiveRestore;
  final LiveRestoreStore? restoreStore;

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
  LiveRestoreStore? _liveStore;
  QuizBackup? _safetyBackup;
  bool _saveRequested = false;
  bool _recoveryChecked = false;
  bool _needsRecovery = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    try {
      _source = widget.source ?? createBrowserBackupSource();
      _sandbox = widget.sandbox ?? createBrowserBackupSandbox();
    } catch (_) {
      _error = 'この機能にはIndexedDBが利用できるWebブラウザが必要です。';
    }
    if (widget.allowLiveRestore) {
      try {
        _liveStore = widget.restoreStore ?? createBrowserLiveRestoreStore();
        _checkRecovery();
      } catch (error) {
        _error = '本番復元を利用できません: $error';
      }
    } else {
      _recoveryChecked = true;
    }
  }

  Future<void> _checkRecovery() async {
    try {
      final pending = await _liveStore!.readRecovery();
      if (mounted) {
        setState(() {
          _needsRecovery = pending != null;
          _recoveryChecked = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _needsRecovery = true;
          _recoveryChecked = true;
          _error = '端末内退避を確認できません。学習・復元を止めています: $error';
        });
      }
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
          _safetyBackup = null;
          _saveRequested = false;
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
        _saveRequested = true;
        _error = null;
        _message = 'ブラウザに保存を依頼しました。保存完了はまだ未確認です。'
            '保存したファイルを下のボタンで選び直してください。';
      });
    } catch (error) {
      setState(() => _error = '保存を開始できませんでした: $error');
    }
  }

  Future<void> _confirmSafetyFile() => _run(() async {
        setState(() => _safetyBackup = null);
        final bytes = await (widget.pickFile ?? _pickFile)();
        if (bytes == null) return;
        final safety = QuizBackup.decode(bytes);
        if (safety.checksum != _prepared?.checksum ||
            !sameBackupContents(safety.snapshot, await _source!.read())) {
          throw StateError('作成した退避データ・現行データと一致しません。再作成して保存してください。');
        }
        if (mounted) {
          setState(() {
            _safetyBackup = safety;
            _message = '復元前の退避ファイルを再読込し、現行データとの一致を確認しました。'
                '次に、戻したい時点のバックアップを選択してください。';
          });
        }
      });

  Future<void> _restoreLive() async {
    final target = _selected!;
    final safety = _safetyBackup!;
    var acknowledged = false;
    var phrase = '';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: const Text('本番復元の最終確認'),
                content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText('復元先: ${_source!.origin}\n'
                            '取得元: ${target.origin}\n端末: ${target.deviceLabel}\n'
                            'バックアップ日時（UTC）: ${target.createdAt.toIso8601String()}'),
                        for (final entry in BackupValidationService()
                            .validate(target.snapshot)
                            .counts
                            .entries)
                          Text('${entry.key}: ${entry.value}'),
                        const Text('現在のデッキ・問題・回答履歴・集計・問題別進捗・一周途中状態・'
                            '保存済み音声・未知の学習用キーを、このバックアップの状態に置き換えます。'
                            '追加・統合ではありません。バックアップにない学習用キーや音声は削除されます。'
                            'ID・日時・未知の項目・未作成キーは原文どおり復元します。'
                            '保存前の回答、外部音声の実体、他サイトや他端末のデータは対象外です。'),
                        const SizedBox(height: 8),
                        const Text('保存先をまたぐ完全な原子性はありません。失敗時は端末内退避から復旧し、'
                            '強制終了時は次回起動で学習を止めて復旧を案内します。'
                            'ブラウザによる保存領域消去や旧版タブからの更新は保護できません。'
                            '処理中は画面を閉じないでください。'),
                        CheckboxListTile(
                          key: const ValueKey('restore-acknowledge'),
                          value: acknowledged,
                          onChanged: (value) =>
                              update(() => acknowledged = value == true),
                          title: const Text('旧版・ホーム画面アプリを含む他のクイズ画面を閉じ、'
                              '退避ファイルを保管しました。置き換えと制約を確認しました。'),
                        ),
                        TextField(
                          key: const ValueKey('restore-phrase'),
                          decoration: const InputDecoration(
                              labelText: '確認のため「復元する」と入力'),
                          onChanged: (value) => update(() => phrase = value),
                        ),
                      ],
                    ))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル')),
                  FilledButton(
                    key: const ValueKey('confirm-live-restore'),
                    onPressed: acknowledged && phrase == '復元する'
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('現在のデータを置き換えて復元'),
                  ),
                ],
              )),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      try {
        await LiveRestoreService(_liveStore!)
            .restore(target, safety, confirmed: true);
        if (mounted) {
          setState(() {
            _completed = true;
            _message = '本番復元が完了しました。保存内容を2回再読込し、'
                '原文・未作成キー・音声の一致を確認しました。'
                '「学習画面を再読み込み」で新しい保存内容を読み込んでください。'
                '通常学習の再開後は、従来の進捗補完や学習保存により内容が更新されます。';
          });
        }
      } finally {
        _safetyBackup = null;
        await _checkRecovery();
      }
    });
  }

  Future<void> _recover() => _run(() async {
        await LiveRestoreService(_liveStore!).recover();
        await _checkRecovery();
        if (mounted) {
          setState(() {
            _completed = true;
            _message = '復元前の保存内容への復旧・再読込一致を確認しました。学習画面を再読み込みできます。';
          });
        }
      });

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
    final available = _source != null &&
        _sandbox != null &&
        !_busy &&
        _recoveryChecked &&
        !_needsRecovery &&
        !_completed;
    final report = _report;
    return PopScope<void>(
      canPop: !_busy && !_needsRecovery && !_completed,
      child: Scaffold(
        appBar: AppBar(title: const Text('バックアップ・復元検証')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('隔離復元・検証は本番データを変更しません。'
                '本番復元は、退避ファイルの保存・再読込と最終確認後に実データを置き換えます。'),
            if (_needsRecovery) ...[
              const Text('未完了の復元または退避の読取エラーがあります。通常学習は再開しないでください。'
                  '他のクイズ画面を閉じてから復元前の状態へ復旧してください。'
                  '保存領域は削除しないでください。'),
              FilledButton(
                  onPressed: !_busy && _liveStore != null ? _recover : null,
                  child: const Text('復元前のデータへの復旧を再試行')),
            ],
            if (_completed)
              const FilledButton(
                  onPressed: reopenStudy, child: Text('学習画面を再読み込み')),
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
            if (widget.allowLiveRestore) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('verify-safety-file'),
                onPressed:
                    available && _saveRequested ? _confirmSafetyFile : null,
                child: const Text('本番復元の準備: 保存した退避ファイルを選び直して確認'),
              ),
              if (_safetyBackup != null) const Text('復元前の退避ファイル: 保存・再読込確認済み'),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('load-backup'),
              onPressed: available ? _loadFile : null,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('3. 検証・復元したいバックアップファイルを選択'),
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
              label: const Text('4. 隔離復元・検証（本番データは変更しません）'),
            ),
            const SizedBox(height: 16),
            Text('本番復元', style: Theme.of(context).textTheme.titleLarge),
            if (!widget.allowLiveRestore)
              OutlinedButton(
                  onPressed: available ? openBackupOnly : null,
                  child: const Text('本番復元用の専用画面を再読み込みして開く'))
            else ...[
              const Text('上で現行データを退避して保存ファイルを確認した後、'
                  '戻したいバックアップを選択します。次のボタンでは確認画面を開きます。'),
              OutlinedButton.icon(
                key: const ValueKey('live-restore'),
                onPressed: available &&
                        _liveStore != null &&
                        _safetyBackup != null &&
                        _selected != null &&
                        report?.canVerifyRestore == true
                    ? _restoreLive
                    : null,
                icon: const Icon(Icons.warning_amber),
                label: const Text('本番復元の確認へ進む（現行データを置き換え）'),
              ),
            ],
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
            const Text('バックアップには解答やコメントなどの個人データを含みます。'
                'Gitリポジトリ・docs・公開フォルダの外へ保存してください。'
                'SHA-256は欠損検出用で、作成者の証明や暗号化ではありません。'),
          ],
        ),
      ),
    );
  }
}
