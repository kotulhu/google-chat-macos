# Google Chat Client (Unofficial)

A native macOS client for Google Chat, built with SwiftUI. This is an alternative to the official PWA, designed to be lightweight, fast, and fully compatible with the Google Chat REST API.

## Important Disclaimer

**This application is an independent, open-source project.** It is **not** affiliated with, endorsed by, or supported by Google Inc. All product names, logos, and brands are property of their respective owners.

## Features

- **Native macOS Experience:** Built with SwiftUI, notifications, drag & drop, and a native look & feel.

- **Chats & Spaces:**
  - View and manage all your chats; sort by recent activity.
  - **Pinned chats** keep important conversations on top.
  - Unread-message counters and a floating **"jump to first unread"** button.
  - Filter chats by name; create new chats and start direct messages from the sidebar.
  - **Member management** for groups: add/remove members and leave a chat.

- **Messaging:**
  - Send and receive text messages with inline images and files.
  - **Mentions** via `@` with autocomplete.
  - **Quoting:** quote any message (context menu) — the original is highlighted and scroll-to-origin is supported.
  - **Edit and delete** your own messages.
  - **Older history:** a "load previous messages" button at the top of the feed pages backwards through the entire conversation.

- **Reactions:**
  - Full reaction picker (Unicode 16.0, ~1900 emojis across 9 categories) with **search**.
  - Quick-reaction menu with recently used emojis; live counts and per-user lists.

- **Custom Emojis (optional, org-level):**
  - Add your own icons from the message context menu ("Add icon…"), including animated GIFs and WebP – resized/transcoded automatically.
  - Requires the **`chat.customemojis` scope** (Developer Preview), a Google Workspace domain and the feature enabled by the admin.

- **Local archive & HTML export:**
  - Messages of every chat you open are merged into a local archive (Application Support), together with downloaded attachments.
  - One-click **export** of the current chat or of *all* archived chats to a `index.html + attachments/` folder:
    - images inline (`<img>`), videos with an embedded player (`<video>`), other files as links;
    - detected URLs become clickable links, reactions and quotes are preserved;
    - very long histories are split into numbered parts (`part_2.html`, …) automatically;
    - works offline for everything already archived; missing attachments are fetched when online.

- **Notifications:** native macOS notifications for new messages (deduplicated), unread badge refresh in the background.

- **Direct-message polish:** pending DM request banner, email-resolution of display names, avatar images.

## Getting Started

> **Prerequisite:** a Google Chat API requires a **paid Google Workspace account** (for example the *Business Starter* plan). Standard free `@gmail.com` accounts won't work.
>
> For development you may be able to use a free demo domain via the Google Cloud Partner Advantage program.

### 1. Create a Google Cloud project

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and create a project.
2. Enable APIs under **APIs & Services → Library**: `Google Chat API` and `People API`.
3. Under **OAuth consent screen** choose **External** (or **Internal** for your own org) and add the scopes:

   | Scope | Purpose |
   | :--- | :--- |
   | `chat.spaces.readonly` | List chats |
   | `chat.spaces.create` | Create spaces |
   | `chat.messages.readonly` | Read messages |
   | `chat.messages` / `chat.messages.create` | Send, edit, delete messages |
   | `chat.messages.reactions` | Add / remove reactions |
   | `chat.memberships` | Manage members |
   | `chat.customemojis` | Upload custom emojis (optional, Developer Preview) |
   | `contacts.readonly` | Find users for mentions/DMs |
   | `directory.readonly` | Resolve user names in your org (optional) |
   | `userinfo.profile` / `userinfo.email` | Your own profile |

4. Under **Credentials → Create credentials → OAuth client ID** choose application type **macOS** and copy the **Client ID**.

### 2. Configure the client

Copy the local config template and paste your Client ID:

```bash
cp GoogleChat/Config/GoogleChat.example.xcconfig GoogleChat/Config/GoogleChat.local.xcconfig
# edit GoogleChat.local.xcconfig:
#   GOOGLE_CLIENT_ID = <your-client-id>.apps.googleusercontent.com
#   GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<your-client-id>
```

`GoogleChat.local.xcconfig` is **git-ignored** — never commit it. `Info.plist` bakes the reversed ID into the OAuth callback URL scheme at build time, so the local file must match the Client ID you sign in with. The Client ID can also be overridden later in the app's **Settings**.

### 3. Build & run

Open `GoogleChat.xcodeproj` in Xcode and run, or build from the command line:

```bash
xcodebuild -project GoogleChat.xcodeproj -scheme GoogleChat \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

(GOOGLE Chat's API is fetched over HTTPS; codesigning is only needed for released builds.)

## Privacy & Security

- OAuth tokens live in memory and the macOS keychain; they are **never stored in the repository**.
- The local archive (`~/Library/Application Support/Gogol Chat/Archive/`) stays on your machine unless you export it.
- The repository contains **no personal data or secrets** — real Client IDs live only in the ignored `GoogleChat.local.xcconfig`.

## Contributing

Contributions are welcome! If you have ideas for improvements or new features:

1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Acknowledgements

- Google for providing the Chat API.
- All contributors and users of this project.

---
**Disclaimer:**
**This software is provided "as is", without warranty of any kind.** The developers are not responsible for any data loss or other issues arising from its use. By using this software, you accept all risks associated with accessing your Google account. Use at your own risk.