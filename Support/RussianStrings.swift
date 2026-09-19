import Foundation

/// Russian string table (active when the system language is Russian).
///
/// Keys must always mirror `EnglishStrings.dict` so the locale switch is seamless
/// and non-Russian locales degrade to the English fallback.
public enum RussianStrings {
    /// Key-value mapping shared with the localization coordinator (`L`).
    public static let dict: [String: String] = [
        // App menu
        "about": "О программе",
        "settings": "Настройки...",
        "close": "Закрыть",

        // Login screen
        "login.prompt": "Войдите, чтобы начать общение",
        "login.button": "Войти через Google",

        // Sidebar / list
        "filter.placeholder": "Фильтр по названию",
        "filter.clear": "Очистить фильтр",
        "no.chats": "Нет чатов",
        "nothing.found": "Ничего не найдено",
        "new.chat": "Новый чат",
        "sign.out": "Выйти",

        // Chat detail / empty state
        "select.chat": "Выберите чат",
        "select.chat.hint": "Нажмите на чат слева, чтобы начать переписку",
        "members.toolbar": "Участники %@",
        "members.help": "Участники чата",
        "attach.files": "Прикрепить файлы",
        "message.placeholder": "Сообщение...",
        "send": "Отправить",
        "edit": "Редактировать",
        "delete": "Удалить",
        "save": "Сохранить",
        "edit.placeholder": "Редактировать сообщение...",
        "jump.unread.hint": "К первому непрочитанному сообщению",

        // Member management
        "members.title": "Участники",
        "member.search.placeholder": "Имя или email…",
        "search": "Найти",
        "add.member.header": "Добавить участника",
        "already.in.chat": "В чате",
        "add": "Добавить",
        "no.results": "Никого не найдено",
        "you": "Вы",
        "remove": "Удалить",
        "leave.chat": "Покинуть чат",

        // Список чатов
        "space.pin": "Закрепить сверху",
        "space.unpin": "Открепить",

        // About
        "version.format": "Версия %@ (сборка %@)",
        "developer": "Разработчик",
        "contact": "Контакт",
        "unofficial.client.note": "Неофициальный клиент Google Chat для macOS",
        "about.gogol.note": "Назван в честь писателя Николая Васильевича Гоголя.",

        // Create chat
        "new.chat.title": "Новый чат",
        "name": "Название",
        "type": "Тип",
        "channel": "Канал",
        "group.chat": "Групповой чат",
        "cancel": "Отмена",
        "creating": "Создание...",
        "create": "Создать",

        // Settings
        "display.name": "Отображаемое имя",
        "settings.oauth.note": "OAuth Client ID используется при входе. Reversed Client ID генерируется из него автоматически и должен совпадать со значением GOOGLE_REVERSED_CLIENT_ID в локальном GoogleChat.local.xcconfig, потому что macOS регистрирует callback из Info.plist при сборке приложения.",
        "settings.reversed.help": "Только для чтения – выводится из OAuth Client ID разворотом dot-компонентов.",

        // Reaction picker
        "reaction.picker.title": "Выбор реакции",
        "reaction.search.placeholder": "Поиск эмодзи",
        "reaction.search.empty": "Ничего не найдено",
        "category.smileys": "Смайлики",
        "category.people": "Жесты и люди",
        "category.animals": "Животные и природа",
        "category.food": "Еда и напитки",
        "category.activities": "Активности",
        "category.travel": "Путешествия",
        "category.objects": "Объекты",
        "category.symbols": "Символы",
        "category.flags": "Флаги",

        // Message bubble / attachments
        "copy.text": "Копировать текст",
        "quote": "Цитировать",
        "quote.original": "Сообщение",
        "quote.remove": "Убрать цитату",
        "quote.jump": "Перейти к цитируемому сообщению",
        "more.reactions": "Другие реакции...",

        // Custom icons
        "add.custom.icon": "Добавить иконку...",
        "add.custom.icon.title": "Добавить иконку",
        "add.custom.icon.drop": "Перетащите изображение сюда или нажмите, чтобы выбрать",
        "add.custom.icon.choose": "Выбрать файл...",
        "add.custom.icon.name": "Имя эмодзи",
        "add.custom.icon.upload": "Загрузить",
        "add.custom.icon.uploading": "Загрузка...",
        "add.custom.icon.success": "Иконка загружена",
        "add.custom.icon.animated": "анимированная",
        "add.custom.icon.error.pick": "Сначала выберите изображение",
        "add.custom.icon.error.invalid": "Не удалось прочитать изображение",
        "add.custom.icon.error.duplicate": "Это имя уже занято — попробуйте другое.",
        "add.custom.icon.scope.failed": "Доступ к кастомным эмодзи не предоставлен",
        "download": "Скачать",
        "loading": "Загрузка...",
        "load.failed": "Не удалось загрузить",
        "history.load.previous": "Загрузить предыдущие",
        "date.yesterday": "'Вчера, ' HH:mm",

        // Errors / user-facing fallbacks
        "err.load.chats": "Ошибка загрузки чатов: %@",
        "err.load.messages": "Ошибка загрузки сообщений: %@",
        "err.load.previous": "Ошибка загрузки предыдущих сообщений: %@",
        "err.send": "Ошибка отправки: %@",
        "err.send.permission": "Не удалось отправить: пользователь должен подтвердить запрос на переписку.",
        "dm.request.pending": "Пользователь ещё не подтвердил запрос на переписку. Переписка станет доступна после подтверждения.",
        "err.create.chat": "Ошибка создания чата: %@",
        "err.open.chat": "Ошибка открытия личного чата: %@",
        "err.add.member": "Не удалось добавить участника: %@",
        "err.remove.member": "Не удалось удалить участника: %@",
        "err.remove.member.noData": "Не удалось удалить участника: нет данных о членстве",
        "err.leave.chat": "Не удалось покинуть чат: %@",
        "user.unknown": "Пользователь",
        "space.unnamed": "Без названия",
        "welcome.message": "Бобро поржаловать!",
        "welcome.space": "Приветствие",
        "membership.notFound": "Членство не найдено",
        "window.notFound": "Окно не найдено",
        "signin.noResult": "Результат отсутствует",

        // Archive export
        "general.ok": "OK",
        "export.menu": "Экспорт архива",
        "export.current": "Экспортировать чат в HTML",
        "export.all": "Экспортировать все чаты",
        "export.panel.title": "Куда сохранить экспорт архива",
        "export.choose": "Экспортировать сюда",
        "export.exporting": "Экспортируем архив…",
        "export.empty": "Экспортировать пока нечего — откройте чаты, чтобы они попали в архив",
        "export.doc.title": "Архив переписок — Google Chat",
        "export.doc.exported": "Экспортировано: %@",
        "export.doc.messages": "%@ сообщений",
        "export.doc.messages.updated": "Обновлено: %@",
        "export.doc.part": "Часть %@ из %@",
        "export.doc.prev": "Предыдущая часть",
        "export.doc.next": "Следующая часть",
        "export.doc.toc": "Оглавление",
        "export.doc.quote": "Цитата",
        "export.link.original": "Исходный файл",
        "export.missing": "не скачано",
    ]
}