import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:game_app/blocs/auth/auth_bloc.dart';
import 'package:game_app/blocs/auth/auth_event.dart';
import 'package:game_app/blocs/auth/auth_state.dart';
import 'package:game_app/screens/auth_page.dart';
import 'package:game_app/screens/play_page.dart';
import 'package:game_app/screens/player_profile.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PlayerHomePage extends StatefulWidget {
  const PlayerHomePage({super.key});

  @override
  State<PlayerHomePage> createState() => _PlayerHomePageState();
}

class _PlayerHomePageState extends State<PlayerHomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _location = 'Fetching location...';
  String _userCity = 'Hyderabad';
  bool _isLoadingLocation = false;
  bool _locationFetchCompleted = false;
  Position? _lastPosition;
  final TextEditingController _locationController = TextEditingController();
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;
  Animation<double>? _fadeAnimation;
  bool _showToast = false;
  String? _toastMessage;
  ToastificationType? _toastType;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    // Defer location fetching to after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchUserCity();
      _getUserLocation();
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

  @override
  void dispose() {
    _locationController.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _fetchUserCity() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      if (mounted) {
        setState(() {
          _userCity = 'Hyderabad';
          _location = 'Hyderabad, India';
        });
      }
      return;
    }

    final userId = authState.user.uid;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data();
      if (mounted) {
        setState(() {
          _userCity = userData?['city']?.toString().toLowerCase() ?? 'hyderabad';
          _location = '$_userCity, India';
        });
      }
      debugPrint('Fetched user city: $_userCity');
    } catch (e) {
      debugPrint('Error fetching user city: $e');
      if (mounted) {
        setState(() {
          _userCity = 'hyderabad';
          _location = 'Hyderabad, India';
        });
      }
    }
  }

  Future<void> _getUserLocation() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationFetchCompleted = false;
    });

    try {
      if (_lastPosition == null) {
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _lastPosition = lastPosition;
          await _updateLocationFromPosition(lastPosition);
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationServiceDisabled();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _handlePermissionDenied();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _handlePermissionDeniedForever();
        return;
      }

      Position? position;
      bool success = false;
      int attempts = 0;
      const int maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        attempts++;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          success = true;
        } on TimeoutException {
          if (attempts == maxAttempts) {
            throw TimeoutException('Location fetch timed out after $maxAttempts attempts');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (position != null) {
        _lastPosition = position;
        await _updateLocationFromPosition(position);
      } else {
        throw Exception('Failed to get location after $maxAttempts attempts');
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
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
    } on TimeoutException {
      _handleLocationTimeout();
    } catch (e) {
      _handleLocationError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationFetchCompleted = true;
        });
      }
    }
  }

  Future<void> _updateLocationFromPosition(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        if (mounted) {
          setState(() {
            _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
            _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
          });
        }
        return;
      }

      final fallbackPlacemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 3));

      if (fallbackPlacemarks.isNotEmpty) {
        final place = fallbackPlacemarks.first;
        if (mounted) {
          setState(() {
            _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
            _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _location = 'Hyderabad, India';
            _userCity = 'hyderabad';
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      if (mounted) {
        setState(() {
          _location = 'Hyderabad, India';
          _userCity = 'hyderabad';
        });
      }
    }
  }

  Future<void> _handleLocationServiceDisabled() async {
    if (!mounted) return;

    final opened = await Geolocator.openLocationSettings();
    if (opened) {
      await Future.delayed(const Duration(seconds: 2));
      await _getUserLocation();
    } else {
      if (mounted) {
        setState(() {
          _location = 'Location services disabled. Using default: Hyderabad.';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Please enable location services manually.';
          _toastType = ToastificationType.warning;
        });
      }
    }
  }

  void _handlePermissionDenied() {
    if (!mounted) return;
    _showPermissionDeniedDialog();
  }

  void _handlePermissionDeniedForever() {
    if (!mounted) return;
    _showPermissionDeniedForeverDialog();
  }

  void _handleLocationTimeout() {
    if (mounted) {
      setState(() {
        _location = 'Location timeout. Using ${_userCity.isNotEmpty ? _userCity : 'Hyderabad'}.';
        _userCity = _userCity.isNotEmpty ? _userCity : 'hyderabad';
        _showToast = true;
        _toastMessage = 'Could not fetch location quickly. Using last known location.';
        _toastType = ToastificationType.warning;
      });
    }
  }

  void _handleLocationError(dynamic e) {
    debugPrint('Location error: $e');
    if (mounted) {
      setState(() {
        _location = 'Failed to fetch location. Using ${_userCity.isNotEmpty ? _userCity : 'Hyderabad'}.';
        _userCity = _userCity.isNotEmpty ? _userCity : 'hyderabad';
        _showToast = true;
        _toastMessage = 'Failed to fetch location: ${e.toString()}. Using default city: Hyderabad.';
        _toastType = ToastificationType.error;
      });
    }
  }

  Future<void> _getUserLocationFromCurrent() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = true;
      _locationFetchCompleted = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _handleLocationServiceDisabled();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDeniedDialog();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showPermissionDeniedForeverDialog();
        return;
      }

      Position? position;
      bool success = false;
      int attempts = 0;
      const int maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        attempts++;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          success = true;
        } on TimeoutException {
          if (attempts == maxAttempts) {
            throw TimeoutException('Location fetch timed out after $maxAttempts attempts');
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (position != null) {
        _lastPosition = position;
        await _updateLocationFromPosition(position);
      } else {
        throw Exception('Failed to get location after $maxAttempts attempts');
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
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
    } on TimeoutException {
      _handleLocationTimeout();
    } catch (e) {
      _handleLocationError(e);
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
        throw Exception('No locations found for "$query"');
      }

      final location = locations.first;
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 3));

      if (placemarks.isEmpty) {
        throw Exception('No placemarks found');
      }

      final place = placemarks.first;
      if (mounted) {
        setState(() {
          _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
          _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
        });
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated && mounted) {
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
    } catch (e) {
      debugPrint('Search location error: $e');
      if (mounted) {
        setState(() {
          _location = 'Failed to find location. Using default: Hyderabad.';
          _userCity = 'hyderabad';
          _showToast = true;
          _toastMessage = 'Failed to find location: ${e.toString()}. Using default city: Hyderabad.';
          _toastType = ToastificationType.error;
        });
      }
    }
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
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _getUserLocationFromCurrent();
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
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                        ),
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
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
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
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Search',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
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
        return Dialog(
          backgroundColor: Colors.transparent,
          child: dialogContent,
        );
      },
    );
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This app needs location permission to fetch your current location. Please enable it in settings.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text('Enable', style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedForeverDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Location Permission Denied Forever',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Location permission has been permanently denied. You can enable it in app settings.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            child: Text('Enable', style: GoogleFonts.poppins(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ScaleTransition(
          scale: _scaleAnimation!,
          child: FadeTransition(
            opacity: _fadeAnimation!,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D1B2A), Color(0xFF1A1A1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withOpacity(0.7),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: Offset(0, 5),
                  ),
                ],
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
                      shadows: [
                        Shadow(
                          color: const Color(0xFF00D4FF).withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showToast && _toastMessage != null && _toastType != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        toastification.show(
          context: context,
          type: _toastType!,
          title: Text(_toastType == ToastificationType.success
              ? 'Success'
              : _toastType == ToastificationType.error
                  ? 'Error'
                  : 'Info'),
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
        debugPrint('PlayerHomePage Auth state: $state');
        if (state is AuthUnauthenticated && mounted && !_hasNavigated) {
          _hasNavigated = true;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (route) => false,
          );
          debugPrint('Navigated to AuthPage due to unauthenticated state');
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
          debugPrint('Building PlayerHomePage with state: $state');
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
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (state is AuthAuthenticated) ...[
                    Text(
                      'Welcome, ${state.user.displayName ?? state.user.email?.split('@')[0] ?? 'Player'}',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Player Dashboard',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PlayPage(userCity: _userCity),
            const PlayerProfilePage(),
          ];

          return WillPopScope(
            onWillPop: () async {
              if (_selectedIndex != 0) {
                if (mounted) {
                  setState(() {
                    _selectedIndex = 0; // Navigate to Home page
                  });
                }
                return false; // Prevent app from exiting
              }
              return true; // Allow exit if on Home page
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0D1B2A),
              appBar: AppBar(
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
                      'Badminton Blitz',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _showLocationSearchDialog,
                      child: Row(
                        children: [
                          Icon(Icons.location_pin, color: Colors.white70, size: 18),
                          const SizedBox(width: 8),
                          _isLoadingLocation && !_locationFetchCompleted
                              ? SizedBox(
                                  width: 100,
                                  height: 20,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
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
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        state is AuthAuthenticated ? Icons.logout : Icons.login,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: () async {
                      if (state is AuthAuthenticated && mounted) {
                        final shouldLogout = await _showLogoutConfirmationDialog();
                        if (shouldLogout == true) {
                          context.read<AuthBloc>().add(AuthLogoutEvent());
                          setState(() {
                            _showToast = true;
                            _toastMessage = 'You have been logged out successfully.';
                            _toastType = ToastificationType.success;
                          });
                          debugPrint('User logged out');
                        }
                      } else if (mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthPage()),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ],
              ),
              body: pages[_selectedIndex],
              bottomNavigationBar: BottomNavigationBar(
                backgroundColor: const Color(0xFF1B263B),
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
                    icon: Icon(Icons.play_arrow_outlined),
                    activeIcon: Icon(Icons.play_arrow),
                    label: 'Play',
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