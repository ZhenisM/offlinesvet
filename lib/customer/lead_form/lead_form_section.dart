import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offlinesvet/customer/lead_form/lead_form_model.dart';

/// Полная анкета лида (как CRM-форма №81 на сайте) одним списком:
/// контакт, помещения, высота, квадратура, доп. освещение, стиль, источник,
/// стадия ремонта, возраст и психотип, кто был с клиентом, предпочтения,
/// что искал и категория товара. Ветки показываются только когда нужны —
/// как условия в форме Bitrix24.
class LeadFormSection extends StatelessWidget {
  const LeadFormSection({super.key, required this.data});
  final LeadFormData data;

  static const _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data,
      builder: (context, _) {
        final rooms = data.selectedRooms;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('Данные контакта'),
            _input(hint: 'E-mail', initial: data.email, keyboard: TextInputType.emailAddress,
                onChanged: (v) => data.email = v),
            const SizedBox(height: 8),
            _BirthDateField(data: data),
            const SizedBox(height: 8),
            _input(hint: 'ИИН (12 цифр)', initial: data.iin, keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                onChanged: (v) => data.iin = v),

            _section('Пол клиента', required: true),
            _single(LfF.gender),

            _section('Куда подбираете освещение'),
            _label('Высота потолков у всех комнат'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Одинаковая', data.sameHeight == true, () => data.setSameHeight(true)),
              _chip('Разная', data.sameHeight == false, () => data.setSameHeight(false)),
            ]),
            const SizedBox(height: 10),
            _label('Помещения'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in lfRooms) _chip(r.label, data.rooms.contains(r.label), () => data.toggleRoom(r.label)),
            ]),
            if (data.rooms.contains('Прочее')) ...[
              const SizedBox(height: 8),
              _input(hint: 'Прочее — своё значение', initial: data.text[LfF.otherText],
                  onChanged: (v) => data.setText(LfF.otherText, v)),
            ],

            if (data.sameHeight == true) ...[
              _section('Высота потолков (общая)'),
              _single(LfF.heightAll, title: 'Высота потолков (общая)'),
              if (lfIsCustom(LfF.heightAll, data.single[LfF.heightAll]))
                _number('Своя высота, м', LfF.heightAllCustom),
            ],
            if (data.sameHeight == false && rooms.isNotEmpty) ...[
              _section('Высота потолков'),
              for (final r in rooms) ...[
                _label(r.label),
                _single(r.height, title: 'Высота потолков — ${r.label}'),
                if (lfIsCustom(r.height, data.single[r.height])) _number('Своя высота, м — ${r.label}', r.heightCustom),
                const SizedBox(height: 6),
              ],
            ],

            if (rooms.isNotEmpty) ...[
              _section('Квадратура'),
              for (final r in rooms) ...[
                _label(r.label),
                _single(r.area, title: 'Квадратура — ${r.label}'),
                const SizedBox(height: 6),
              ],
            ],

            _section('Дополнительное освещение'),
            _single(LfF.extraLight),
            if (data.extraLight)
              for (final r in rooms) ...[
                const SizedBox(height: 8),
                _label('${r.label}: сколько точек выведено'),
                _single(r.points, title: 'Сколько точек выведено — ${r.label}'),
                if (lfIsCustom(r.points, data.single[r.points])) _number('Своё количество точек — ${r.label}', r.pointsCustom),
                const SizedBox(height: 6),
                _label('${r.label}: точки под доп. освещение'),
                _single(r.pointsType),
              ],
            if (data.extraLight && rooms.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Отметьте помещения выше — по ним появятся вопросы о точках.',
                    style: TextStyle(fontSize: 12.5, color: Colors.black45)),
              ),

            _section('Стиль помещения'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Общий для всех комнат', data.separateStyle == false, () => data.setSeparateStyle(false)),
              _chip('Раздельный', data.separateStyle == true, () => data.setSeparateStyle(true)),
            ]),
            if (data.separateStyle == false) ...[
              const SizedBox(height: 10),
              _single(LfF.styleAll, title: 'Стиль для всех комнат', forcePicker: true),
            ],
            if (data.separateStyle == true)
              for (final r in rooms) ...[
                const SizedBox(height: 10),
                _label(r.label),
                _single(r.style, title: 'Стиль — ${r.label}', forcePicker: true),
              ],

            _section('Откуда пришёл клиент', required: true),
            _single(LfF.source, title: 'Откуда пришёл клиент', forcePicker: true),
            if (data.single[LfF.source] == lfSourceOther) ...[
              const SizedBox(height: 8),
              _input(hint: 'Источник — своё значение', initial: data.text[LfF.sourceText],
                  onChanged: (v) => data.setText(LfF.sourceText, v)),
            ],

            _section('Стадия ремонта'),
            _single(LfF.repairStage, title: 'Стадия ремонта'),

            _section('Возраст клиента', required: true),
            _single(LfF.age),
            _section('Психотип клиента', required: true),
            _single(LfF.psychotype),

            _section('Сколько человек было с клиентом'),
            _single(LfF.peopleCount, title: 'Сколько человек было с клиентом'),
            _section('Кто был с клиентом'),
            _multi(LfF.whoWasWith, title: 'Кто был с клиентом'),

            _section('Угости клиента — предпочтения'),
            _multi(LfF.coffee, title: 'Предпочтения клиента'),

            _section('Что искал клиент'),
            _input(hint: 'Например: люстра в зал, бра в спальню', initial: data.whatSought,
                onChanged: (v) => data.whatSought = v),
            const SizedBox(height: 10),
            _label('Категория товара'),
            _single(LfF.category, title: 'Категория товара'),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // ── элементы ────────────────────────────────────────────────────────

  /// Заголовок блока; обязательные — с красной звёздочкой.
  Widget _section(String title, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text.rich(TextSpan(
          text: title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
          children: [
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ],
        )),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _green : Colors.black12),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 14, color: selected ? Colors.white : Colors.black87)),
        ),
      );

  /// Списки длиннее этого — выбор в отдельном окне, короткие — кнопками.
  static const _inlineMax = 6;

  /// Один вариант (повторное нажатие снимает выбор).
  Widget _single(String field, {String? title, bool forcePicker = false}) {
    final opts = lfOptions(field);
    if (forcePicker || opts.length > _inlineMax) {
      return _PickerField(data: data, field: field, title: title ?? 'Выберите', multi: false);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in opts)
        _chip(o.label, data.single[field] == o.id, () => data.setSingle(field, o.id)),
    ]);
  }

  /// Несколько вариантов.
  Widget _multi(String field, {String? title}) {
    final opts = lfOptions(field);
    if (opts.length > _inlineMax) {
      return _PickerField(data: data, field: field, title: title ?? 'Выберите', multi: true);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in opts)
        _chip(o.label, data.multi[field]?.contains(o.id) ?? false, () => data.toggleMulti(field, o.id)),
    ]);
  }


  Widget _number(String hint, String field) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _input(
          hint: hint,
          initial: data.text[field],
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (v) => data.setText(field, v),
        ),
      );

  Widget _input({
    required String hint,
    String? initial,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    required ValueChanged<String> onChanged,
  }) =>
      TextFormField(
        initialValue: initial,
        keyboardType: keyboard,
        inputFormatters: formatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
      );
}

