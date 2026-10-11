## Изменения

- Состояние замка сундука синхронизируется между игроками: после взлома другим участникам не нужно взламывать его повторно.
- Исправлено дублирование общего лута при одновременном подборе. Подтверждённое изменение содержимого применяется сразу, без ожидания очередной периодической синхронизации.
- Исправлены ошибки потери предметов и содержимого рюкзаков при обмене. Пока передача не подтверждена, предмет нельзя передать дальше; при отказе возвращается именно переданный экземпляр.
- Исправлена передача управления персонажами после смены отряда, в том числе при задержке сети и разных локальных ID. NPC сохраняют правильную цель боя, а здоровье переданного персонажа больше не публикуется одновременно двумя владельцами.
- Исправлено сопоставление персонажей при переносе и сбросе после изменения их ID.

## Совместимость

Обновите мод до **v0.1.30 у всех участников сессии**, включая хоста. Формат сетевых пакетов не изменён, но старые сборки не содержат этих исправлений — не смешивайте их в одной сессии.

Отдельные визуальные рассинхроны анимаций этим релизом не закрыты.

## Установка и обновление

Скачайте **`KenshiCoop-kit.zip`**. Полностью закройте Kenshi и скопируйте папку `KenshiCoop` в `<Kenshi>\mods\` с заменой файлов. RE_Kenshi должен быть установлен. Существующий `coop_config.json` сохраните.

В архиве только `KenshiCoop.dll`, `KenshiCoopUI.dll`, `KenshiCoop.mod` и `RE_Kenshi.json`. Отдельные DLL в релизе нужны для автообновления: для ручной установки достаточно архива. Автообновление заменяет обе DLL, включая UI; после обновления перезапустите игру. Если ранее отключали автообновление для локальной сборки, его можно снова включить.

<details><summary>English</summary>

Shared chest locks now synchronize after lockpicking. Fixed simultaneous shared-loot pickup duplication, delayed application of confirmed inventory changes, and item/backpack-content loss during exchange. Provisional items cannot be forwarded before confirmation; rejected transfers restore the actual transferred instance.

Fixed character ownership handoff across squad moves, delayed body creation and differing native IDs. NPC combat targets resolve to the correct character, and handed-off character health has a single author. Carry/drop identity mapping also follows changed character IDs.

Update **every participant, including the Host, to v0.1.30**. Packet format is unchanged, but older builds lack these fixes and should not be mixed in one session. Separate visual animation desynchronization is not resolved by this release.

With Kenshi closed, copy `KenshiCoop/` from **`KenshiCoop-kit.zip`** into `<Kenshi>/mods/`, replacing the four mod files. RE_Kenshi must already be installed. Keep your `coop_config.json`. The standalone DLL assets support auto-update; the ZIP is sufficient for manual installation. Auto-update replaces both DLLs, including the UI. Restart afterward. Auto-update disabled for a previous local build can now be re-enabled.

</details>
