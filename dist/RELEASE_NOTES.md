## Изменения

- Панель F2 стала понятнее: состояния подключения и готовности мира, список игроков и вместимость сессии видны в основном окне.
- Диагностика вынесена в отдельное перемещаемое окно с прокруткой и одной кнопкой копирования отчёта.
- При завершении хостом сессии с подключёнными игроками появляется подтверждение. Отмена выбрана по умолчанию.
- Steam ID и адреса скрыты в отображаемой диагностике; скопированный отчёт не содержит имён игроков, идентификаторов и адресов подключения. Кнопка копирования собственного Steam ID по-прежнему копирует настоящий ID.
- Улучшены компоновка узких окон, длинные имена в списке игроков и обратная связь при копировании.

## Совместимость

Совместим с **v0.1.28**. Сетевой протокол и сетевое поведение не изменены: в этом релизе только доработки интерфейса.

## Установка и обновление

Скачайте **`KenshiCoop-kit.zip`**. Полностью закройте Kenshi и скопируйте папку `KenshiCoop` в `<Kenshi>\mods\` с заменой файлов. RE_Kenshi должен быть установлен. Существующий `coop_config.json` сохраните.

В архиве только `KenshiCoop.dll`, `KenshiCoopUI.dll`, `KenshiCoop.mod` и `RE_Kenshi.json`. Автообновление заменяет обе DLL, включая UI. После обновления перезапустите игру.

<details><summary>English</summary>

Improved the F2 panel's connection/world readiness states, roster and session capacity display. Diagnostics now use a separate movable, scrollable window with one report-copy button. Hosts are asked to confirm ending a session with connected players; Cancel is selected by default.

Displayed diagnostics mask Steam IDs and endpoints. Copied reports omit player names, IDs and connection addresses. Explicitly copying your own Steam ID still copies the real ID. Narrow-window layout, long roster names and clipboard feedback have also been improved.

Compatible with **v0.1.28**; network protocol and behavior are unchanged.

With Kenshi closed, copy `KenshiCoop/` from **`KenshiCoop-kit.zip`** into `<Kenshi>/mods/`, replacing the four mod files. RE_Kenshi must already be installed. Keep your `coop_config.json`. Auto-update replaces both DLLs, including the UI. Restart the game afterward.

</details>
