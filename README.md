# Smart Expense Tracker

A modern, intelligent personal finance management app built with Flutter. Smart Expense Tracker helps you effortlessly track your income, expenses, and overall financial health while offering AI-powered insights to help you save more and spend smarter.

## Features

- **Transaction Tracking**: Easily log your daily expenses and income with an intuitive UI.
- **Categorization**: Organize your spending into categories like Food, Travel, Bills, Shopping, and more.
- **Rich Analytics**: Visual breakdowns, donut charts, and spending trends to understand your financial habits.
- **AI Financial Assistant**: Ask questions and get brutally honest, actionable financial advice powered by advanced AI models.
- **Bill Reminders**: Never miss a due date with local push notifications.
- **Cloud Sync**: Securely store and sync your financial data using Firebase Auth and Firestore.
- **Modern UI/UX**: A beautiful, responsive, and fully themed interface that supports both Dark and Light modes.

## Tech Stack

- **Framework**: [Flutter](https://flutter.dev/)
- **Backend & Database**: [Firebase](https://firebase.google.com/) (Authentication, Cloud Firestore)
- **AI Integration**: Groq API (`llama-3.1-8b-instant`) / Google Generative AI
- **Notifications**: `flutter_local_notifications`

## Getting Started

### Prerequisites
- Flutter SDK (v3.12.0 or higher)
- Android Studio or VS Code
- A valid Groq API key for the AI Financial Assistant (optional but recommended for full functionality)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/smartexpense.git
   ```

2. Navigate to the project directory:
   ```bash
   cd smartexpense
   ```

3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

## Configuration

The AI Financial Assistant needs a Groq API key. The key is a **compile-time**
define, so it is baked into the binary when you build — a build without it can
never reach the API, whatever you change at runtime.

Create `dart_defines.json` in the project root (it is gitignored, so it will
not be committed):

```json
{
  "GROQ_API_KEY": "gsk_your_key_here",
  "GROQ_MODEL": "openai/gpt-oss-20b"
}
```

Then run or build with it:

```bash
flutter run --dart-define-from-file=dart_defines.json
flutter build apk --release --dart-define-from-file=dart_defines.json
```

Everything except the assistant's replies works without a key: transactions,
analytics, reminders, and the locally computed month briefing on the assistant
screen are all plain Dart over your own data.

### Models

Groq retires models periodically, and a retired model returns an error rather
than falling back. `llama-3.1-8b-instant` and `llama-3.3-70b-versatile` shut
down on **16 August 2026**; the default is now `openai/gpt-oss-20b`. Check
<https://console.groq.com/docs/deprecations> if the assistant starts reporting
that its model is unavailable, and set a current one via `GROQ_MODEL`.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License.
