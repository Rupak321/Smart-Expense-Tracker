import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/models/bill_reminder.dart';
import 'user_settings_service.dart';

class BillReminderService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kathmandu'));

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  static Future<List<BillReminder>> getReminders() async {
    final reminders = await UserSettingsService.getBillRemindersOnce();
    reminders.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return reminders;
  }

  static Future<void> saveReminder(BillReminder reminder) async {
    await UserSettingsService.saveBillReminder(reminder);
    await scheduleReminder(reminder);
  }

  static Future<void> deleteReminder(String id) async {
    await UserSettingsService.deleteBillReminder(id);
    await _notifications.cancel(_notificationId(id));
  }

  static Future<void> rescheduleAll() async {
    await initialize();
    final reminders = await getReminders();
    for (final reminder in reminders) {
      await scheduleReminder(reminder);
    }
  }

  static Future<void> scheduleReminder(BillReminder reminder) async {
    await initialize();
    await _notifications.cancel(_notificationId(reminder.id));

    if (!reminder.enabled) {
      return;
    }

    final scheduledAt = _scheduledTime(reminder);
    if (scheduledAt == null) {
      return;
    }

    await _notifications.zonedSchedule(
      _notificationId(reminder.id),
      'Bill Reminder',
      _notificationBody(reminder),
      scheduledAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bill_reminders',
          'Bill Reminders',
          channelDescription: 'Alerts for upcoming bills and payments',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
    );
  }


  static tz.TZDateTime? _scheduledTime(BillReminder reminder) {
    final remindDate = reminder.dueDate.subtract(
      Duration(days: reminder.remindDaysBefore),
    );
    final scheduledAt = tz.TZDateTime(
      tz.local,
      remindDate.year,
      remindDate.month,
      remindDate.day,
      9,
    );

    if (scheduledAt.isBefore(tz.TZDateTime.now(tz.local))) {
      return null;
    }
    return scheduledAt;
  }

  static String _notificationBody(BillReminder reminder) {
    final title = reminder.title.trim().isEmpty ? 'bill' : reminder.title.trim();
    if (reminder.remindDaysBefore == 0) {
      return 'Your $title is due today.';
    }
    if (reminder.remindDaysBefore == 1) {
      return 'Your $title is due tomorrow.';
    }
    return 'Your $title is due in ${reminder.remindDaysBefore} days.';
  }

  static int _notificationId(String id) {
    return id.codeUnits.fold(0, (value, code) {
      return (value * 31 + code) & 0x7fffffff;
    });
  }
}
