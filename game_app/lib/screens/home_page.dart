
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:game_app/blocs/auth/auth_bloc.dart';
// import 'package:game_app/blocs/auth/auth_event.dart';
// import 'package:game_app/blocs/auth/auth_state.dart';
// import 'package:game_app/screens/auth_page.dart';
// import 'package:game_app/screens/player_profile.dart';
// import 'package:game_app/screens/play_page.dart';
// import 'package:game_app/screens/tournamnet_create.dart';
// import 'package:google_fonts/google_fonts.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:toastification/toastification.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';

// class HomePage extends StatefulWidget {
//   final bool showLocationDialog;
//   final bool returnToPlayPage;

//   const HomePage({
//     super.key,
//     this.showLocationDialog = false,
//     this.returnToPlayPage = false,
//   });

//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
//   int _selectedIndex = 0;
//   String _location = 'Fetching location...';
//   String _userCity = 'Hyderabad';
//   bool _isLoadingLocation = false;
//   Position? _lastPosition;
//   final TextEditingController _locationController = TextEditingController();
//   AnimationController? _animationController;
//   Animation<double>? _scaleAnimation;
//   Animation<double>? _fadeAnimation;
//   bool _locationFetchCompleted = false;
//   final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
//   DateTime? _lastBackPressedTime;
//   bool _shouldReturnToPlayPage = false;

//   // State variables for deferred toast messages
//   bool _showToast = false;
//   String? _toastMessage;
//   ToastificationType? _toastType;

//   // Placeholder images
//   final String matchImage = 'assets/match.jpeg';
//   final String courtImage = 'assets/court.jpeg';
//   final String tournamentImage = 'assets/tournament.jpeg';
//   final String profileImage = 'assets/sketch1.jpg';
//   final String appLogo = 'assets/images/logo.png';

//   @override
//   void initState() {
//     super.initState();
//     SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
//       statusBarColor: Color(0xFF0D1B2A),
//       statusBarIconBrightness: Brightness.light,
//       statusBarBrightness: Brightness.dark,
//     ));
//     _initializeAnimations();

//     _shouldReturnToPlayPage = widget.returnToPlayPage;

