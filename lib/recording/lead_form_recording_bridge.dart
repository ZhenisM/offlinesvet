import 'dart:async';
import 'package:offlinesvet/common/call_recording_service.dart';
import 'package:offlinesvet/customer/lead_form/lead_form_model.dart';
import 'package:offlinesvet/recording/lead_form_fields.dart';

/// Связывает анкету лида с записью разговора: отправляет в консультацию
/// изменения полей (field_changed) и этап — «Данные клиента» /
/// «Выявление потребности».
///
/// Анкета меняет данные разными путями (чипы, шторки выбора, текстовые
/// поля без notifyListeners), поэтому мост не встраивается в каждый виджет,
/// а раз в полсекунды сравнивает снимок полей с отправленным. Текст уходит,
/// когда менеджер перестал печатать (значение не менялось [_settle]).
class LeadFormRecordingBridge {
  LeadFormRecordingBridge({
    required this.data,
    required this.extraFields,
  });

  final LeadFormData data;

  /// Поля вне LeadFormData: NAME, PHONE, TYPE_ID, COMMENTS.
  final Map<String, String> Function() extraFields;

  static const _tick = Duration(milliseconds: 500);
  // Текст уходит после паузы в 3 с — чтобы «dim → dmitr → dmitri» при
  // медленном наборе не превращалось в три правки.
  static const _settle = Duration(seconds: 3);

  final _service = CallRecordingService.instance;
  Timer? _timer;
  Map<String, String> _sent = {};
  final Map<String, ({String value, DateTime since})> _pending = {};
  bool _reachedNeeds = false;

  void start() {
    _timer?.cancel();
    _service.setStage(CallRecordingService.stageClientData, reason: 'lead_form_opened');
    _sent = _snapshot();
    _timer = Timer.periodic(_tick, (_) => _check(force: false));
  }

  /// Перед закрытием анкеты — отправить всё, что ещё «отстаивается».
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _check(force: true);
  }

  void _check({required bool force}) {
    if (!_service.isRecording.value) {
      _pending.clear();
      _sent = _snapshot();
      return;
    }
    final now = DateTime.now();
    final snap = _snapshot();
    final keys = {..._sent.keys, ...snap.keys};
    for (final k in keys) {
      final v = snap[k] ?? '';
      if (v == (_sent[k] ?? '')) {
        _pending.remove(k);
        continue;
      }
      final p = _pending[k];
      if (p == null || p.value != v) {
        _pending[k] = (value: v, since: now);
        if (!force) continue;
      } else if (!force && now.difference(p.since) < _settle) {
        continue;
      }
      _pending.remove(k);
      _sent[k] = v;
      _emit(k, v);
    }
  }

  void _emit(String field, String value) {
    // В анкете этап только идёт вперёд: если после потребностей менеджер
    // вернулся и дописал возраст или психотип, это всё ещё «Выявление
    // потребности», а не возврат к этапу 1 (иначе этап прыгает туда-сюда).
    final isNeeds = !lfClientDataFields.contains(field);
    if (isNeeds) _reachedNeeds = true;
    final stage = _reachedNeeds
        ? CallRecordingService.stageNeeds
        : CallRecordingService.stageClientData;
    final ids = value.isEmpty ? const <String>[] : value.split(',');
    final isOption = lfOptions(field).isNotEmpty;
    final Object? payload = value.isEmpty
        ? null
        : (ids.length > 1 ? ids : value);
    final valueLabel = (isOption || field == 'TYPE_ID') && ids.isNotEmpty
        ? ids.map((id) => _optionLabel(field, id)).join(', ')
        : null;
    () async {
      await _service.setStage(stage, reason: 'field_changed');
      await _service.onFieldChanged(
        field: field,
        label: lfFieldLabels[field],
        value: payload,
        valueLabel: valueLabel,
      );
    }();
  }

  static String _optionLabel(String field, String id) {
    if (field == 'TYPE_ID') return id == '1' ? 'Дизайнер' : 'Клиент';
    for (final o in lfOptions(field)) {
      if (o.id == id) return o.label;
    }
    return id;
  }

  /// Плоский снимок: код поля → строка (множественные — ID через запятую,
  /// отсортированные, чтобы порядок кликов не считался изменением).
  Map<String, String> _snapshot() {
    final out = <String, String>{};
    void put(String k, Object? v) {
      if (v == null) return;
      String s;
      if (v is List) {
        final items = v.map((e) => e is Map ? (e['VALUE'] ?? '').toString() : e.toString()).toList()..sort();
        s = items.join(',');
      } else {
        s = v.toString().trim();
      }
      if (s.isNotEmpty) out[k] = s;
    }

    data.leadFields().forEach(put);
    data.contactFields().forEach(put);
    put('WHAT_SOUGHT', data.whatSought);
    extraFields().forEach(put);
    return out;
  }
}
