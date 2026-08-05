import 'package:flutter/material.dart';
import 'package:offlinesvet/common/call_recording_service.dart';

/// Кнопка "Записать разговор" — сама по себе просто отображает состояние
/// CallRecordingService (синглтон, живёт отдельно от экрана) и дёргает
/// start()/stop(). Прикрепление к лиду происходит НЕ здесь, а в момент
/// сохранения анкеты (см. new_customer_dialog.dart) — именно поэтому
/// запись переживает переход на другой экран после отправки лида.
class CallRecorderButton extends StatelessWidget {
  const CallRecorderButton({super.key});

  Future<void> _toggle(BuildContext context) async {
    final service = CallRecordingService.instance;
    if (service.isRecording.value) {
      await service.stop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Запись остановлена без привязки к лиду. '
            'Чтобы запись прикрепилась автоматически — в следующий раз '
            'сохраните анкету лида, не останавливая запись вручную.',
          )),
        );
      }
      return;
    }

    if (!await service.hasPermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нужно разрешение на использование микрофона')),
        );
      }
      return;
    }
    await service.start();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final service = CallRecordingService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.isRecording,
      builder: (context, isRecording, _) {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _toggle(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isRecording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                  color: isRecording ? Colors.red : Colors.black87,
                ),
                const SizedBox(width: 10),
                if (isRecording)
                  ValueListenableBuilder<Duration>(
                    valueListenable: service.elapsed,
                    builder: (context, elapsed, _) => Text(
                      'Идёт запись — ${_fmtDuration(elapsed)}. Сохраните анкету, '
                      'чтобы прикрепить, или нажмите здесь, чтобы остановить без привязки.',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red),
                    ),
                  )
                else
                  const Text(
                    'Записать разговор',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
