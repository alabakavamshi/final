import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/screens/auth_page.dart';
import 'package:game_app/organiser_pages/manage_players_page.dart';
import 'package:game_app/screens/play_page.dart' show PlayPage;
import 'package:game_app/screens/player_profile.dart';
import 'package:game_app/organiser_pages/schedule_page.dart';
import 'package:game_app/tournaments/history_page.dart';
import 'package:game_app/tournaments/tournament_details_page.dart';
import 'package:game_app/tournaments/tournamnet_create.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';

// Extension for string capitalization
extension StringExtension on String {
  String capitalize() {
    return isNotEmpty ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}' : this;
  }
}

class OrganizerHomePage extends StatefulWidget {
  final bool showLocationDialog;
  final bool returnToPlayPage;

  const OrganizerHomePage({
    super.key,
    this.showLocationDialog = false,
    this.returnToPlayPage = false,
  });

  @override
  State<OrganizerHomePage> createState() => _OrganizerHomePageState();
}

class _OrganizerHomePageState extends State<OrganizerHomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _location = 'Hyderabad, India';
  String _userCity = '';
  bool _isLoadingLocation = false;
  final TextEditingController _locationController = TextEditingController();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  bool _locationFetchCompleted = false;
  bool _shouldReturnToPlayPage = false;
  bool _hasNavigated = false;
  bool _showToast = false;
  String? _toastMessage;
  ToastificationType? _toastType;
  List<Map<String, dynamic>> _upcomingTournaments = [];
  List<Map<String, dynamic>> _recentActivities = [];
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0D1B2A),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    _initializeAnimations();
    _shouldReturnToPlayPage = widget.returnToPlayPage;
    _initializeUserData();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .get();
        if (userDoc.exists && userDoc.data()?['city']?.toString().isNotEmpty == true) {
          if (mounted) {
            setState(() {
              _userCity = userDoc.data()!['city'].toString().toLowerCase();
              _location = '${StringExtension(_userCity).capitalize()}, India';
              _locationFetchCompleted = true;
              _isLoadingLocation = false;
            });
          }
          if (widget.showLocationDialog) {
            _showLocationSearchDialog();
          }
        } else {
          if (!kIsWeb) {
            await _getUserLocation();
          } else {
            if (mounted) {
              setState(() {
                _location = 'Hyderabad, India';
                _userCity = 'hyderabad';
                _locationFetchCompleted = true;
                _isLoadingLocation = false;
              });
            }
            _showLocationSearchDialog();
          }
        }
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOutQuint),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _animationController?.forward();
  }

  Future<void> _initializeUserData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(authState.user.uid);
    final userDoc = await userDocRef.get();

    final defaultUser = {
      'createdAt': Timestamp.now(),
      'displayName': authState.user.email?.split('@')[0] ?? 'Organizer',
      'email': authState.user.email ?? '',
      'firstName': 'Organizer',
      'lastName': '',
      'gender': 'unknown',
      'phone': '',
      'profileImage': '',
      'city': _userCity.isNotEmpty ? _userCity : 'hyderabad',
      'updatedAt': Timestamp.now(),
    };

    if (!userDoc.exists) {
      await userDocRef.set(defaultUser);
      if (mounted) {
        setState(() => _userData = defaultUser);
      }
    } else {
      if (mounted) {
        setState(() => _userData = userDoc.data() ?? defaultUser);
      }
    }
  }

  Stream<Map<String, dynamic>?> _userDataStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Stream.value(null);
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(authState.user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  Stream<List<Map<String, dynamic>>> _upcomingTournamentsStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('tournaments')
        .where('createdBy', isEqualTo: authState.user.uid)
        .where('endDate', isGreaterThanOrEqualTo: Timestamp.now())
        .orderBy('startDate', descending: false)
        .limit(5)
        .snapshots()
        .map((querySnapshot) {
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        final startTimeData = data['startTime'] as Map<String, dynamic>? ?? {'hour': 0, 'minute': 0};
        return {
          'id': doc.id,
          'name': data['name']?.toString() ?? 'Unnamed Tournament',
          'startDate': data['startDate'] ?? Timestamp.now(),
          'endDate': data['endDate'] ?? Timestamp.now(),
          'startTime': TimeOfDay(
            hour: startTimeData['hour'] as int? ?? 0,
            minute: startTimeData['minute'] as int? ?? 0,
          ),
          'location': (data['venue']?.toString().isNotEmpty == true &&
                  data['city']?.toString().isNotEmpty == true)
              ? '${data['venue']}, ${data['city']}'
              : 'Unknown',
          'status': data['status']?.toString() ?? 'open',
          'participantCount': (data['participants'] as List?)?.length ?? 0,
          'entryFee': (data['entryFee'] as num?)?.toDouble() ?? 0.0,
          'maxParticipants': data['maxParticipants']?.toInt() ?? 0,
          'createdBy': data['createdBy']?.toString() ?? '',
        };
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> _recentActivitiesStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('organizer_activities')
        .doc(authState.user.uid)
        .collection('activities')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots()
        .map((querySnapshot) {
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'type': data['type']?.toString() ?? 'activity',
          'message': data['message']?.toString() ?? 'Organizer activity',
          'timestamp': data['timestamp'] ?? Timestamp.now(),
          'tournamentId': data['tournamentId']?.toString(),
        };
      }).toList();
    });
  }

  @override
  void dispose() {
    _locationController.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
        _locationFetchCompleted = false;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
            _showToast = true;
            _toastMessage = 'Location services disabled';
            _toastType = ToastificationType.warning;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _location = 'Hyderabad, India';
              _userCity = 'hyderabad';
              _showToast = true;
              _toastMessage = 'Location permission denied';
              _toastType = ToastificationType.error;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
            _showToast = true;
            _toastMessage = 'Location permission denied forever';
            _toastType = ToastificationType.error;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          _location = placemarks.isNotEmpty ? '${placemarks.first.locality ?? 'Hyderabad'}, India' : 'Hyderabad, India';
          _userCity = placemarks.isNotEmpty ? placemarks.first.locality?.toLowerCase() ?? 'hyderabad' : 'hyderabad';
        });
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }

      if (_shouldReturnToPlayPage && mounted) {
        setState(() {
          _selectedIndex = 2;
          _shouldReturnToPlayPage = false;
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Failed to fetch location';
          _toastType = ToastificationType.error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationFetchCompleted = true;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Please enter a location';
          _toastType = ToastificationType.error;
        });
      }
      return;
    }

    try {
      final locations = await locationFromAddress(query).timeout(const Duration(seconds: 5));
      if (locations.isEmpty) {
        throw Exception('No locations found');
      }

      final location = locations.first;
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude)
          .timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          _location = placemarks.isNotEmpty ? '${placemarks.first.locality ?? 'Hyderabad'}, India' : 'Hyderabad, India';
          _userCity = placemarks.isNotEmpty ? placemarks.first.locality?.toLowerCase() ?? 'hyderabad' : 'hyderabad';
        });
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authState.user.uid)
            .update({'city': _userCity});
      }

      if (mounted) {
        setState(() {
          _showToast = true;
          _toastMessage = 'Location updated to $_location';
          _toastType = ToastificationType.success;
        });
      }

      if (_shouldReturnToPlayPage && mounted) {
        setState(() {
          _selectedIndex = 2;
          _shouldReturnToPlayPage = false;
        });
      }
    } catch (e) {
      debugPrint('Search location error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Failed to find location';
          _toastType = ToastificationType.error;
        });
      }
    }
  }

  void _onItemTapped(int index) {
    if (index < 0 || index >= 4) {
      debugPrint('Invalid index: $index');
      return;
    }
    if (mounted) {
      setState(() => _selectedIndex = index);
    }
    debugPrint('Selected tab: $index');
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D1B2A), Color(0xFF1A1A1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.cyan.withOpacity(0.7), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Confirm Logout',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to logout?',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      backgroundColor: Colors.white.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Logout',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _userDataStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _userData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading user data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        _userData = snapshot.data ?? _userData;
        if (_userData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final displayName = _userData!['firstName']?.toString().isNotEmpty == true
            ? '${StringExtension(_userData!['firstName'].toString()).capitalize()} ${_userData!['lastName']?.toString().isNotEmpty == true ? StringExtension(_userData!['lastName'].toString()).capitalize() : ''}'
            : 'Organizer';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A506B), Color(0xFF1C2541)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back,',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _upcomingTournamentsStream(),
                      builder: (context, tournamentsSnapshot) {
                        if (tournamentsSnapshot.hasData) {
                          _upcomingTournaments = tournamentsSnapshot.data!;
                        }
                        return Row(
                          children: [
                            const Icon(Icons.emoji_events, size: 16, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              '${_upcomingTournaments.length} Upcoming Tournaments',
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedIndex = 3),
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white10,
                  backgroundImage: _userData!['profileImage']?.toString().isNotEmpty == true
                      ? CachedNetworkImageProvider(_userData!['profileImage'])
                      : const AssetImage('assets/default_profile.png') as ImageProvider,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingTournaments() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _upcomingTournamentsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading tournaments',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        _upcomingTournaments = snapshot.data ?? [];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Tournaments',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.amber),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_upcomingTournaments.isEmpty)
                Column(
                  children: [
                    Text(
                      'No upcoming tournaments created yet',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Create Tournament',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              else
                ..._upcomingTournaments.map((tournament) {
                  final startDate = (tournament['startDate'] as Timestamp).toDate();
                  final endDate = (tournament['endDate'] as Timestamp).toDate();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _getTournamentStatusColor(tournament['status']),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Start Date',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('MMM').format(startDate).toUpperCase(),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('dd').format(startDate),
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tournament['name'],
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 14, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        tournament['location'],
                                        style: GoogleFonts.poppins(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Entry: ₹${tournament['entryFee'].toStringAsFixed(0)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getTournamentStatusColor(tournament['status']),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'End Date',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('MMM').format(endDate).toUpperCase(),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('dd').format(endDate),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getTournamentStatusColor(tournament['status']).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tournament['status'].toUpperCase(),
                                style: GoogleFonts.poppins(
                                  color: _getTournamentStatusColor(tournament['status']),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final tournamentDoc = await FirebaseFirestore.instance
                                    .collection('tournaments')
                                    .doc(tournament['id'])
                                    .get();
                                final tournamentData = tournamentDoc.data();
                                if (tournamentData != null) {
                                  final tournament = Tournament.fromFirestore(tournamentData, tournamentDoc.id);
                                  final creatorDoc = await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(tournament.createdBy)
                                      .get();
                                  final creatorName = creatorDoc.data()?['firstName']?.toString().isNotEmpty == true
                                      ? '${StringExtension(creatorDoc.data()!['firstName'].toString()).capitalize()} ${creatorDoc.data()!['lastName']?.toString().isNotEmpty == true ? StringExtension(creatorDoc.data()!['lastName'].toString()).capitalize() : ''}'
                                      : 'Organizer';
                                  if (mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TournamentDetailsPage(
                                          tournament: tournament,
                                          creatorName: creatorName,
                                        ),
                                      ),
                                    );
                                  }
                                } else if (mounted) {
                                  setState(() {
                                    _showToast = true;
                                    _toastMessage = 'Tournament not found';
                                    _toastType = ToastificationType.error;
                                  });
                                }
                              },
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              child: Text(
                                'Manage >',
                                style: GoogleFonts.poppins(
                                  color: Colors.blueAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Color _getTournamentStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blueAccent;
      case 'ongoing':
        return Colors.greenAccent;
      case 'completed':
        return Colors.purpleAccent;
      case 'cancelled':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRecentActivities() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _recentActivitiesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading recent activities',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        _recentActivities = snapshot.data ?? [];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activities',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.history, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 12),
              if (_recentActivities.isEmpty)
                Text(
                  'No recent activities found',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                )
              else
                ..._recentActivities.map((activity) {
                  final timestamp = (activity['timestamp'] as Timestamp).toDate();
                  final tournamentId = activity['tournamentId'] as String?;
                  return GestureDetector(
                    onTap: tournamentId != null
                        ? () async {
                            final tournamentDoc = await FirebaseFirestore.instance
                                .collection('tournaments')
                                .doc(tournamentId)
                                .get();
                            final tournamentData = tournamentDoc.data();
                            if (tournamentData != null && mounted) {
                              final tournament = Tournament.fromFirestore(tournamentData, tournamentDoc.id);
                              final creatorDoc = await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(tournament.createdBy)
                                  .get();
                              final creatorName = creatorDoc.data()?['firstName']?.toString().isNotEmpty == true
                                  ? '${StringExtension(creatorDoc.data()!['firstName'].toString()).capitalize()} ${creatorDoc.data()!['lastName']?.toString().isNotEmpty == true ? StringExtension(creatorDoc.data()!['lastName'].toString()).capitalize() : ''}'
                                  : 'Organizer';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TournamentDetailsPage(
                                    tournament: tournament,
                                    creatorName: creatorName,
                                  ),
                                ),
                              );
                            } else if (mounted) {
                              setState(() {
                                _showToast = true;
                                _toastMessage = 'Tournament not found';
                                _toastType = ToastificationType.error;
                              });
                            }
                          }
                        : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getActivityColor(activity['type']),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getActivityIcon(activity['type']),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity['message'],
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  DateFormat('MMM dd, hh:mm a').format(timestamp),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'tournament_created':
        return Colors.blueAccent.withOpacity(0.2);
      case 'player_registered':
        return Colors.amber.withOpacity(0.2);
      case 'match_completed':
        return Colors.greenAccent.withOpacity(0.2);
      default:
        return Colors.purpleAccent.withOpacity(0.2);
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'tournament_created':
        return Icons.add_box;
      case 'player_registered':
        return Icons.person_add;
      case 'match_completed':
        return Icons.sports_score;
      default:
        return Icons.notifications;
    }
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQuickActionButton(
                icon: Icons.history,
                label: 'Tournament History',
                color: Colors.purpleAccent,
                onTap: () async {
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TournamentHistoryPage(userId: authState.user.uid),
                      ),
                    );
                  }
                },
              ),
              _buildQuickActionButton(
                icon: Icons.people,
                label: 'Manage Players',
                color: Colors.greenAccent,
                onTap: () async {
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManagePlayersPage(userId: authState.user.uid),
                      ),
                    );
                  }
                },
              ),
              _buildQuickActionButton(
                icon: Icons.schedule,
                label: 'Schedule',
                color: Colors.amber,
                onTap: () async {
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SchedulePage(userId: authState.user.uid),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showLocationSearchDialog() {
    _locationController.clear();
    _animationController?.forward();

    showDialog(
      context: context,
      builder: (context) {
        Widget dialogContent = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1B263B),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Location',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      Navigator.pop(context);
                      if (_shouldReturnToPlayPage && mounted) {
                        setState(() {
                          _selectedIndex = 2;
                          _shouldReturnToPlayPage = false;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _getUserLocation();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Use Current Location',
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                      ),
                      const Spacer(),
                      if (_isLoadingLocation)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.2), height: 1),
              const SizedBox(height: 16),
              Text(
                'Or search for a location',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                style: GoogleFonts.poppins(color: Colors.white),
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: 'Enter city name',
                  hintStyle: GoogleFonts.poppins(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        if (_shouldReturnToPlayPage && mounted) {
                          setState(() {
                            _selectedIndex = 2;
                            _shouldReturnToPlayPage = false;
                          });
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_locationController.text.isNotEmpty) {
                          _searchLocation(_locationController.text);
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Search',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (_scaleAnimation != null && _fadeAnimation != null) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: ScaleTransition(
              scale: _scaleAnimation!,
              child: FadeTransition(
                opacity: _fadeAnimation!,
                child: dialogContent,
              ),
            ),
          );
        }
        return Dialog(backgroundColor: Colors.transparent, child: dialogContent);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showToast && _toastMessage != null && _toastType != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastification.show(
          context: context,
          type: _toastType!,
          title: Text(
            _toastType == ToastificationType.success
                ? 'Success'
                : _toastType == ToastificationType.error
                    ? 'Error'
                    : 'Info',
          ),
          description: Text(_toastMessage!),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: _toastType == ToastificationType.success
              ? Colors.green
              : _toastType == ToastificationType.error
                  ? Colors.red
                  : Colors.blue,
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
        if (mounted) {
          setState(() {
            _showToast = false;
            _toastMessage = null;
            _toastType = null;
          });
        }
      });
    }

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated && !_hasNavigated && mounted) {
          _hasNavigated = true;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (route) => false,
          );
        } else if (state is AuthError && mounted) {
          setState(() {
            _showToast = true;
            _toastMessage = state.message;
            _toastType = ToastificationType.error;
          });
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthUnauthenticated) {
            return const AuthPage();
          }

          if (state is AuthLoading) {
            return const Scaffold(
              backgroundColor: Color(0xFF0D1B2A),
              body: Center(child: CircularProgressIndicator(color: Colors.white)),
            );
          }

          final List<Widget> pages = [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildWelcomeCard(),
                  _buildQuickActions(),
                  _buildUpcomingTournaments(),
                  _buildRecentActivities(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            state is AuthAuthenticated
                ? CreateTournamentPage(
                    userId: state.user.uid,
                    onBackPressed: () => setState(() => _selectedIndex = 0),
                    onTournamentCreated: () {
                      if (mounted) {
                        setState(() {
                          _selectedIndex = 2;
                        });
                      }
                    },
                  )
                : const Center(child: CircularProgressIndicator(color: Colors.white)),
            PlayPage(userCity: _userCity, key: ValueKey(_userCity)),
            const PlayerProfilePage(),
          ];

          return WillPopScope(
            onWillPop: () async {
              if (_selectedIndex != 0) {
                setState(() => _selectedIndex = 0);
                return false;
              }
              return true;
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0D1B2A),
              appBar: _selectedIndex != 3
                  ? AppBar(
                      elevation: 0,
                      toolbarHeight: 80,
                      flexibleSpace: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF3A506B), Color(0xFF1C2541)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SmashLive',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _showLocationSearchDialog,
                            child: Row(
                              children: [
                                const Icon(Icons.location_pin, color: Colors.white70, size: 18),
                                const SizedBox(width: 8),
                                _isLoadingLocation && !_locationFetchCompleted
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                        ),
                                      )
                                    : Flexible(
                                        child: Text(
                                          _location,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white70),
                          onPressed: () async {
                            final shouldLogout = await _showLogoutConfirmationDialog();
                            if (shouldLogout == true && mounted) {
                              context.read<AuthBloc>().add(AuthLogoutEvent());
                            }
                          },
                        ),
                      ],
                    )
                  : null,
              body: pages[_selectedIndex],
              bottomNavigationBar: BottomNavigationBar(
                backgroundColor: const Color(0xFF2A324B),
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white.withOpacity(0.6),
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                type: BottomNavigationBarType.fixed,
                selectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                unselectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_filled),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.add_circle_outline),
                    activeIcon: Icon(Icons.add_circle),
                    label: 'Create',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.sports_tennis_outlined),
                    activeIcon: Icon(Icons.sports_tennis),
                    label: 'Matches',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}