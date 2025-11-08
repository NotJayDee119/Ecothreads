import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class EditProfilePage extends StatefulWidget {
  final String username;
  final String bio;
  final String email;
  final String portfolio;
  final String location;
  final bool showEcoImpact;
  final String? avatarUrl;

  const EditProfilePage({
    super.key,
    required this.username,
    required this.bio,
    required this.email,
    required this.portfolio,
    required this.location,
    required this.showEcoImpact,
    this.avatarUrl,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final supabase = Supabase.instance.client;
  late TextEditingController usernameController;
  late TextEditingController bioController;
  late TextEditingController emailController;
  late TextEditingController portfolioController;
  late TextEditingController locationController;
  late bool showEcoImpact;
  bool _saving = false;
  bool _uploading = false;
  XFile? _pickedImage;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.username);
    bioController = TextEditingController(text: widget.bio);
    emailController = TextEditingController(text: widget.email);
    portfolioController = TextEditingController(text: widget.portfolio);
    locationController = TextEditingController(text: widget.location);
    showEcoImpact = widget.showEcoImpact;
    _avatarUrl = widget.avatarUrl;
  }

  @override
  void dispose() {
    usernameController.dispose();
    bioController.dispose();
    emailController.dispose();
    portfolioController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      
      if (picked != null) {
        setState(() {
          _pickedImage = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<String?> _uploadAvatar() async {
    if (_pickedImage == null) return _avatarUrl;

    setState(() => _uploading = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final fileExt = _pickedImage!.path.split('.').last;
      final fileName = 'avatar_$userId.${fileExt}';
      final bytes = await _pickedImage!.readAsBytes();

      // Delete old avatar if exists
      if (_avatarUrl != null) {
        try {
          final oldFileName = _avatarUrl!.split('/').last;
          await supabase.storage.from('avatars').remove([oldFileName]);
        } catch (e) {
          // Ignore error if file doesn't exist
        }
      }

      // Upload new avatar
      await supabase.storage.from('avatars').uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      // Get public URL
      final url = supabase.storage.from('avatars').getPublicUrl(fileName);
      
      setState(() => _uploading = false);
      return url;
    } catch (e) {
      setState(() => _uploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading avatar: $e')),
        );
      }
      return _avatarUrl;
    }
  }

  Future<void> _saveProfile() async {
    if (usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // Upload avatar if changed
      final avatarUrl = await _uploadAvatar();

      // Update user metadata in Supabase auth
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'name': usernameController.text.trim(),
            'bio': bioController.text.trim(),
            'portfolio': portfolioController.text.trim(),
            'location': locationController.text.trim(),
            'showEcoImpact': showEcoImpact,
            'avatar_url': avatarUrl,
          },
        ),
      );

      // Update all existing posts with the new name
      await supabase
          .from('posts')
          .update({
            'user_name': usernameController.text.trim(),
            'user_avatar': avatarUrl,
          })
          .eq('user_id', supabase.auth.currentUser!.id);

      if (mounted) {
        Navigator.pop(context, {
          "username": usernameController.text.trim(),
          "bio": bioController.text.trim(),
          "email": emailController.text.trim(),
          "portfolio": portfolioController.text.trim(),
          "location": locationController.text.trim(),
          "showEcoImpact": showEcoImpact,
          "avatar_url": avatarUrl,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Edit Profile",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveProfile,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    "Save",
                    style: TextStyle(color: Colors.green, fontSize: 16),
                  ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.green[100],
                  backgroundImage: _pickedImage != null
                      ? (kIsWeb
                          ? NetworkImage(_pickedImage!.path)
                          : FileImage(File(_pickedImage!.path)) as ImageProvider)
                      : (_avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? NetworkImage(_avatarUrl!)
                          : null),
                  child: (_pickedImage == null && (_avatarUrl == null || _avatarUrl!.isEmpty))
                      ? Text(
                          usernameController.text.isNotEmpty
                              ? usernameController.text[0].toUpperCase()
                              : 'E',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _uploading ? null : _pickImage,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.green,
                      child: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _uploading ? null : _pickImage,
              child: Text(
                _pickedImage != null
                    ? "Change Photo"
                    : (_avatarUrl != null && _avatarUrl!.isNotEmpty
                        ? "Change Photo"
                        : "Add Profile Picture"),
                style: const TextStyle(color: Colors.green),
              ),
            ),
            const SizedBox(height: 20),

            // Username
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
                helperText: "This name will appear on all your posts",
              ),
            ),
            const SizedBox(height: 16),

            // Bio
            TextField(
              controller: bioController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Bio",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Email (Read-only)
            TextField(
              controller: emailController,
              enabled: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.email),
                labelText: "Email",
                border: OutlineInputBorder(),
                helperText: "Email cannot be changed",
              ),
            ),
            const SizedBox(height: 16),

            // Portfolio
            TextField(
              controller: portfolioController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.link),
                labelText: "Portfolio/GitHub",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Location
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on),
                labelText: "Location",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Switch
            SwitchListTile(
              title: const Text("Show Eco Impact"),
              value: showEcoImpact,
              onChanged: (val) {
                setState(() {
                  showEcoImpact = val;
                });
              },
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}
