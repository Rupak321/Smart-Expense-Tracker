import 'package:hive/hive.dart';

part 'user_profile_model.g.dart';

@HiveType(typeId: 1)
class UserProfileModel extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final String phoneNumber;

  @HiveField(2)
  final String address;

  @HiveField(3)
  final String email;

  @HiveField(4)
  final String occupation;

  @HiveField(5)
  final DateTime updatedAt;

  UserProfileModel({
    required this.name,
    required this.phoneNumber,
    required this.address,
    required this.email,
    required this.occupation,
    required this.updatedAt,
  });
}
