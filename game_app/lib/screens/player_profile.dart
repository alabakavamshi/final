import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/user_model.dart';
import 'package:game_app/screens/auth_page.dart';
import 'package:game_app/screens/hosted_tournaments_page.dart';
import 'package:game_app/screens/joined_tournaments.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:toastification/toastification.dart';

class PlayerProfilePage extends StatefulWidget {
  const PlayerProfilePage({super.key});

  @override
  State<PlayerProfilePage> createState() => _PlayerProfilePageState();
}

class _PlayerProfilePageState extends State<PlayerProfilePage> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();

  final List<String> _genderOptions = ['Male', 'Female', 'Other'];
  final Map<String, bool> _isEditing = {
    'firstName': false,
    'lastName': false,
    'email': false,
    'phone': false,
    'gender': false,
  };
  final Map<String, bool> _isChecking = {
    'email': false,
    'phone': false,
    'gender': false,
  };

  String? _profileImageUrl;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        context.read<AuthBloc>().add(AuthRefreshProfileEvent(user.uid));
      }
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  String _normalizePhoneNumber(String phone) {
    phone = phone.trim();
    if (!phone.startsWith('+91')) return '+91$phone';
    return phone;
  }

  Future<void> _pickAndSetProfileImage(String uid) async {
    final List<String> sketchOptions = [
      'assets/sketch1.jpg',
      'assets/sketch2.jpeg',
      'assets/sketch3.jpeg',
      'assets/sketch4.jpeg',
    ];

    setState(() => _isUploadingImage = true);
    debugPrint('Starting image selection process');

    try {
      final selectedSketch = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1B263B),
          title: Text('Select Profile Image', style: GoogleFonts.poppins(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: sketchOptions.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => Navigator.pop(context, sketchOptions[index]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(sketchOptions[index], fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ),
      );

      if (selectedSketch != null) {
        debugPrint('Selected sketch: $selectedSketch');

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'profileImage': selectedSketch});

        if (mounted) setState(() => _profileImageUrl = selectedSketch);
        context.read<AuthBloc>().add(AuthRefreshProfileEvent(uid));
        _showToast('Profile image updated successfully', ToastificationType.success);
      }
    } catch (e) {
      debugPrint('Image selection error: $e');
      _showToast('Failed to update profile image: ${e.toString()}', ToastificationType.error);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
      debugPrint('Image selection process ended');
    }
  }

  Future<void> _saveField(String field, String value, String uid, String? currentValue) async {
    try {
      if (value.trim().isEmpty) {
        _showToast('Field cannot be empty', ToastificationType.error);
        return;
      }

      if (field == 'phone') value = _normalizePhoneNumber(value);

      setState(() => _isChecking[field] = true);
      debugPrint('Saving $field: $value for UID: $uid');

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        field: value.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (field == 'email') {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != value.trim()) {
          await user.updateEmail(value.trim());
          await user.sendEmailVerification();
          _showToast('Email updated. Verification email sent.', ToastificationType.info);
        }
      }

      setState(() {
        _isEditing[field] = false;
        _isChecking[field] = false;
      });
      context.read<AuthBloc>().add(AuthRefreshProfileEvent(uid));
      _showToast('$field updated successfully', ToastificationType.success);
    } catch (e) {
      debugPrint('Save field error: $e');
      setState(() => _isChecking[field] = false);
      _showToast('Failed to update $field: ${e.toString()}', ToastificationType.error);
    }
  }

  Future<void> _deleteAccount(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Re-authenticate the user to perform the delete operation
        final credential = await _showReauthenticationDialog();
        if (credential == null) {
          _showToast('Re-authentication required to delete account', ToastificationType.error);
          return;
        }

        await user.reauthenticateWithCredential(credential);
        
        // Delete from Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
        // Delete from Firebase Authentication
        await user.delete();
        // Logout and navigate to AuthPage
        context.read<AuthBloc>().add(AuthLogoutEvent());
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthPage()),
          (route) => false,
        );
        _showToast('Account deleted successfully', ToastificationType.success);
      }
    } catch (e) {
      debugPrint('Delete account error: $e');
      _showToast('Failed to delete account: ${e.toString()}', ToastificationType.error);
    }
  }

  Future<AuthCredential?> _showReauthenticationDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return showDialog<AuthCredential>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        title: Text('Re-authenticate', style: GoogleFonts.poppins(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: GoogleFonts.poppins(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: GoogleFonts.poppins(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              obscureText: true,
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              try {
                final email = emailController.text.trim();
                final password = passwordController.text.trim();
                if (email.isEmpty || password.isEmpty) {
                  _showToast('Email and password are required', ToastificationType.error);
                  return;
                }
                final credential = EmailAuthProvider.credential(email: email, password: password);
                Navigator.pop(context, credential);
              } catch (e) {
                _showToast('Re-authentication failed: ${e.toString()}', ToastificationType.error);
              }
            },
            child: Text('Submit', style: GoogleFonts.poppins(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  void _showToast(String message, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
    );
  }

  void _showLogoutConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        title: Text('Confirm Logout', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to logout?', style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              context.read<AuthBloc>().add(AuthLogoutEvent());
              Navigator.pop(context);
              _showToast('Logged out successfully', ToastificationType.success);
            },
            child: Text('Logout', style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirmationDialog(String uid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        title: Text('Confirm Delete Account', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to delete your account? This action cannot be undone.', style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount(uid);
            },
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(User user, AppUser appUser) {
    final displayName = "${appUser.firstName} ${appUser.lastName}".trim();
    final role = appUser.role;

    return Column(
      children: [
        GestureDetector(
          onTap: _isUploadingImage ? null : () => _pickAndSetProfileImage(user.uid),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFF415A77), Color(0xFF778DA9)]),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
              _isUploadingImage
                  ? const CircularProgressIndicator(color: Colors.white)
                  : ClipOval(
                      child: _profileImageUrl != null
                          ? Image.asset(
                              _profileImageUrl!,
                              width: 108,
                              height: 108,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Image.asset(
                                'assets/logo.png',
                                width: 108,
                                height: 108,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Image.asset(
                              'assets/logo.png',
                              width: 108,
                              height: 108,
                              fit: BoxFit.cover,
                            ),
                    ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _isUploadingImage ? null : () => _pickAndSetProfileImage(user.uid),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF3F51B5),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        Text(
          role,
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String fieldKey,
    required String uid,
    required String? currentValue,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final isEditing = _isEditing[fieldKey] ?? false;
    final isChecking = _isChecking[fieldKey] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  enabled: isEditing,
                  keyboardType: keyboardType,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    prefixIcon: Icon(icon, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              debugPrint('Tapped edit/save for $fieldKey, isEditing: $isEditing');
              if (mounted) {
                setState(() {
                  if (isEditing) {
                    _saveField(fieldKey, controller.text, uid, currentValue);
                  } else {
                    _isEditing[fieldKey] = true; // Set to true to start editing
                    controller.text = currentValue ?? '';
                  }
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                isEditing ? Icons.check : Icons.edit,
                color: isEditing ? Colors.white : Colors.white70,
                size: 24,
              ),
            ),
          ),
          if (isChecking)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenderField({
    required TextEditingController controller,
    required String fieldKey,
    required String uid,
    required String currentValue,
  }) {
    final isEditing = _isEditing[fieldKey] ?? false;
    final isChecking = _isChecking[fieldKey] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gender',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _genderOptions.contains(controller.text) ? controller.text : _genderOptions[0],
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                    ),
                  ),
                  dropdownColor: const Color(0xFF1B263B),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                  items: _genderOptions.map((gender) {
                    return DropdownMenuItem<String>(
                      value: gender,
                      child: Text(gender),
                    );
                  }).toList(),
                  onChanged: isEditing ? (value) {
                    if (value != null) {
                      setState(() => controller.text = value);
                    }
                  } : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              debugPrint('Tapped edit/save for $fieldKey, isEditing: $isEditing');
              if (mounted) {
                setState(() {
                  if (isEditing) {
                    _saveField(fieldKey, controller.text, uid, currentValue);
                  } else {
                    _isEditing[fieldKey] = true; // Set to true to start editing
                    controller.text = currentValue;
                  }
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                isEditing ? Icons.check : Icons.edit,
                color: isEditing ? Colors.white : Colors.white70,
                size: 24,
              ),
            ),
          ),
          if (isChecking)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.white.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (route) => false,
          );
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthInitial || state is AuthLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFF0B132B),
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }

          if (state is AuthAuthenticated) {
            final user = state.user;
            final appUser = state.appUser;

            if (_firstNameController.text.isEmpty) {
              _firstNameController.text = appUser!.firstName;
              _lastNameController.text = appUser.lastName;
              _emailController.text = appUser.email ?? user.email ?? '';
              _phoneController.text = appUser.phone ?? user.phoneNumber ?? '';
              _genderController.text = appUser.gender ?? _genderOptions[0];
              _profileImageUrl = appUser.profileImage ?? 'assets/logo.png';
            }

            return Scaffold(
              backgroundColor: const Color(0xFF0B132B),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildProfileHeader(user, appUser!),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            _buildEditableField(
                              label: 'First Name',
                              controller: _firstNameController,
                              icon: Icons.person,
                              fieldKey: 'firstName',
                              uid: user.uid,
                              currentValue: appUser.firstName,
                            ),
                            _buildEditableField(
                              label: 'Last Name',
                              controller: _lastNameController,
                              icon: Icons.person,
                              fieldKey: 'lastName',
                              uid: user.uid,
                              currentValue: appUser.lastName,
                            ),
                            _buildEditableField(
                              label: 'Email',
                              controller: _emailController,
                              icon: Icons.email,
                              fieldKey: 'email',
                              uid: user.uid,
                              currentValue: appUser.email ?? user.email,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            _buildEditableField(
                              label: 'Phone',
                              controller: _phoneController,
                              icon: Icons.phone,
                              fieldKey: 'phone',
                              uid: user.uid,
                              currentValue: appUser.phone ?? user.phoneNumber,
                              keyboardType: TextInputType.phone,
                            ),
                            _buildGenderField(
                              controller: _genderController,
                              fieldKey: 'gender',
                              uid: user.uid,
                              currentValue: appUser.gender ?? _genderOptions[0],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (appUser.role == 'organizer')
                        _buildActionButton(
                          icon: Icons.tour,
                          label: 'Hosted Tournaments',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HostedTournamentsPage(userId: user.uid),
                            ),
                          ),
                          color: const Color(0xFF6A1B9A),
                        ),
                      if (appUser.role == 'player')
                        _buildActionButton(
                          icon: Icons.event,
                          label: 'Joined Tournaments',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => JoinedTournamentsPage(userId: user.uid),
                            ),
                          ),
                          color: const Color(0xFF2E7D32),
                        ),
                      if (appUser.role == 'umpire')
                        _buildActionButton(
                          icon: Icons.gavel,
                          label: 'Umpired Matches',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UmpiredMatchesPage(userId: user.uid),
                            ),
                          ),
                          color: const Color(0xFF0288D1),
                        ),
                      _buildActionButton(
                        icon: Icons.lock_reset,
                        label: 'Reset Password',
                        onTap: () {
                          final email = appUser.email ?? user.email ?? '';
                          if (email.isNotEmpty) {
                            FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                            _showToast('Password reset email sent', ToastificationType.success);
                          } else {
                            _showToast('No email available for password reset', ToastificationType.error);
                          }
                        },
                        color: const Color(0xFFEF6C00),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: ElevatedButton(
                            onPressed: _showLogoutConfirmationDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Log Out',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: ElevatedButton(
                            onPressed: () => _showDeleteAccountConfirmationDialog(user.uid),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFAD1457),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Delete Account',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return const Scaffold(
            backgroundColor: Color(0xFF0B132B),
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        },
      ),
    );
  }
}

// New Page: UmpiredMatchesPage
class UmpiredMatchesPage extends StatefulWidget {
  final String userId;

  const UmpiredMatchesPage({super.key, required this.userId});

  @override
  State<UmpiredMatchesPage> createState() => _UmpiredMatchesPageState();
}

class _UmpiredMatchesPageState extends State<UmpiredMatchesPage> {
  late Stream<QuerySnapshot> _matchesStream;

  @override
  void initState() {
    super.initState();
    _matchesStream = FirebaseFirestore.instance
        .collection('tournaments')
        .where('umpire.email', isEqualTo: FirebaseAuth.instance.currentUser?.email)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Umpired Matches',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _matchesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading matches',
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No umpired matches found',
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    );
                  }

                  final matches = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final match = data['matches'] as List<dynamic>? ?? [];
                    return match.where((m) => m['umpire']['email'] == FirebaseAuth.instance.currentUser?.email).toList();
                  }).expand((x) => x).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final match = matches[index] as Map<String, dynamic>;
                      final team1 = match['team1'] ?? match['player1'] ?? 'Unknown';
                      final team2 = match['team2'] ?? match['player2'] ?? 'Unknown';
                      final isCompleted = match['completed'] ?? false;
                      final winner = match['winner'] ?? 'Not decided';

                      return Card(
                        color: Colors.white.withOpacity(0.1),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          title: Text(
                            '$team1 vs $team2',
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status: ${isCompleted ? 'Completed' : 'Ongoing'}',
                                style: GoogleFonts.poppins(color: Colors.cyanAccent),
                              ),
                              if (isCompleted)
                                Text(
                                  'Winner: $winner',
                                  style: GoogleFonts.poppins(color: Colors.greenAccent),
                                ),
                            ],
                          ),
                          trailing: Icon(
                            Icons.gavel,
                            color: Colors.white70,
                            size: 24,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}