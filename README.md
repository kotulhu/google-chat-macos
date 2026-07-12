# Google Chat Client (Unofficial)

A native macOS client for Google Chat, built with SwiftUI. This is an alternative to the official PWA, designed to be lightweight, fast, and fully compatible with the Google Chat API.

## Important Disclaimer

**This application is an independent, open-source project.** It is **not** affiliated with, endorsed by, or supported by Google Inc. All product names, logos, and brands are property of their respective owners.

## Features

-   **Native macOS Experience:** Built with SwiftUI for a seamless, fast, and responsive experience.
-   **Full Chat Functionality:**
    -   View and manage all your chats (Spaces).
    -   Send and receive messages.
    -   **Mentions:** Use `@` to mention users in a chat.
    -   **Direct Messages:** Click on any user's name to start a direct chat.
-   **Media & Files:**
    -   Send and receive images and files.
    -   Inline image previews.
-   **Notifications:**
    -   Native macOS notifications for new messages.
    -   Unread message counter.
-   **Theming (Planned):** Choose your own fonts, colors, and bubble styles.
-   **Future-Ready:** The architecture is designed for planned features like emoji reactions, message scheduling, and custom chat sorting.

## Getting Started

Follow these steps to get your own instance of the client up and running.

### Prerequisites

**1. A Paid Google Workspace Account**

**This is the most critical requirement.** The Google Chat API is **not** available for standard free Gmail accounts (`@gmail.com`). You will need a Google Workspace subscription to use this client. The minimum plan is **Business Starter** (~$6 per user/month with annual commitment).

> **Note:** For developers, you may be able to request a free demo domain through the Google Cloud Partner Advantage program to use for testing. These domains often include `dev.`, `demo.`, or `test.`.

**2. Enable Required APIs & Create Credentials**

You will need to create a Google Cloud project and enable the necessary APIs to get a `Client ID`.

**Step-by-Step Setup:**

1.  **Create a Project:**
    *   Go to the [Google Cloud Console](https://console.cloud.google.com/).
    *   Create a new project or select an existing one.

2.  **Enable Required APIs:**
    *   Navigate to **APIs & Services** → **Library**.
    *   Search for and **enable** the following APIs:
        *   `Google Chat API`
        *   `People API`

3.  **Configure the OAuth Consent Screen:**
    *   Go to **APIs & Services** → **OAuth consent screen**.
    *   Choose **External** (or **Internal** if your app is only for your organization).
    *   Fill in the required fields (App name, support email, etc.).
    *   On the **Scopes** page, add the following permissions (scopes):

        | Scope | Purpose |
        | :--- | :--- |
        | `.../auth/chat.spaces.readonly` | View list of chats |
        | `.../auth/chat.messages.readonly` | Read messages |
        | `.../auth/chat.messages.create` | Send messages |
        | `.../auth/chat.spaces.create` | Create new spaces |
        | `.../auth/contacts.readonly` | Search for users (for mentions) |
        | `.../auth/userinfo.profile` | Get your profile info |
        | `.../auth/chat.memberships.readonly` | View space members |

4.  **Create OAuth 2.0 Credentials:**
    *   Go to **APIs & Services** → **Credentials**.
    *   Click **+ CREATE CREDENTIALS** and select **OAuth client ID**.
    *   Choose **Application type** → **macOS**.
    *   Give it a name (e.g., `Google Chat Client`).
    *   Click **Create** and copy the **Client ID** that appears.

### Installing and Configuring the Client

1.  **Download the latest release** from the [Releases] https://github.com/kotulhu/google-chat-macos page.
2.  Move the app to your `Applications` folder.
3.  **First Launch:** When you open the app for the first time, it will prompt you to enter your **Client ID**.
4.  **Enter the Client ID:** Paste the `Client ID` you copied from the Google Cloud Console into the settings field and save it.
5.  **Sign In:** Click the "Sign in with Google" button to authenticate.

That's it! The client will now load your chats.

## Contributing

Contributions are welcome! If you have ideas for improvements or new features, feel free to:

1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.

## License

Distributed under the MIT License. See `LICENSE.txt` for more information.

## Acknowledgements

-   Google for providing the Chat API.
-   All contributors and users of this project.

---
**Disclaimer:**
**This software is provided "as is", without warranty of any kind.** The developers are not responsible for any data loss or other issues arising from its use. By using this software, you accept all risks associated with accessing your Google account. Use at your own risk.
