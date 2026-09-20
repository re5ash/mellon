# Происхождение фоновых ресурсов

Фоны подготовлены встроенным генератором изображений по трём пользовательским
референсам, затем сохранены в WebP (quality 85). Растровые ресурсы содержат
только фон. Тексты, карточки, кнопки, навигация, иконки и данные — Flutter-виджеты.

## assets/themes/cathedral.webp

Исходный референс: 2CFA129A-E1B5-4292-9783-EFBAF58CD115(3).PNG.
Запрос:

> Use case: precise-object-edit. Asset type: local mobile app wallpaper. Edit target: attached interface reference. Remove ALL interface overlays, cards, text, icons, avatars, status bar and navigation bar. Reconstruct only the background that continues behind them. Preserve exactly the existing underlying cathedral architecture composition: warm cream white carved arcade and candles at left, luminous sky and distant golden cross dome right, reflective pale marble floor below. Preserve existing gentle optical blur and diffuse warm light, no new objects. Full bleed portrait 941:1672 aspect. NO text, NO panels, NO UI, NO frames, NO border. This is a clean background extraction/inpainting for a live app, not an app mockup.

## assets/themes/radiance.webp

Исходный референс: 922451B6-A5E7-457A-AAB9-54A29F1DB6D9(3).PNG.
Запрос:

> Use case: precise-object-edit. Asset type: clean mobile app wallpaper. Edit target: attached UI reference. Remove absolutely ALL text, icons, avatars, buttons, chat panels, glass cards and bottom navigation. Inpaint the underlying very pale luminous cream-white softly blurred background faithfully. Preserve pale blue-white sky, golden rays diagonally from upper right, distant subtle Orthodox golden dome with cross at upper right, delicate light bokeh and soft warm gold glow at edges/lower corners. Center remains luminous near white, faint architecture only behind distant upper right. No additional objects. Match source background hues/blur/composition exactly, portrait941:1672. NO UI, NO text, NO frames, no avatars, no bubbles, no large glass shapes.

## assets/themes/azure.webp

Исходный референс: Молодёжный клуб_ светлый ореол храма(5).PNG.
Запрос:

> Use case: precise-object-edit. Asset type: clean mobile app wallpaper. Edit target: attached interface reference. Remove ALL UI overlays including all lettering, logos, cards, avatar, icons, clock, toolbar, chat rows and navigation. Reconstruct underlying background faithfully behind them: pale blue softly clouded sky at top, blurred dark olive green branches along left edge, luminous white Orthodox church exterior with gold cross and dome at upper right, white stone foreground lower right, golden warm daylight lower left. Keep original source optical blur and exact background positions, hues and atmosphere. Full bleed portrait941:1672. No additional subjects. NO words, no glass panels, no phone frame, no icons or circles. Output just a clean softly out of focus photographic background for a live app.

Недоступные участки исходных изображений восстанавливаются генерацией, поэтому
эти ресурсы не являются точными исходными фонами дизайн-макетов.
