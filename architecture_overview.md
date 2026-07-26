# SmartExpense Architecture Overview

## 1. Project Overview
A Flutter-based financial tracking application implementing Smart Expense Management with AI-powered insights and bill reminder functionality. Uses Firebase backend for authentication and storage.

## 2. Folder Structure
```
smart_expense/
├── lib/
│   ├── core/
│   │   ├── models/          # Data entities (ExpenseModel, UserProfileModel)
│   │   ├── services/          # Business logic and API clients
│   │   │   ├── auth_service.dart
│   │   │   └── bill_reminder_service.dart
│   │   ├── theme/             # Theme management
│   │   │   └── app_theme_controller.dart
│   │   ├── utils/             # Utility functions
│   │   └── widgets/           # Reusable UI components
│   │
│   ├── presentation/
│   │   └── screens/           # UI screens
│   │       ├── profile_screen.dart
│   │       ├── home_screen.dart
│   │       ├── analytics_screen.dart
│   │       ├── bill_reminder_screen.dart
│   │       └── ...            
│   │
│   ├── features/              # Feature-specific modules
│   │   ├── ai_expense/        # AI-powered expense analysis
│   │   └── ...               
│   │
│   └── firebase_options.dart    # Firebase configuration placeholder
│
├── test/
│   └── widget_test.dart       # Widget testing suite
│
└── pubspec.yaml               # Dependencies
```

## 3. Core Components
### 3.1 Models
- `expense_model.dart`: Represents individual expense records
- `user_profile_model.dart`: Date and profile management
- Generated `.g.dart` files: Type-safe code generation using build_runner

### 3.2 Services
- `auth_service.dart`: Firebase Authentication implementation
- `bill_reminder_service.dart`: manages recurring bill notifications
- `ai_expense_service.dart`: Uses Google Generative AI for expense analysis

### 3.3 Theme Management
- `app_theme_controller.dart`: Centralized theme state management

## 4. UI Architecture
### 4.1 Screen Structure
- Profile Screen
- Home Screen (main navigation hub)
- Analytics Screen
- Bill Reminder Screen
- AI Financial Assistant Screen
- Personal Details Screen

### 4.2 Widget System
- CustomCard component
- TransactionTile widget
- SummaryItem widget
- AddTransactionSheet dialog

## 5. Technology Stack
- Flutter 3.x with Dart 3
- Firebase Core for backend integration
- Cloud Firestore (implied) for data persistence
- Google Generative AI for AI-powered insights
- Hive for local storage
- Custom UI components following Material Design

## 6. Data Flow
User interactions trigger events in presentation layer → processed by services → update core models → display changes in UI
AI service consumes expense data → provides analysis via Generative AI → results displayed in analytics screens

## 7. Security Considerations
- `core/secrets.dart` manages sensitive configuration
- Firebase secrets placeholder in `firebase_options.dart`
- Hive database encryption enabled
- Input validation in service layer

## 8. Testing Approach
- Widget testing in `test/widget_test.dart`
- Service-level testing with mock Firebase implementations
- AI response validation through response parsing

## 9. Future Enhancements
- Additional AI features (expense categorization)
- Advanced analytics dashboards
- Cross-platform deployment improvements
- Enhanced security measures