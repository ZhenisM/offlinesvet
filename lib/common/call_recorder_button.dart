import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:offlinesvet/bitrix/bitrix_service.dart';

/// Кнопка "Записать разговор" — намеренно НЕ привязана к конкретной
/// анкете/лиду в момент начала записи. Менеджер может начать запись,
/// затем заполнить и сохранить анкету лида (это создаст лид в Bitrix
/// раньше, чем закончится разговор), и только когда запись
/// остановится — она прикрепится к ТОМУ САМОМУ, только что созданному
/// лиду (crm.timeline.comment.add с файлом). Хранения записей на
/// сервере сайта нет — файл целиком уходит в Bitrix24.
class CallRecorderButton extends StatefulWidget {
  const CallRecorderButton({super.key});

  @override
  State<CallRecorderButton> createState() => _CallRecorderButtonState();
}

class _CallRecorderButtonState extends State<CallRecorderButton> {
  final _recorder = AudioRecorder();
  final _bitrixService = BitrixService(dio: Dio());

  bool _isRecording = false;
  bool _isUploading = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String? _currentFilePath;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужно разрешение на использование микрофона')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

    setState(() {
      _isRecording = true;
      _currentFilePath = path;
      _elapsed = Duration.zero;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecordingAndAttach() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    final filePath = path ?? _currentFilePath;
    if (filePath == null) return;

    setState(() => _isUploading = true);
    try {
      // Берём ID лида, созданного последним (см. BitrixService.createLead) —
      // если такого нет или он создан слишком давно (> 3 часов), считаем,
      // что прикреплять запись некуда.
      final leadId = await BitrixService.getLastLeadId();
      if (leadId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Не найден недавно созданный лид — запись не прикреплена. '
            'Сначала создайте лид через анкету.',
          )),
        );
        return;
      }

      final bytes = await File(filePath).readAsBytes();
      final base64Content = base64Encode(bytes);
      final filename = 'call_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _bitrixService.attachRecordingToLead(
        leadId: leadId,
        base64Content: base64Content,
        filename: filename,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Запись прикреплена к лиду #$leadId')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось прикрепить запись: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
      // Временный файл на устройстве больше не нужен после отправки —
      // на сервере сайта запись не хранится вообще.
      try { await File(filePath).delete(); } catch (_) {}
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _isUploading ? null : (_isRecording ? _stopRecordingAndAttach : _startRecording),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_isUploading)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                _isRecording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                color: _isRecording ? Colors.red : Colors.black87,
              ),
            const SizedBox(width: 10),
            Text(
              _isUploading
                  ? 'Отправляем в Bitrix...'
                  : _isRecording
                      ? 'Идёт запись — ${_fmtDuration(_elapsed)} (нажмите, чтобы остановить)'
                      : 'Записать разговор',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _isRecording ? Colors.red : Colors.black87,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
