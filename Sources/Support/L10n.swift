import Foundation

/// UI localization without .lproj: English strings are the keys, Russian ones
/// are the translations. Switching is instant, the app is not restarted.
enum L10n {
    /// "auto" | "ru" | "en"
    static var resolvedLanguage: String {
        let stored = UserDefaults.standard.string(forKey: PrefKey.uiLanguage) ?? "auto"
        if stored == "ru" || stored == "en" { return stored }
        let system = Locale.preferredLanguages.first ?? "en"
        return system.hasPrefix("ru") ? "ru" : "en"
    }

    /// Used by tests: whether a Russian translation exists for a key.
    static func hasTranslation(_ key: String) -> Bool {
        russian[key] != nil
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let template = resolvedLanguage == "ru" ? (russian[key] ?? key) : key
        guard !args.isEmpty else { return template }
        return String(format: template, arguments: args)
    }

    private static let russian: [String: String] = [
        "Model settings…": "Настройки моделей…",
        "Download": "Скачать",
        "Test": "Проверить",
        "Select": "Выбрать",
        "Delete": "Удалить",
        "Cancel": "Отмена",
        "Cancel download": "Отменить загрузку",
        "Download cancelled": "Загрузка отменена",
        "Delete model?": "Удалить модель?",
        "This removes %@ from disk. You can download it again later.": "Файлы «%@» будут удалены с диска. Модель можно скачать снова.",
        "Deleted: %@": "Удалено: %@",
        "Delete failed: %@": "Не удалось удалить: %@",
        "Add folder": "Добавить папку",
        "Add folder…": "Добавить папку…",
        "Choose folders that contain CoreML Whisper models": "Выберите папки, в которых лежат CoreML-модели Whisper",
        "Testing model…": "Проверяем модель…",
        "Test passed: %@": "Проверка пройдена: %@",
        "Model test": "Проверка модели",
        "Model loaded but returned no text": "Модель загрузилась, но текста не вернула",
        "Recognition time: %.1f s": "Время распознавания: %.1f с",
        "Test failed: %@": "Проверка не удалась: %@",
        "No models installed": "Модели не установлены",
        "Custom folders": "Свои папки с моделями",
        "Models": "Модели",
        "Custom": "Своя",
        "Models from these folders appear in the list below.": "Модели из этих папок появятся в списке ниже.",

        // MARK: Menu
        "Start dictation": "Начать диктовку",
        "Stop and insert": "Остановить и вставить",
        "Hotkey: %@": "Хоткей: %@",
        "Microphone": "Микрофон",
        "Insertion": "Вставка",
        "Model: %@": "Модель: %@",
        "Model: loading… %d s": "Модель: загружается… %d с",
        "Settings…": "Настройки…",
        "Grant Accessibility access…": "Выдать доступ Accessibility…",
        "Minimum requirement. Without the microphone speech recognition does not work at all.": "Минимальное требование. Без микрофона распознавание речи не работает вообще.",
        "Needed for the global hotkey and for inserting text into other apps. Without it the text goes to the clipboard and you paste it yourself with ⌘V.": "Нужен для глобального хоткея и вставки текста в другие приложения. Без него текст попадает в буфер, а вставлять придётся самому через ⌘V.",
        "Granted": "Разрешено",
        "Access was denied. macOS remembers the decision, so restarting is the only way to see the dialog again.": "Доступ запрещён. macOS запоминает решение, поэтому увидеть диалог снова можно только после перезапуска.",
        "Restart to request again": "Перезапустить для нового запроса",
        "Accessibility is required for the hotkey and automatic insertion.": "Для хоткея и автоматической вставки нужно разрешить Accessibility.",
        "Without Accessibility only clipboard mode is available.": "Без Accessibility доступен только режим буфера обмена.",
        "Request access": "Запросить разрешение",
        "Continue": "Продолжить",
        "Microphone access…": "Доступ к микрофону…",
        "Microphone access required": "Нужен доступ к микрофону",
        "Quit": "Выйти",
        "Check for Updates…": "Проверить обновления…",
        "Update available": "Доступна новая версия",
        "Version %@ is available. You have %@.": "Доступна версия %@. У вас установлена %@.",
        "Later": "Позже",
        "Skip this version": "Пропустить эту версию",
        "No updates": "Обновлений нет",
        "You are running the latest version (%@).": "У вас последняя версия (%@).",
        "Could not check for updates": "Не удалось проверить обновления",
        "About PerfectWhisper": "О программе PerfectWhisper",
        "Version %@": "Версия %@",
        "Local dictation. Audio never leaves your Mac.": "Локальная диктовка. Аудио не покидает ваш Mac.",
        "License": "Лицензия",
        "Third-party notices": "Сторонние компоненты",
        "Close": "Закрыть",
        "PerfectWhisper needs the microphone to transcribe your speech. Audio never leaves your Mac.": "PerfectWhisper записывает голос, чтобы превратить его в текст. Аудио не покидает ваш Mac.",
        "Quit PerfectWhisper": "Выйти из PerfectWhisper",
        "Audio device %@": "Аудиоустройство %@",
        "Compiling model…": "Компилируем модель…",
        "Compiling model… %d s": "Компилируем модель… %d с",
        "Model ready (%.1f s)": "Модель готова (%.1f с)",
        "Model: compiling… %d s": "Модель: компилируется… %d с",
        "The first launch after install or update compiles the model for this Mac and may take a few minutes.": "Первый запуск после установки или обновления компилирует модель под этот Mac — это может занять несколько минут.",

        "The repository returned no file list": "Репозиторий не вернул список файлов",
        "The server returned an invalid response": "Сервер вернул некорректный ответ",
        "Model file is corrupted: %@": "Файл модели повреждён: %@",
        "No GitLab project configured for updates": "Не задан проект для обновлений",
        "The project has no releases": "В проекте нет релизов",
        "Invalid server response": "Некорректный ответ сервера",

        "Automatic (system default)": "Автоматически (системный)",
        "%@ (default)": "%@ (по умолчанию)",
        "Selected microphone is unavailable — using system default": "Выбранный микрофон недоступен — используется системный",

        // MARK: Insertion modes
        "Paste (⌘V), restore clipboard": "Вставить (⌘V), буфер восстановить",
        "Clipboard only": "Только в буфер обмена",
        "Type character by character": "Печатать по символам",

        // MARK: HUD and messages
        "Listening…": "Слушаю…",
        "Listening… %@": "Слушаю… %@",
        "%d s": "%d с",
        "Transcribing…": "Распознаю…",
        "Model not loaded": "Модель не загружена",
        "Ready (%.1f s)": "Готова (%.1f с)",
        "Load failed: %@": "Ошибка загрузки: %@",
        "No Accessibility — text is in clipboard": "Нет Accessibility — текст в буфере",
        "Secure input is enabled — text is in clipboard": "Включён безопасный ввод — текст в буфере",
        "Copied to clipboard": "Скопировано в буфер обмена",
        "Too short": "Слишком коротко",
        "Nothing recognized": "Ничего не распознано",
        "Error: %@": "Ошибка: %@",
        "Hotkey active": "Хоткей активен",
        "Download a Whisper model": "Скачайте модель Whisper",
        "Download a model first": "Сначала скачайте модель",
        "Accessibility access required": "Нужен доступ Accessibility",
        "Model failed to load": "Модель не загрузилась",
        "Model not found": "Модель не найдена",
        "No microphone access": "Нет доступа к микрофону",
        "Audio device changed — transcribed what was captured": "Устройство изменилось — распознал что успел",
        "Audio device changed": "Аудиоустройство изменилось",

        // MARK: Audio and recognition errors
        "No input audio device found": "Не найдено входное аудиоустройство",
        "Could not create audio converter": "Не удалось создать конвертер аудио",
        "Could not start recording: %@": "Не удалось запустить запись: %@",
        "Model is not loaded yet": "Модель ещё не загружена",
        "Model not ready": "Модель не готова",
        "Continue (%d)": "Продолжить (%d)",
        "Empty recording": "Пустая запись",

        // MARK: Settings tabs
        "General": "Общие",
        "Model": "Модель",
        "Access": "Доступ",

        // MARK: General
        "Interface language": "Язык интерфейса",
        "System": "Системный",
        "Double tap": "Двойное нажатие",
        "Modifier": "Модификатор",
        "Right Option": "Правый Option",
        "Left Option": "Левый Option",
        "Left Command": "Левый Command",
        "Double Left Option": "Двойной левый Option",
        "Double Left Command": "Двойной левый Command",
        "Right Command": "Правый Command",
        "Tap the modifier twice quickly.": "Нажмите модификатор дважды быстро.",
        "Double Fn": "Двойной Fn",
        "Double Right Option": "Двойной правый Option",
        "Double Right Command": "Двойной правый Command",
        "Single Fn still switches the input source. To keep the system quiet, set “Press 🌐 key to” → Do Nothing in Keyboard settings.": "Одиночный Fn по-прежнему переключает язык. Чтобы система не мешала, поставьте «Нажатие клавиши 🌐» → «Ничего не делать» в настройках клавиатуры.",
        "Keyboard shortcut": "Комбинация клавиш",
        "Hotkey": "Горячая клавиша",
        "Press the hotkey once to start recording, again to stop and insert the text.": "Нажмите хоткей один раз — начать запись, ещё раз — остановить и вставить текст.",
        "Where to put text": "Куда девать текст",
        "Add trailing space": "Добавлять пробел в конце",
        "Recognition": "Распознавание",
        "Language": "Язык",
        "Auto-detect": "Автоопределение",
        "Model hint (initial prompt)": "Подсказка модели (initial prompt)",
        "A list of terms and languages noticeably improves mixed-speech accuracy. Leave empty to disable.": "Список терминов и языков заметно улучшает качество на смешанной речи. Пустая строка — без подсказки.",
        "Launch at login": "Запускать при входе",
        "The app starts automatically when you log in. It appears in System Settings → General → Login Items.": "Приложение будет запускаться само при входе в систему. Его видно в «Системные настройки → Основные → Элементы входа».",
        "macOS needs your approval to add PerfectWhisper to login items.": "macOS просит подтвердить добавление PerfectWhisper в элементы входа.",
        "Open Login Items settings": "Открыть настройки элементов входа",
        "Sounds": "Звуки",
        "Start and stop signals": "Сигналы начала и конца записи",
        "Change": "Изменить",
        "Press shortcut… (Esc to cancel)": "Нажмите комбинацию… (Esc — отмена)",

        // MARK: Model
        "Current model": "Текущая модель",
        "Reload": "Перезагрузить",
        "Downloading %@…": "Скачиваем %@…",
        "Downloaded: %@": "Скачано: %@",
        "Download failed: %@": "Ошибка скачивания: %@",
        "Selected: %@": "Выбрана: %@",

        // MARK: Microphone
        "Input device": "Устройство ввода",
        "Recording will use “%@”. If it's the built-in microphone, Bluetooth headphones stay in A2DP and music quality is preserved.": "Запись пойдёт с «%@». Если это встроенный микрофон, Bluetooth-наушники останутся в A2DP и музыка не потеряет качество.",
        "The selected microphone is currently unavailable — the system default will be used.": "Выбранный микрофон сейчас недоступен — будет использован системный по умолчанию.",
        "macOS picks the microphone itself. With Bluetooth headphones active, music quality may drop because they switch to headset mode.": "macOS сама выбирает микрофон. При активных Bluetooth-наушниках качество музыки может упасть, потому что наушники переключаются в режим гарнитуры.",
        "Refresh list": "Обновить список",
        "How it works": "Как это работает",
        "“Automatic” follows the system input device: take the headphones off and recording moves to the built-in microphone. If you pick a microphone explicitly, PerfectWhisper will always record from it, even when headphones are connected.": "«Автоматически» следует за системным устройством ввода: сняли наушники — запись ушла на встроенный микрофон. Если выбрать микрофон явно, PerfectWhisper будет всегда писать с него, даже когда подключены наушники.",

        // MARK: Permissions
        "Access granted": "Доступ есть",
        "No access": "Доступа нет",
        "Open System Settings": "Открыть системные настройки",
        "Accessibility": "Универсальный доступ (Accessibility)",
        "Required for the global hotkey and for inserting text with ⌘V into other apps.": "Нужен для глобальной горячей клавиши и для вставки текста через ⌘V в другие приложения.",
        "Check again": "Проверить снова",

        // MARK: Model variants
        "Recommended. Same model as in whisper.cpp, fastest on macOS": "Рекомендуется. Та же модель, что и в whisper.cpp, максимальная скорость на macOS",
        "Less memory, slightly lower accuracy": "Меньше памяти, точность чуть ниже",
        "Maximum accuracy, noticeably slower": "Максимальная точность, заметно медленнее",
        "Compromise for slower Macs": "Компромисс для слабых машин",
        "Debug only, low quality": "Только для проверки, качество низкое",
    ]
}
