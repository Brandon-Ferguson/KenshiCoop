## Изменения

- Исправлена блокировка обновления инвентаря после синхронизированного перемещения экипировки: служебное перемещение больше не считается предметом, удерживаемым курсором для обмена.

## Известные проблемы

Новые сообщения о пропаже предметов при прямом обмене, разных товарах торговцев, рассинхронах времени и координат, кроватях на втором этаже и боевых анимациях остаются открытыми. Этот релиз не объявляет их исправленными. До отдельного исправления прямого обмена используйте передачу через пол.

## Совместимость

Обновите мод до **v0.1.31 у всех участников сессии**, включая хоста. Формат сетевых пакетов не изменён; старые сборки не содержат этого исправления.

## Установка и обновление

Скачайте **`KenshiCoop-kit.zip`**. Полностью закройте Kenshi и скопируйте папку `KenshiCoop` в `<Kenshi>\mods\` с заменой файлов. RE_Kenshi должен быть установлен. Существующий `coop_config.json` сохраните.

В архиве только `KenshiCoop.dll`, `KenshiCoopUI.dll`, `KenshiCoop.mod` и `RE_Kenshi.json`. Отдельные DLL нужны для автообновления; для ручной установки достаточно архива. Автообновление заменяет обе DLL, включая UI. После обновления перезапустите игру.

<details><summary>English</summary>

Fixed an inventory-update blockage after replicated equipment repositioning: snapshot maintenance no longer looks like an item held by the cursor for a user trade.

New reports of direct-trade item loss, differing merchant stock, time and position desynchronization, upstairs beds and combat animations remain open. This release does not claim to fix them. Use ground-item transfers instead of direct trading until a separate fix is available.

Update **every participant, including the Host, to v0.1.31**. Packet format is unchanged; older builds lack this fix.

With Kenshi closed, copy `KenshiCoop/` from **`KenshiCoop-kit.zip`** into `<Kenshi>/mods/`, replacing the four mod files. RE_Kenshi must already be installed. Keep your `coop_config.json`. The standalone DLL assets support auto-update; the ZIP is sufficient for manual installation. Auto-update replaces both DLLs, including the UI. Restart afterward.

</details>
