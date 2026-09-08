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

        // About
        "version.format": "Версия %@ (сборка %@)",
        "developer": "Разработчик",
        "contact": "Контакт",
        "unofficial.client.note": "Неофициальный клиент Google Chat для macOS",

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
        "settings.oauth.note": "OAuth Client ID используется при входе. Reversed Client ID должен совпадать с GOOGLE_REVERSED_CLIENT_ID в локальном GoogleChat.local.xcconfig, потому что macOS регистрирует callback из Info.plist при сборке приложения.",

        // Reaction picker
        "reaction.picker.title": "Выбор реакции",
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
        "more.reactions": "Другие реакции...",
        "download": "Скачать",
        "loading": "Загрузка...",
        "load.failed": "Не удалось загрузить",
        "date.yesterday": "'Вчера, ' HH:mm",

        // Errors / user-facing fallbacks
        "err.load.chats": "Ошибка загрузки чатов: %@",
        "err.load.messages": "Ошибка загрузки сообщений: %@",
        "err.send": "Ошибка отправки: %@",
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
    ]
}