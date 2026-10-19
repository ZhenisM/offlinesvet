// Данные разделов «Обучение» и «Графики» — со страниц сайта offline.svet.kz
// (/obuchenie_svet/ и /managers_reports/grafiki.php). Видео и отчёты
// Power BI открыты публично, поэтому приложение открывает их напрямую.

class LearningVideo {
  final String title;
  final String url;
  const LearningVideo(this.title, this.url);
}

class PowerBiReport {
  final String title;
  final String url;
  /// Требует входа в Microsoft (не «Опубликовать в веб»).
  final bool needsLogin;
  const PowerBiReport(this.title, this.url, {this.needsLogin = false});
}

const learningVideos = <LearningVideo>[
  LearningVideo("Поле в Сделке- место обслуживания клиента", "https://offline.svet.kz/upload/medialibrary/dea/0y2wyu63a88vwxttr1szev6h2fk059co/Pole-Mesto-obsluzhivaniya-klienta-_-sdelano-v-Clipchamp.mp4"),
  LearningVideo("Возврат товара в Сделку Б24 если он пропал оттуда при редактировании", "https://offline.svet.kz/upload/medialibrary/4e9/scd32x3y8ot0wm3xtpohv6oc291v5zvh/Vozvrat-tovara-pri-redaktirovanii.mp4"),
  LearningVideo("Мультикорзина", "https://offline.svet.kz/upload/medialibrary/ad6/dw0z9nj2sbaozzfncjp3z5hhoujpfyer/Multikorzina.mp4"),
  LearningVideo("Добавление нескольких клиентов в мультикорзину", "https://offline.svet.kz/upload/medialibrary/033/wdw97nq9wzkbnlas52tau3t6qj8u59mg/Dobavlenie-nesolkikh-klientov-v-multikorzinu.mp4"),
  LearningVideo("Распечатка КП после правки заказа", "https://offline.svet.kz/upload/medialibrary/1e9/lcui8j9uireg42bijfwkg7dia0vac59y/Raspechatka_KP_posle_pravki_zakaza.mp4"),
  LearningVideo("Редактирование выбора помещения", "https://offline.svet.kz/upload/medialibrary/e84/u044unxy4ftu71n5tvwvh610om3vtnts/redaktirovanie_vybora_pomeshcheniya.mp4"),
  LearningVideo("Применение скидки", "https://offline.svet.kz/upload/medialibrary/aa7/s904pr912fgfu043lrljb3px1x9oltdo/primenenie_skidki.mp4"),
  LearningVideo("Поле корректировать и кнопка \"Без Итого\"", "https://offline.svet.kz/upload/medialibrary/5bd/rit4cazjknyt0o3k4ddjw3ydjmy037lx/pole_korrektirovat_i_knopka_bez_Itogo.mp4"),
  LearningVideo("Где находится умный фильтр", " https://offline.svet.kz/upload/medialibrary/fb7/zntw0s02m9gudos2nprsni7gcdxqum86/Ubrali-umnyy-filtr.mp4"),
  LearningVideo("Распечатка КП после правки заказа", " https://offline.svet.kz/upload/medialibrary/73a/cvjb0silwsl2fc1bwf0c5kl7wuqbo3m8/Raspechatka_KP_posle_pravki_zakaza.mp4"),
  LearningVideo("Создание КП через каталог под дизайнера часть 1", "https://offline.svet.kz/upload/medialibrary/05c/zi1medntxyz7wtqbmig3cupnvwc1t0jg/Vybor_dizaynera_oformlenie_zakaza.mp4"),
  LearningVideo("Создание КП через каталог под дизайнера часть 2", "https://offline.svet.kz/upload/medialibrary/476/1w3i3b3jlkh3zrkjljjdlc28kwe3c3td/Vybor_dizaynera_oformlenie_zakaza_chast_2.mp4"),
  LearningVideo("Создание Заказа под существующего клиента", "https://offline.centr-krasok.kz/upload/medialibrary/806/dqu3mnjg5jb3v8x7gsnzukotlso9ut5v/Sushchestvuyushchiy-klient-_-Zakaz-na-sayte-_-sdelano-v-Clipchamp.mp4"),
  LearningVideo("Создание Некачественного Лида через Анкету клиента", "https://offline.svet.kz/upload/medialibrary/9fc/4rj1sqbc3to1uutlf25ruhsp131nkwkv/Nekachestvennyy-lid_-sdelano-v-Clipchamp-_6_.mp4"),
  LearningVideo("Создание Качественного Лида через Анкету Клиента", "https://offline.svet.kz/upload/medialibrary/e0c/5zh3jo91b6yklwa1llupehyi65fz3irq/Kachestvennyy-lid-_-sdelano-v-Clipchamp-_6_.mp4"),
  LearningVideo("Заполнение Анкеты Лида", "https://offline.svet.kz/upload/medialibrary/898/qvie7s92nkstf1ird33bzg3d737s2v8b/Zapolnenie-Ankety-Lida-_-sdelano-v-Clipchamp.mp4"),
];

const chartReports = <PowerBiReport>[
  PowerBiReport("Потенциальные проекты", "https://app.powerbi.com/view?r=eyJrIjoiNTU4MjNiNjUtM2RiZC00MjY3LTgxN2ItNDNhYTg1MDE4MmNlIiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9"),
  PowerBiReport("Лиды Оффлайн", "https://app.powerbi.com/view?r=eyJrIjoiMGI4ZjcxOGEtZTM1My00MTk1LWJkMzUtYzM0YmQ2ZDRiOWRkIiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9&pageName=3f369af10dc842fffb73"),
  PowerBiReport("Статистика выполняемых задач по дизайнерам (Воронка СРП 2026 Дизайнеры)", "https://app.powerbi.com/view?r=eyJrIjoiNDY2YTUyNjYtMmYwYS00ZWZjLTg4Y2ItMjlmODE2YmFiZmU2IiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9"),
  PowerBiReport("Создание лидов по времени подключения, 2025", "https://app.powerbi.com/view?r=eyJrIjoiOTVhZDc4ODgtZTg0YS00ZDczLWJlYTItNDhmYzA3MjI2ZGEwIiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9"),
  PowerBiReport("Создание лидов по магазинам и источникам, 2026", "https://app.powerbi.com/view?r=eyJrIjoiMWRhNmMyNjctYzJlYi00N2Q1LTg3M2EtNDRiODAxMDM2NzM3IiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9"),
  PowerBiReport("Сделки по этапам воронки «СВЕТ 2026 ВОРОНКА ПРОДАЖ»", "https://app.powerbi.com/view?r=eyJrIjoiNTZlMjI1M2ItZTc3NS00ZTg3LWEzNjktZTYzN2I1MDg0ZDAyIiwidCI6IjBiZjBhMjFjLTA4MDEtNGFiOC1hN2NiLWQzYTBiZjc4NTRmMiIsImMiOjl9&pageName=c1b9a59b3357b5389c07"),
  PowerBiReport("Основной финансовый отчёт", "https://app.powerbi.com/view?r=eyJrIjoiNTlmYjgxZWUtOWJhNC00MmUwLWJhZjMtZDQyM2Q5YmUwYzBlIiwidCI6IjMxNDRjYWI1LTIyYzItNDY3ZC05NTZhLWVmYjUyMzRiN2IwOSIsImMiOjl9&pageName=ReportSection"),
  PowerBiReport("Временный отчёт", "https://app.powerbi.com/reportEmbed?reportId=19dd4fcf-5b20-44f9-a8c1-d25fce849602&autoAuth=true&ctid=9a531ee8-6fd1-46be-9344-dd4178dd33ba", needsLogin: true),
];