//     // Defer location fetching and dialog to after the first frame
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!widget.showLocationDialog) {
//         _getUserLocation();
//       } else {
//         if (mounted) {
//           setState(() {
//             _location = _userCity.isNotEmpty ? '$_userCity, India' : 'Hyderabad, India';
//             _locationFetchCompleted = true;
//             _isLoadingLocation = false;
//           });
//           _showLocationSearchDialog();
//         }
//       }
//     });
//   }

//   void _initializeAnimations() {
//     _animationController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 500),
//     );
//     _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
//       CurvedAnimation(parent: _animationController!, curve: Curves.easeOutQuint),
//     );
//     _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
//     );
//     _animationController?.forward();
//   }

//   @override
//   void dispose() {
//     _locationController.dispose();
//     _animationController?.dispose();
//     super.dispose();
//   }

//   Future<bool> _onWillPop() async {
//     if (_selectedIndex != 0) {
//       if (mounted) {
//         setState(() => _selectedIndex = 0);
//       }
//       return false;
//     }

//     final now = DateTime.now();
//     final shouldExit = _lastBackPressedTime == null ||
//         now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

//     if (shouldExit) {
//       _lastBackPressedTime = now;
//       if (mounted) {
//         setState(() {
//           _showToast = true;
//           _toastMessage = 'Press back again to exit';
//           _toastType = ToastificationType.info;
//         });
//       }
//       return false;
//     }
//     return true;
//   }

//   Future<bool?> _showLogoutConfirmationDialog(BuildContext context) {
//     return showDialog<bool>(
//       context: context,
//       builder: (context) => Dialog(
//         backgroundColor: Colors.transparent,
//         child: Container(
//           padding: const EdgeInsets.all(24),
//           decoration: BoxDecoration(
//             gradient: const LinearGradient(
//               colors: [Color(0xFF0D1B2A), Color(0xFF1A1A1A)],
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//             ),
//             borderRadius: BorderRadius.circular(20),
//             border: Border.all(
//               color: const Color(0xFF00D4FF).withOpacity(0.7),
//               width: 2,
//             ),
//             boxShadow: [
//               BoxShadow(
//                 color: const Color(0xFF00D4FF).withOpacity(0.3),
//                 blurRadius: 15,
//                 spreadRadius: 5,
//               ),
//               const BoxShadow(
//                 color: Colors.black54,
//                 blurRadius: 10,
//                 spreadRadius: 2,
//                 offset: Offset(0, 5),
//               ),
//             ],
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text(
//                 'Confirm Logout',
//                 style: GoogleFonts.poppins(
//                   color: Colors.white,
//                   fontWeight: FontWeight.bold,
//                   fontSize: 18,
//                   shadows: [
//                     Shadow(
//                       color: const Color(0xFF00D4FF).withOpacity(0.5),
//                       blurRadius: 10,
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Text(
//                 'Are you sure you want to logout?',
//                 style: GoogleFonts.poppins(
//                   color: Colors.white70,
//                   fontSize: 14,
//                 ),
//               ),
//               const SizedBox(height: 24),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.end,
//                 children: [
//                   TextButton(
//                     onPressed: () => Navigator.pop(context, false),
//                     style: TextButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//                       backgroundColor: Colors.white.withOpacity(0.1),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                     ),
//                     child: Text(
//                       'Cancel',
//                       style: GoogleFonts.poppins(
//                         color: Colors.white,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   ElevatedButton(
//                     onPressed: () => Navigator.pop(context, true),
//                     style: ElevatedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//                       backgroundColor: Colors.red,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                     ),
//                     child: Text(
//                       'Logout',
//                       style: GoogleFonts.poppins(
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Future<void> _getUserLocation() async {
//     if (!mounted) return;
//     setState(() {
//       _isLoadingLocation = true;
//       _locationFetchCompleted = false;
//     });

//     try {
//       if (_lastPosition == null) {
//         final lastPosition = await Geolocator.getLastKnownPosition();
//         if (lastPosition != null) {
//           _lastPosition = lastPosition;
//           await _updateLocationFromPosition(lastPosition);
//           return;
//         }
//       }

//       final serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         _handleLocationServiceDisabled();
//         return;
//       }

//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           _handlePermissionDenied();
//           return;
//         }
//       }

//       if (permission == LocationPermission.deniedForever) {
//         _handlePermissionDeniedForever();
//         return;
//       }

//       Position? position;
//       bool success = false;
//       int attempts = 0;
//       const int maxAttempts = 3;

//       while (!success && attempts < maxAttempts) {
//         attempts++;
//         try {
//           position = await Geolocator.getCurrentPosition(
//             desiredAccuracy: LocationAccuracy.medium,
//             timeLimit: const Duration(seconds: 10),
//           );
//           success = true;
//         } on TimeoutException {
//           if (attempts == maxAttempts) {
//             throw TimeoutException('Location fetch timed out after $maxAttempts attempts');
//           }
//           await Future.delayed(const Duration(seconds: 1));
//         }
//       }

//       if (position != null) {
//         _lastPosition = position;
//         await _updateLocationFromPosition(position);
//       } else {
//         throw Exception('Failed to get location after $maxAttempts attempts');
//       }

//       final authState = context.read<AuthBloc>().state;
//       if (authState is AuthAuthenticated && mounted) {
//         final collection = await _getUserCollection(authState.user.uid);
//         if (collection != null) {
//           await FirebaseFirestore.instance
//               .collection(collection)
//               .doc(authState.user.uid)
//               .update({'city': _userCity});
//         }
//       }

//       if (mounted) {
//         setState(() {
//           _showToast = true;
//           _toastMessage = 'Location updated to $_location';
//           _toastType = ToastificationType.success;
//         });
//       }

//       if (_shouldReturnToPlayPage && mounted) {
//         setState(() {
//           _selectedIndex = 1;
//           _shouldReturnToPlayPage = false;
//         });
//       }
//     } on TimeoutException {
//       _handleLocationTimeout();
//     } catch (e) {
//       _handleLocationError(e);
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoadingLocation = false;
//           _locationFetchCompleted = true;
//         });
//       }
//     }
//   }

//   Future<String?> _getUserCollection(String uid) async {
//     try {
//       final collections = ['participants', 'organizers', 'officials'];
//       for (final collection in collections) {
//         final doc = await FirebaseFirestore.instance.collection(collection).doc(uid).get();
//         if (doc.exists) {
//           return collection;
//         }
//       }
//       return null;
//     } catch (e) {
//       print('Error getting user collection: $e');
//       return null;
//     }
//   }

//   Future<void> _updateLocationFromPosition(Position position) async {
//     try {
//       final placemarks = await placemarkFromCoordinates(
//         position.latitude,
//         position.longitude,
//       ).timeout(const Duration(seconds: 5));

//       if (placemarks.isNotEmpty) {
//         final place = placemarks.first;
//         if (mounted) {
//           setState(() {
//             _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
//             _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
//           });
//         }
//         return;
//       }

//       final fallbackPlacemarks = await placemarkFromCoordinates(
//         position.latitude,
//         position.longitude,
//       ).timeout(const Duration(seconds: 3));

//       if (fallbackPlacemarks.isNotEmpty) {
//         final place = fallbackPlacemarks.first;
//         if (mounted) {
//           setState(() {
//             _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
//             _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
//           });
//         }
//       } else {
//         if (mounted) {
//           setState(() {
//             _location = 'Hyderabad, India';
//             _userCity = 'hyderabad';
//           });
//         }
//       }
//     } catch (e) {
//       print('Geocoding error: $e');
//       if (mounted) {
//         setState(() {
//           _location = 'Hyderabad, India';
//           _userCity = 'hyderabad';
//         });
//       }
//     }
//   }

//   void _handleLocationServiceDisabled() {
//     if (mounted) {
//       setState(() {
//         _location = 'Location services disabled. Using default: Hyderabad.';
//         _userCity = 'hyderabad';
//         _showToast = true;
//         _toastMessage = 'Please enable location services or select a city manually.';
//         _toastType = ToastificationType.warning;
//       });
//     }
//     Geolocator.openLocationSettings();
//   }

//   void _handlePermissionDenied() {
//     if (mounted) {
//       setState(() {
//         _location = 'Location permission denied. Using default: Hyderabad.';
//         _userCity = 'hyderabad';
//         _showToast = true;
//         _toastMessage = 'Location permission denied. Using default city: Hyderabad.';
//         _toastType = ToastificationType.error;
//       });
//     }
//   }

//   void _handlePermissionDeniedForever() {
//     if (mounted) {
//       setState(() {
//         _location = 'Location permission denied forever. Using default: Hyderabad.';
//         _userCity = 'hyderabad';
//         _showToast = true;
//         _toastMessage = 'Location permission denied forever. Using default city: Hyderabad.';
//         _toastType = ToastificationType.error;
//       });
//     }
//     Geolocator.openAppSettings();
//   }

//   void _handleLocationTimeout() {
//     if (mounted) {
//       setState(() {
//         _location = 'Location timeout. Using ${_userCity.isNotEmpty ? _userCity : 'Hyderabad'}.';
//         _userCity = _userCity.isNotEmpty ? _userCity : 'hyderabad';
//         _showToast = true;
//         _toastMessage = 'Could not fetch location quickly. Using last known location.';
//         _toastType = ToastificationType.warning;
//       });
//     }
//   }

//   void _handleLocationError(dynamic e) {
//     print('Location error: $e');
//     if (mounted) {
//       setState(() {
//         _location = 'Failed to fetch location. Using ${_userCity.isNotEmpty ? _userCity : 'Hyderabad'}.';
//         _userCity = _userCity.isNotEmpty ? _userCity : 'hyderabad';
//         _showToast = true;
//         _toastMessage = 'Failed to fetch location: ${e.toString()}. Using default city: Hyderabad.';
//         _toastType = ToastificationType.error;
//       });
//     }
//   }

//   Future<void> _searchLocation(String query) async {
//     if (query.isEmpty) {
//       if (mounted) {
//         setState(() {
//           _showToast = true;
//           _toastMessage = 'Please enter a location';
//           _toastType = ToastificationType.error;
//         });
//       }
//       return;
//     }

//     try {
//       final locations = await locationFromAddress(query).timeout(const Duration(seconds: 5));

//       if (locations.isEmpty) {
//         throw Exception('No locations found for "$query"');
//       }

//       final location = locations.first;
//       final placemarks = await placemarkFromCoordinates(
//         location.latitude,
//         location.longitude,
//       ).timeout(const Duration(seconds: 3));

//       if (placemarks.isEmpty) {
//         throw Exception('No placemarks found');
//       }

//       final place = placemarks.first;
//       if (mounted) {
//         setState(() {
//           _location = '${place.locality ?? 'Unknown'}, ${place.country ?? 'Unknown'}';
//           _userCity = place.locality?.toLowerCase() ?? 'hyderabad';
//         });
//       }

//       final authState = context.read<AuthBloc>().state;
//       if (authState is AuthAuthenticated && mounted) {
//         final collection = await _getUserCollection(authState.user.uid);
//         if (collection != null) {
//           await FirebaseFirestore.instance
//               .collection(collection)
//               .doc(authState.user.uid)
//               .update({'city': _userCity});
//         }
//       }

//       if (mounted) {
//         setState(() {
//           _showToast = true;
//           _toastMessage = 'Location updated to $_location';
//           _toastType = ToastificationType.success;
//         });
//       }

//       if (_shouldReturnToPlayPage && mounted) {
//         setState(() {
//           _selectedIndex = 1;
//           _shouldReturnToPlayPage = false;
//         });
//       }
//     } catch (e) {
//       print('Search location error: $e');
//       if (mounted) {
//         setState(() {
//           _location = 'Failed to find location. Using default: Hyderabad.';
//           _userCity = 'hyderabad';
//           _showToast = true;
//           _toastMessage = 'Failed to find location: ${e.toString()}. Using default city: Hyderabad.';
//           _toastType = ToastificationType.error;
//         });
//       }
//     }
//   }

//   void _showLocationSearchDialog() {
//     _locationController.clear();
//     _animationController?.forward();

//     showDialog(
//       context: context,
//       builder: (context) {
//         Widget dialogContent = Container(
//           padding: const EdgeInsets.all(20),
//           decoration: BoxDecoration(
//             color: const Color(0xFF1B263B),
//             borderRadius: BorderRadius.circular(16),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.3),
//                 blurRadius: 20,
//                 spreadRadius: 5,
//               ),
//             ],
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'Select Location',
//                     style: GoogleFonts.poppins(
//                       color: Colors.white,
//                       fontWeight: FontWeight.bold,
//                       fontSize: 18,
//                     ),
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.close, color: Colors.white70),
//                     onPressed: () {
//                       Navigator.pop(context);
//                       if (_shouldReturnToPlayPage && mounted) {
//                         setState(() {
//                           _selectedIndex = 1;
//                           _shouldReturnToPlayPage = false;
//                         });
//                       }
//                     },
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               GestureDetector(
//                 onTap: () async {
//                   Navigator.pop(context);
//                   await _getUserLocation();
//                 },
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//                   decoration: BoxDecoration(
//                     color: Colors.white.withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(Icons.my_location, color: Colors.blue, size: 24),
//                       const SizedBox(width: 12),
//                       Text(
//                         'Use Current Location',
//                         style: GoogleFonts.poppins(
//                           color: Colors.white,
//                           fontSize: 16,
//                         ),
//                       ),
//                       const Spacer(),
//                       if (_isLoadingLocation)
//                         const SizedBox(
//                           width: 20,
//                           height: 20,
//                           child: CircularProgressIndicator(strokeWidth: 2),
//                         )
//                       else
//                         const Icon(Icons.chevron_right, color: Colors.white70),
//                     ],
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Divider(color: Colors.white.withOpacity(0.2), height: 1),
//               const SizedBox(height: 16),
//               Text(
//                 'Or search for a location',
//                 style: GoogleFonts.poppins(
//                   color: Colors.white70,
//                   fontSize: 14,
//                 ),
//               ),
//               const SizedBox(height: 12),
//               TextField(
//                 controller: _locationController,
//                 style: GoogleFonts.poppins(color: Colors.white),
//                 keyboardType: TextInputType.text, // Fixed the keyboardType parameter
//                 decoration: InputDecoration(
//                   hintText: 'Enter city name',
//                   hintStyle: GoogleFonts.poppins(color: Colors.white54),
//                   filled: true,
//                   fillColor: Colors.white.withOpacity(0.1),
//                   border: OutlineInputBorder(
//                     borderRadius: BorderRadius.circular(12),
//                     borderSide: BorderSide.none,
//                   ),
//                   prefixIcon: const Icon(Icons.search, color: Colors.white70),
//                   contentPadding: const EdgeInsets.symmetric(vertical: 12),
//                 ),
//               ),
//               const SizedBox(height: 20),
//               Row(
//                 children: [
//                   Expanded(
//                     child: TextButton(
//                       onPressed: () {
//                         Navigator.pop(context);
//                         if (_shouldReturnToPlayPage && mounted) {
//                           setState(() {
//                             _selectedIndex = 1;
//                             _shouldReturnToPlayPage = false;
//                           });
//                         }
//                       },
//                       style: TextButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         backgroundColor: Colors.white.withOpacity(0.1),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),
//                       child: Text(
//                         'Cancel',
//                         style: GoogleFonts.poppins(
//                           color: Colors.white,
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: ElevatedButton(
//                       onPressed: () {
//                         if (_locationController.text.isNotEmpty) {
//                           _searchLocation(_locationController.text);
//                           Navigator.pop(context);
//                         }
//                       },
//                       style: ElevatedButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 14),
//                         backgroundColor: Colors.blue,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),
//                       child: Text(
//                         'Search',
//                         style: GoogleFonts.poppins(
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         );

//         if (_scaleAnimation != null && _fadeAnimation != null) {
//           return Dialog(
//             backgroundColor: Colors.transparent,
//             child: ScaleTransition(
//               scale: _scaleAnimation!,
//               child: FadeTransition(
//                 opacity: _fadeAnimation!,
//                 child: dialogContent,
//               ),
//             ),
//           );
//         }
//         return Dialog(
//           backgroundColor: Colors.transparent,
//           child: dialogContent,
//         );
//       },
//     );
//   }

//   Widget _buildHomeScreen(BuildContext context) {
//     return BlocBuilder<AuthBloc, AuthState>(
//       builder: (context, state) {
//         if (state is AuthAuthenticated) {
//           final role = state.profile?['role'];
//           Widget homeContent;

//           if (role == 'participants') {
//             homeContent = _buildParticipantHomeScreen(context);
//           } else if (role == 'organizers') {
//             homeContent = _buildOrganizerHomeScreen(context);
//           } else if (role == 'officials') {
//             homeContent = _buildOfficialHomeScreen(context);
//           } else {
//             homeContent = const Center(child: Text('Unknown role', style: TextStyle(color: Colors.white)));
//           }

//           return Scaffold(
//             appBar: _buildAppBar(context, state),
//             body: homeContent,
//           );
//         }
//         return const Center(child: CircularProgressIndicator());
//       },
//     );
//   }

//   PreferredSizeWidget _buildAppBar(BuildContext context, AuthState state) {
//     return AppBar(
//       elevation: 0,
//       toolbarHeight: 80,
//       flexibleSpace: Container(
//         decoration: const BoxDecoration(
//           gradient: LinearGradient(
//             colors: [Color(0xFF3A506B), Color(0xFF1C2541)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//       ),
//       title: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Badminton Blitz',
//             style: GoogleFonts.poppins(
//               fontWeight: FontWeight.w800,
//               fontSize: 24,
//               color: Colors.white,
//               letterSpacing: 0.5,
//               shadows: [
//                 Shadow(
//                   color: Colors.black.withOpacity(0.3),
//                   blurRadius: 10,
//                   offset: const Offset(0, 2),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 4),
//           GestureDetector(
//             onTap: _showLocationSearchDialog,
//             child: Row(
//               children: [
//                 Icon(Icons.location_pin, color: Colors.white70, size: 18),
//                 const SizedBox(width: 8),
//                 _isLoadingLocation && !_locationFetchCompleted
//                     ? SizedBox(
//                         width: 100,
//                         height: 20,
//                         child: Center(
//                           child: SizedBox(
//                             width: 16,
//                             height: 16,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2,
//                               valueColor: AlwaysStoppedAnimation<Color>(
//                                 Colors.white.withOpacity(0.7),
//                               ),
//                             ),
//                           ),
//                         ),
//                       )
//                     : Flexible(
//                         child: Text(
//                           _location,
//                           style: GoogleFonts.poppins(
//                             color: Colors.white70,
//                             fontSize: 14,
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                 const SizedBox(width: 4),
//                 Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
//               ],
//             ),
//           ),
//         ],
//       ),
//       actions: [
//         IconButton(
//           icon: Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               color: Colors.white.withOpacity(0.1),
//               border: Border.all(
//                 color: Colors.white.withOpacity(0.3),
//                 width: 1,
//               ),
//             ),
//             child: Icon(
//               state is AuthAuthenticated ? Icons.logout : Icons.login,
//               color: Colors.white,
//               size: 20,
//             ),
//           ),
//           onPressed: () async {
//             if (state is AuthAuthenticated) {
//               final shouldLogout = await _showLogoutConfirmationDialog(context);
//               if (shouldLogout ?? false) {
//                 context.read<AuthBloc>().add(AuthLogoutEvent());
//                 setState(() {
//                   _showToast = true;
//                   _toastMessage = 'You have been logged out successfully.';
//                   _toastType = ToastificationType.success;
//                 });
//               }
//             } else if (mounted) {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (_) => const AuthPage()),
//               );
//             }
//           },
//         ),
//       ],
//     );
//   }

//   Widget _buildParticipantHomeScreen(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//           colors: [
//             const Color(0xFF0D1B2A),
//             const Color(0xFF1B263B).withOpacity(0.9),
//             const Color(0xFF0D1B2A).withOpacity(0.9),
//           ],
//           stops: const [0.0, 0.5, 1.0],
//         ),
//       ),
//       child: ListView(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Welcome Back, Participant!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'Join matches or tournaments today!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 14,
//                     color: Colors.white70,
//                   ),
//                 ),
//                 const SizedBox(height: 24),
//               ],
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 2,
//                 mainAxisSpacing: 16,
//                 crossAxisSpacing: 16,
//                 childAspectRatio: 0.85,
//               ),
//               itemCount: 2,
//               itemBuilder: (context, index) {
//                 final features = [
//                   {
//                     'title': 'Find a Match',
//                     'icon': Icons.sports_tennis,
//                     'color': const Color(0xFF4CAF50),
//                     'image': matchImage,
//                     'onTap': () => _onItemTapped(1),
//                   },
//                   {
//                     'title': 'Your Profile',
//                     'icon': Icons.person,
//                     'color': const Color(0xFFFF9800),
//                     'image': profileImage,
//                     'onTap': () => _onItemTapped(2),
//                   },
//                 ];

//                 final feature = features[index];
//                 return _FeatureCard(
//                   title: feature['title'] as String,
//                   icon: feature['icon'] as IconData,
//                   color: feature['color'] as Color,
//                   imagePath: feature['image'] as String,
//                   onTap: feature['onTap'] as VoidCallback,
//                 );
//               },
//             ),
//           ),
//           const SizedBox(height: 24),
//         ],
//       ),
//     );
//   }

//   Widget _buildOrganizerHomeScreen(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//           colors: [
//             const Color(0xFF0D1B2A),
//             const Color(0xFF1B263B).withOpacity(0.9),
//             const Color(0xFF0D1B2A).withOpacity(0.9),
//           ],
//           stops: const [0.0, 0.5, 1.0],
//         ),
//       ),
//       child: ListView(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Welcome Back, Organizer!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'Create or manage your tournaments!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 14,
//                     color: Colors.white70,
//                   ),
//                 ),
//                 const SizedBox(height: 24),
//               ],
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 2,
//                 mainAxisSpacing: 16,
//                 crossAxisSpacing: 16,
//                 childAspectRatio: 0.85,
//               ),
//               itemCount: 2,
//               itemBuilder: (context, index) {
//                 final features = [
//                   {
//                     'title': 'Host Tournaments',
//                     'icon': Icons.emoji_events,
//                     'color': const Color(0xFF9C27B0),
//                     'image': tournamentImage,
//                     'onTap': () {
//                       final state = context.read<AuthBloc>().state;
//                       if (state is AuthAuthenticated && mounted) {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => CreateTournamentPage(
//                               userId: state.user.uid,
//                             ),
//                           ),
//                         ).then((_) {
//                           if (mounted) {
//                             setState(() {
//                               _selectedIndex = 0;
//                             });
//                           }
//                         });
//                       }
//                     },
//                   },
//                   {
//                     'title': 'Your Profile',
//                     'icon': Icons.person,
//                     'color': const Color(0xFFFF9800),
//                     'image': profileImage,
//                     'onTap': () => _onItemTapped(2),
//                   },
//                 ];

//                 final feature = features[index];
//                 return _FeatureCard(
//                   title: feature['title'] as String,
//                   icon: feature['icon'] as IconData,
//                   color: feature['color'] as Color,
//                   imagePath: feature['image'] as String,
//                   onTap: feature['onTap'] as VoidCallback,
//                 );
//               },
//             ),
//           ),
//           const SizedBox(height: 24),
//         ],
//       ),
//     );
//   }

//   Widget _buildOfficialHomeScreen(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topCenter,
//           end: Alignment.bottomCenter,
//           colors: [
//             const Color(0xFF0D1B2A),
//             const Color(0xFF1B263B).withOpacity(0.9),
//             const Color(0xFF0D1B2A).withOpacity(0.9),
//           ],
//           stops: const [0.0, 0.5, 1.0],
//         ),
//       ),
//       child: ListView(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Welcome Back, Official!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 18,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'Manage matches or join as a player!',
//                   style: GoogleFonts.poppins(
//                     fontSize: 14,
//                     color: Colors.white70,
//                   ),
//                 ),
//                 const SizedBox(height: 24),
//               ],
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20),
//             child: GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 2,
//                 mainAxisSpacing: 16,
//                 crossAxisSpacing: 16,
//                 childAspectRatio: 0.85,
//               ),
//               itemCount: 3,
//               itemBuilder: (context, index) {
//                 final features = [
//                   {
//                     'title': 'Find a Match',
//                     'icon': Icons.sports_tennis,
//                     'color': const Color(0xFF4CAF50),
//                     'image': matchImage,
//                     'onTap': () => _onItemTapped(1),
//                   },
//                   {
//                     'title': 'Manage Tournaments',
//                     'icon': Icons.emoji_events,
//                     'color': const Color(0xFF9C27B0),
//                     'image': tournamentImage,
//                     'onTap': () {
//                       // Placeholder for official-specific tournament management
//                       if (mounted) {
//                         setState(() {
//                           _showToast = true;
//                           _toastMessage = 'Tournament management coming soon!';
//                           _toastType = ToastificationType.info;
//                         });
//                       }
//                     },
//                   },
//                   {
//                     'title': 'Your Profile',
//                     'icon': Icons.person,
//                     'color': const Color(0xFFFF9800),
//                     'image': profileImage,
//                     'onTap': () => _onItemTapped(2),
//                   },
//                 ];

//                 final feature = features[index];
//                 return _FeatureCard(
//                   title: feature['title'] as String,
//                   icon: feature['icon'] as IconData,
//                   color: feature['color'] as Color,
//                   imagePath: feature['image'] as String,
//                   onTap: feature['onTap'] as VoidCallback,
//                 );
//               },
//             ),
//           ),
//           const SizedBox(height: 24),
//         ],
//       ),
//     );
//   }

//   void _onItemTapped(int index) {
//     if (index < 0 || index >= 3) {
//       print('Invalid index: $index');
//       return;
//     }
//     if (mounted) {
//       setState(() {
//         _selectedIndex = index;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Show toast messages in the build method
//     if (_showToast && _toastMessage != null && _toastType != null && mounted) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         toastification.show(
//           context: context,
//           type: _toastType!,
//           title: Text(_toastType == ToastificationType.success
//               ? 'Success'
//               : _toastType == ToastificationType.warning
//                   ? 'Warning'
//                   : _toastType == ToastificationType.error
//                       ? 'Error'
//                       : 'Info'),
//           description: Text(_toastMessage!),
//           autoCloseDuration: const Duration(seconds: 3),
//           backgroundColor: _toastType == ToastificationType.success
//               ? Colors.green
//               : _toastType == ToastificationType.warning
//                   ? Colors.orange
//                   : _toastType == ToastificationType.error
//                       ? Colors.red
//                       : Colors.blue,
//           foregroundColor: Colors.white,
//           alignment: Alignment.bottomCenter,
//         );
//         if (mounted) {
//           setState(() {
//             _showToast = false;
//             _toastMessage = null;
//             _toastType = null;
//           });
//         }
//       });
//     }

//     return BlocBuilder<AuthBloc, AuthState>(
//       builder: (context, state) {
//         if (state is AuthUnauthenticated) {
//           return const AuthPage();
//         }

//         String userId = state is AuthAuthenticated ? state.user.uid : '';
//         String? userRole = state is AuthAuthenticated ? (state.profile != null ? state.profile!['role'] : null) : null;

//         return StreamBuilder<DocumentSnapshot>(
//           stream: userId.isNotEmpty
//               ? FirebaseFirestore.instance.collection(userRole!).doc(userId).snapshots()
//               : null,
//           builder: (context, snapshot) {
//             if (snapshot.hasData && snapshot.data != null) {
//               final userData = snapshot.data!.data() as Map<String, dynamic>?;
//               if (!_isLoadingLocation && !_locationFetchCompleted && mounted) {
//                 _userCity = (userData?['city'] ?? 'hyderabad').toLowerCase();
//                 _location = '$_userCity, India';
//               }
//             }

//             final pages = [
//               _buildHomeScreen(context),
//               PlayPage(userCity: _userCity, key: ValueKey(_userCity)),
//               const PlayerProfilePage(),
//             ];

//             return WillPopScope(
//               onWillPop: _onWillPop,
//               child: AnnotatedRegion<SystemUiOverlayStyle>(
//                 value: const SystemUiOverlayStyle(
//                   statusBarColor: Color(0xFF0D1B2A),
//                   statusBarIconBrightness: Brightness.light,
//                   statusBarBrightness: Brightness.dark,
//                 ),
//                 child: Scaffold(
//                   key: _scaffoldKey,
//                   backgroundColor: Colors.transparent,
//                   body: IndexedStack(
//                     index: _selectedIndex,
//                     children: pages,
//                   ),
//                   bottomNavigationBar: _buildBottomNavBar(),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   Widget _buildBottomNavBar() {
//     return Container(
//       decoration: BoxDecoration(
//         color: const Color(0xFF1B263B),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.3),
//             blurRadius: 10,
//             spreadRadius: 2,
//           ),
//         ],
//         border: Border(
//           top: BorderSide(
//             color: Colors.white.withOpacity(0.1),
//             width: 1,
//           ),
//         ),
//       ),
//       child: ClipRRect(
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
//         child: BottomNavigationBar(
//           backgroundColor: const Color(0xFF1B263B).withOpacity(0.9),
//           selectedItemColor: Colors.white,
//           unselectedItemColor: Colors.white.withOpacity(0.6),
//           currentIndex: _selectedIndex,
//           onTap: _onItemTapped,
//           type: BottomNavigationBarType.fixed,
//           elevation: 0,
//           showSelectedLabels: true,
//           showUnselectedLabels: true,
//           selectedLabelStyle: GoogleFonts.poppins(
//             fontSize: 12,
//             fontWeight: FontWeight.w500,
//           ),
//           unselectedLabelStyle: GoogleFonts.poppins(
//             fontSize: 12,
//             fontWeight: FontWeight.w500,
//           ),
//           items: [
//             BottomNavigationBarItem(
//               icon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: _selectedIndex == 0 ? Colors.white.withOpacity(0.2) : Colors.transparent,
//                 ),
//                 child: const Icon(Icons.home_outlined, size: 24),
//               ),
//               activeIcon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: Colors.white.withOpacity(0.2),
//                 ),
//                 child: const Icon(Icons.home_filled, size: 24),
//               ),
//               label: 'Home',
//             ),
//             BottomNavigationBarItem(
//               icon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: _selectedIndex == 1 ? Colors.white.withOpacity(0.2) : Colors.transparent,
//                 ),
//                 child: const Icon(Icons.sports_tennis_outlined, size: 24),
//               ),
//               activeIcon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: Colors.white.withOpacity(0.2),
//                 ),
//                 child: const Icon(Icons.sports_tennis, size: 24),
//               ),
//               label: 'Play',
//             ),
//             BottomNavigationBarItem(
//               icon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: _selectedIndex == 2 ? Colors.white.withOpacity(0.2) : Colors.transparent,
//                 ),
//                 child: const Icon(Icons.person_outline, size: 24),
//               ),
//               activeIcon: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: Colors.white.withOpacity(0.2),
//                 ),
//                 child: const Icon(Icons.person, size: 24),
//               ),
//               label: 'Profile',
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _FeatureCard extends StatelessWidget {
//   final String title;
//   final IconData icon;
//   final Color color;
//   final String imagePath;
//   final VoidCallback onTap;

//   const _FeatureCard({
//     required this.title,
//     required this.icon,
//     required this.color,
//     required this.imagePath,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(16),
//       child: Container(
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(16),
//           gradient: LinearGradient(
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//             colors: [
//               color.withOpacity(0.15),
//               color.withOpacity(0.05),
//             ],
//           ),
//           border: Border.all(
//             color: Colors.white.withOpacity(0.1),
//             width: 1,
//           ),
//         ),
//         child: Stack(
//           children: [
//             Positioned(
//               right: 0,
//               bottom: 0,
//               child: Opacity(
//                 opacity: 0.3,
//                 child: Image.asset(
//                   imagePath,
//                   width: 100,
//                   height: 100,
//                   fit: BoxFit.cover,
//                   errorBuilder: (context, error, stackTrace) {
//                     return Container(
//                       width: 100,
//                       height: 100,
//                       color: Colors.grey.withOpacity(0.3),
//                       child: const Icon(
//                         Icons.broken_image,
//                         color: Colors.white70,
//                         size: 40,
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.all(10),
//                     decoration: BoxDecoration(
//                       color: color.withOpacity(0.2),
//                       shape: BoxShape.circle,
//                     ),
//                     child: Icon(icon, color: color, size: 20),
//                   ),
//                   const SizedBox(height: 16),
//                   Text(
//                     title,
//                     style: GoogleFonts.poppins(
//                       color: Colors.white,
//                       fontWeight: FontWeight.w600,
//                       fontSize: 16,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Tap to explore',
//                     style: GoogleFonts.poppins(
//                       color: Colors.white70,
//                       fontSize: 12,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }