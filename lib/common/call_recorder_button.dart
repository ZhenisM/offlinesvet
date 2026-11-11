import 'package:flutter/material.dart';
import 'package:offlinesvet/common/call_recording_service.dart';
import 'package:offlinesvet/customer/customer_storage.dart';
import 'package:offlinesvet/recording/recording_upload_queue.dart';

/// Общие действия старт/стоп записи — для кнопки на главном экране,
/// микрофона в нижнем меню и экрана оформления.
class RecordingControls {
  RecordingControls._();

  /// Если запись идёт — спрашивает подтверждение и останавливает.
  /// Если нет — начинает новую запись, привязанную к [cartId] (по
  /// умолчанию — текущая активная корзина, если она есть).
  static Future<void> toggle(BuildContext context, {required String trigger, String? cartId}) async {
    final service = CallRecordingService.instance;
    if (service.isRecording.value) {
      await confirmStop(context);
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
    final started = await service.start(trigger: trigger, cartId: cartId);
    if (!started && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось начать запись')),
      );
    }
  }

  /// Ручная остановка с подтверждением — случайное касание не должно
  /// разрывать разговор на две записи.
  static Future<void> confirmStop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Остановить запись?'),
        content: const Text(
          'Разговор с этим клиентом будет завершён. Если включить запись снова, '
          'это будет уже новая запись — для текущей выбранной корзины.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Продолжить запись')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Остановить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await CallRecordingService.instance.stop(reason: 'manual');
    }
  }

  /// Старт из нижнего меню: запись сразу относится к текущей корзине.
  static Future<void> toggleForActiveCart(BuildContext context) async {
    if (CallRecordingService.instance.isRecording.value) {
      await confirmStop(context);
      return;
    }
    final cartId = await CustomerStorage.getActiveCartId();
    if (!context.mounted) return;
    await toggle(context, trigger: 'bottom_menu', cartId: cartId);
  }
}

/// Кнопка «Записать разговор» на главном экране. Запись живёт в
/// CallRecordingService и не зависит от экрана — переживает переход в
/// каталог после анкеты. Создание лида запись не останавливает.
class CallRecorderButton extends StatelessWidget {
  const CallRecorderButton({super.key});

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
            onTap: () => RecordingControls.toggle(context, trigger: 'button'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isRecording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
                  color: isRecording ? Colors.red : Colors.black87,
                ),
                const SizedBox(width: 10),
                if (isRecording)
                  Flexible(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: service.elapsed,
                      builder: (context, elapsed, _) => Text(
                        'Идёт запись — ${_fmtDuration(elapsed)}',
                        softWrap: true,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.red),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Записать разговор',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                  ),
                // Сколько кусков ещё не дошло до сервера (плохая сеть).
                ValueListenableBuilder<int>(
                  valueListenable: RecordingUploadQueue.instance.pendingCount,
                  builder: (context, pending, _) => pending > 2
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('· не отправлено $pending',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