/// Поле-кнопка: показывает выбранное, по нажатию открывает окно со списком.
class _PickerField extends StatelessWidget {
  const _PickerField({required this.data, required this.field, required this.title, required this.multi});
  final LeadFormData data;
  final String field;
  final String title;
  final bool multi;

  static const _green = Color(0xFF4CAF50);

  String? _value() {
    final opts = lfOptions(field);
    if (multi) {
      final sel = data.multi[field] ?? const <String>{};
      final labels = opts.where((o) => sel.contains(o.id)).map((o) => o.label).toList();
      return labels.isEmpty ? null : labels.join(', ');
    }
    final id = data.single[field];
    for (final o in opts) {
      if (o.id == id) return o.label;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: AnimatedBuilder(
          animation: data,
          builder: (ctx, _) {
            final opts = lfOptions(field);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                    if (_value() != null)
                      TextButton(
                        onPressed: () {
                          if (multi) {
                            data.multi.remove(field);
                            data.touch();
                          } else {
                            data.setSingle(field, null);
                          }
                        },
                        child: const Text('Сбросить'),
                      ),
                  ]),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: opts.length,
                    itemBuilder: (_, i) {
                      final o = opts[i];
                      if (multi) {
                        return CheckboxListTile(
                          value: data.multi[field]?.contains(o.id) ?? false,
                          activeColor: _green,
                          title: Text(o.label),
                          onChanged: (_) => data.toggleMulti(field, o.id),
                        );
                      }
                      final selected = data.single[field] == o.id;
                      return ListTile(
                        title: Text(o.label),
                        trailing: selected ? const Icon(Icons.check, color: _green) : null,
                        onTap: () {
                          if (!selected) data.setSingle(field, o.id);
                          Navigator.pop(ctx); // один вариант — закрываем сразу
                        },
                      );
                    },
                  ),
                ),
                if (multi)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Готово', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  )
                else
                  const SafeArea(top: false, child: SizedBox(height: 8)),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _value();
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: v != null ? _green : Colors.transparent),
        ),
        child: Row(children: [
          Expanded(
            child: Text(v ?? 'Выбрать',
                style: TextStyle(fontSize: 15, color: v == null ? Colors.grey.shade400 : Colors.black87)),
          ),
          const Icon(Icons.expand_more, color: Colors.black38),
        ]),
      ),
    );
  }
}

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({required this.data});
  final LeadFormData data;

  @override
  Widget build(BuildContext context) {
    final d = data.birthDate;
    final text = d == null
        ? 'Дата рождения'
        : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: d ?? DateTime(now.year - 35, now.month, now.day),
          firstDate: DateTime(1920),
          lastDate: now,
          helpText: 'Дата рождения',
        );
        if (picked != null) {
          data.birthDate = picked;
          data.touch();
        }
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: d == null ? Colors.grey.shade400 : Colors.black87))),
          if (d != null)
            GestureDetector(
              onTap: () { data.birthDate = null; data.touch(); },
              child: const Icon(Icons.close, size: 18, color: Colors.black38),
            )
          else
            const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.black38),
        ]),
      ),
    );
  }
}
