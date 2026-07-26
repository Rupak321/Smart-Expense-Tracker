import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/user_profile_model.dart';
import '../../../core/utils/profile_image_storage.dart';
import '../../services/auth_service.dart';
import '../../services/user_data_service.dart';

class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _occupationController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSaving = false;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await UserDataService.profileStream().first;
    final user = AuthService.currentUser;
    if (!mounted) return;

    setState(() {
      _nameController.text = profile?.name.isNotEmpty == true
          ? profile!.name
          : user?.displayName ?? '';
      _phoneController.text = profile?.phoneNumber ?? '';
      _addressController.text = profile?.address ?? '';
      _emailController.text = profile?.email.isNotEmpty == true
          ? profile!.email
          : user?.email ?? '';
      _occupationController.text = profile?.occupation ?? '';
      _profileImagePath = profile?.profileImagePath ?? user?.photoURL;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      children: [
                        _ProfileAvatar(imagePath: _profileImagePath),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 17,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _PersonalDetailsField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_rounded,
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                _PersonalDetailsField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: _phoneValidator,
                ),
                const SizedBox(height: 12),
                _PersonalDetailsField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.mail_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailValidator,
                ),
                const SizedBox(height: 12),
                _PersonalDetailsField(
                  controller: _occupationController,
                  label: 'Occupation',
                  icon: Icons.work_rounded,
                ),
                const SizedBox(height: 12),
                _PersonalDetailsField(
                  controller: _addressController,
                  label: 'Address',
                  icon: Icons.location_on_rounded,
                  minLines: 2,
                  maxLines: 3,
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveProfile,
                  icon: Icon(
                    _isSaving ? Icons.hourglass_top_rounded : Icons.save_rounded,
                  ),
                  label: Text(_isSaving ? 'Saving...' : 'Save Details'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickProfileImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked == null) {
      return;
    }

    final savedPath = await ProfileImageStorage.savePickedImage(picked.path);
    if (mounted) {
      setState(() => _profileImagePath = savedPath);
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    final profile = UserProfileModel(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      email: _emailController.text.trim(),
      occupation: _occupationController.text.trim(),
      updatedAt: DateTime.now(),
      profileImagePath: _profileImagePath,
    );

    try {
      await UserDataService.saveProfile(profile);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personal details saved')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^[0-9+\-\s]{7,16}$').hasMatch(trimmed)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? imagePath;

  const _ProfileAvatar({this.imagePath});

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final isNetwork = imagePath?.startsWith('http') == true;
    final hasLocalImage = !isNetwork && imagePath != null && File(imagePath!).existsSync();

    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        image: hasImage && (isNetwork || hasLocalImage)
            ? DecorationImage(
                image: isNetwork
                    ? NetworkImage(imagePath!) as ImageProvider
                    : FileImage(File(imagePath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasImage && (isNetwork || hasLocalImage)
          ? null
          : Icon(
              Icons.person_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 44,
            ),
    );
  }
}

class _PersonalDetailsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final String? Function(String? value)? validator;

  const _PersonalDetailsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }
}
