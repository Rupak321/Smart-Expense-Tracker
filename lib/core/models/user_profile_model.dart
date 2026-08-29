class UserProfileModel {
  final String name;
  final String phoneNumber;
  final String address;
  final String email;
  final String occupation;
  final DateTime updatedAt;
  final String? profileImagePath;

  UserProfileModel({
    required this.name,
    required this.phoneNumber,
    required this.address,
    required this.email,
    required this.occupation,
    required this.updatedAt,
    this.profileImagePath,
  });
}
