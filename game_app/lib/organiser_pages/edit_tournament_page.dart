import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class EditTournamentPage extends StatefulWidget {
  final Tournament tournament;

  const EditTournamentPage({super.key, required this.tournament});

  @override
  State<EditTournamentPage> createState() => _EditTournamentPageState();
}

class _EditTournamentPageState extends State<EditTournamentPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _venueController = TextEditingController();
  final _cityController = TextEditingController();
  final _entryFeeController = TextEditingController();
  final _rulesController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late DateTime? _selectedEndDate;
  late String _gameFormat;
  late String _gameType;
  late bool _bringOwnEquipment;
  late bool _costShared;
  bool _isLoading = false;
  String? _fetchedCity;
  bool _isFetchingLocation = false;
  bool _isCityValid = true;
  bool _isValidatingCity = false;
  Timer? _debounceTimer;

  late String _initialName;
  late String _initialVenue;
  late String _initialCity;
  late String _initialEntryFee;
  late String _initialRules;
  late String _initialMaxParticipants;
  late DateTime _initialStartDate;
  late TimeOfDay _initialStartTime;
  late DateTime? _initialEndDate;
  late bool _initialBringOwnEquipment;
  late bool _initialCostShared;

  final List<String> _gameFormatOptions = [
    'Men\'s Singles',
    'Women\'s Singles',
    'Men\'s Doubles',
    'Women\'s Doubles',
    'Mixed Doubles',
  ];
  final List<String> _gameTypeOptions = [
    'Knockout',
    'Double Elimination',
    'Round-Robin',
    'Group + Knockout',
    'Team Format',
    'Ladder',
    'Swiss Format',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.tournament.name;
    _venueController.text = widget.tournament.venue;
    _cityController.text = widget.tournament.city;
    _entryFeeController.text = widget.tournament.entryFee.toStringAsFixed(2);
    _rulesController.text = widget.tournament.rules.isEmpty
        ? '''
1. Matches are best of 3 games, each played to 21 points with a 2-point lead required to win.
2. A rally point system is used; a point is scored on every serve.
3. Players change sides after each game and at 11 points in the third game.
4. A 60-second break is allowed between games, and a 120-second break at 11 points in a game.
5. Service must be diagonal, below the waist, and the shuttle must land within the opponent's court.
6. Faults include: shuttle landing out of bounds, double hits, or player touching the net.
7. Respect the umpire's decisions and maintain sportsmanship at all times.
'''
        : widget.tournament.rules;
    _maxParticipantsController.text = widget.tournament.maxParticipants.toString();
    _selectedDate = widget.tournament.startDate;
    _selectedTime = widget.tournament.startTime;
    _selectedEndDate = widget.tournament.endDate;
    _gameFormat = _gameFormatOptions.contains(widget.tournament.gameFormat)
        ? widget.tournament.gameFormat
        : _gameFormatOptions[0];
    _gameType = _gameTypeOptions.contains(widget.tournament.gameType)
        ? widget.tournament.gameType
        : _gameTypeOptions[0];
    _bringOwnEquipment = widget.tournament.bringOwnEquipment;
    _costShared = widget.tournament.costShared;

    _initialName = _nameController.text;
    _initialVenue = _venueController.text;
    _initialCity = _cityController.text;
    _initialEntryFee = _entryFeeController.text;
    _initialRules = _rulesController.text;
    _initialMaxParticipants = _maxParticipantsController.text;
    _initialStartDate = _selectedDate;
    _initialStartTime = _selectedTime;
    _initialEndDate = _selectedEndDate;
    _initialBringOwnEquipment = _bringOwnEquipment;
    _initialCostShared = _costShared;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _venueController.dispose();
    _cityController.dispose();
    _entryFeeController.dispose();
    _rulesController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  bool _hasChanges() {
    return _nameController.text != _initialName ||
        _venueController.text != _initialVenue ||
        _cityController.text != _initialCity ||
        _entryFeeController.text != _initialEntryFee ||
        _rulesController.text != _initialRules ||
        _maxParticipantsController.text != _initialMaxParticipants ||
        _selectedDate != _initialStartDate ||
        _selectedTime != _initialStartTime ||
        _selectedEndDate != _initialEndDate ||
        _bringOwnEquipment != _initialBringOwnEquipment ||
        _costShared != _initialCostShared;
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges()) return true;

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        title: Text(
          'Unsaved Changes',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'You have unsaved changes. Are you sure you want to leave?',
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Colors.blueGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Leave',
              style: GoogleFonts.poppins(
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
  }

  Future<void> _selectDate(BuildContext context) async {
    // If the existing startDate is in the past, use it as firstDate to avoid assertion error
    final firstDate = _selectedDate.isBefore(DateTime.now())
        ? _selectedDate
        : DateTime.now();
    // Use current date as initialDate if startDate is in the past to enforce future selection
    final initialDate = _selectedDate.isBefore(DateTime.now())
        ? DateTime.now()
        : _selectedDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      if (picked.isBefore(DateTime.now())) {
        _showErrorToast('Invalid Start Date', 'Start date cannot be in the past.');
        return;
      }
      setState(() {
        _selectedDate = picked;
        if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) {
          _selectedEndDate = null;
          _showErrorToast(
            'End Date Reset',
            'End date was reset because it was before the new start date. Please select a new end date.',
          );
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final initialDate = _selectedEndDate != null && !_selectedEndDate!.isBefore(_selectedDate)
        ? _selectedEndDate!
        : _selectedDate;
    final firstDate = _selectedDate;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedEndDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueGrey,
              onPrimary: Colors.white,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _validateCityWithGeocoding(String city) async {
    if (city.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isValidatingCity = true;
      });
    }

    final normalizedCity = city.trim().toLowerCase();

    try {
      List<Location> locations = await locationFromAddress('$normalizedCity, India');
      if (locations.isNotEmpty) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          locations.first.latitude,
          locations.first.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final fetchedCity = place.locality ?? place.administrativeArea;
          if (fetchedCity != null) {
            if (mounted) {
              setState(() {
                _cityController.text = fetchedCity;
                _isCityValid = true;
                _isValidatingCity = false;
              });
            }
            return;
          }
        }
      }

      if (normalizedCity.length > 2) {
        List<Location> suggestionLocations = await locationFromAddress('$normalizedCity, India');
        if (suggestionLocations.isNotEmpty) {
          List<Placemark> suggestions = await placemarkFromCoordinates(
            suggestionLocations.first.latitude,
            suggestionLocations.first.longitude,
          );
          if (suggestions.isNotEmpty) {
            final suggestedCity = suggestions.first.locality ?? suggestions.first.administrativeArea;
            if (suggestedCity != null) {
              if (mounted) {
                setState(() {
                  _cityController.text = suggestedCity;
                  _isCityValid = true;
                  _isValidatingCity = false;
                });
              }
              return;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
        });
        _showErrorToast('Invalid City', 'No matching city found for "$normalizedCity"');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCityValid = false;
          _isValidatingCity = false;
          _cityController.clear();
        });
        _showErrorToast('Invalid City', 'Geocoding failed for "$normalizedCity": $e');
      }
    }
  }

  void _debounceCityValidation(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 2000), () {
      _validateCityWithGeocoding(value);
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isFetchingLocation = true;
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorToast('Location Permission Denied', 'Please enable location permissions.');
          setState(() {
            _isFetchingLocation = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showErrorToast('Location Permission Denied Forever', 'Please enable location permissions in settings.');
        setState(() {
          _isFetchingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality ?? place.administrativeArea;
        if (city != null) {
          setState(() {
            _fetchedCity = city;
            _cityController.text = city;
            _isCityValid = true;
            _isFetchingLocation = false;
          });
        } else {
          _showErrorToast('Invalid Location', 'Could not determine a valid city from current location.');
          setState(() {
            _isFetchingLocation = false;
          });
        }
      }
    } catch (e) {
      _showErrorToast('Location Error', 'Failed to get current location: $e');
      setState(() {
        _isFetchingLocation = false;
      });
    }
  }

  Future<void> _updateTournament() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedEndDate == null) {
      _showErrorToast('End Date Required', 'Please select an end date.');
      return;
    }

    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final endDate = DateTime(
      _selectedEndDate!.year,
      _selectedEndDate!.month,
      _selectedEndDate!.day,
    );

    if (endDate.isBefore(startDateTime)) {
      _showErrorToast('Invalid Date Range', 'End date must be on or after start date.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedTournament = Tournament(
        id: widget.tournament.id,
        name: _nameController.text.trim(),
        venue: _venueController.text.trim(),
        city: _cityController.text.trim(),
        startDate: startDateTime,
        startTime: _selectedTime,
        endDate: endDate,
        entryFee: double.tryParse(_entryFeeController.text.trim()) ?? 0.0,
        status: widget.tournament.status,
        createdBy: widget.tournament.createdBy,
        createdAt: widget.tournament.createdAt,
        participants: widget.tournament.participants,
        rules: _rulesController.text.trim(),
        maxParticipants: int.tryParse(_maxParticipantsController.text.trim()) ?? 1,
        gameFormat: _gameFormat,
        gameType: _gameType,
        bringOwnEquipment: _bringOwnEquipment,
        costShared: _costShared,
        teams: widget.tournament.teams,
        matches: widget.tournament.matches,
      );

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update(updatedTournament.toFirestore());

      _showSuccessToast('Event Updated', '"${updatedTournament.name}" has been updated.');
      Navigator.pop(context);
    } catch (e) {
      _showErrorToast('Update Failed', 'Failed to update event: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessToast(String title, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.success,
      title: Text(title),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      backgroundColor: Colors.grey[800],
      foregroundColor: Colors.white,
      alignment: Alignment.bottomCenter,
    );
  }

  void _showErrorToast(String title, String message) {
    toastification.show(
      context: context,
      type: ToastificationType.error,
      title: Text(title),
      description: Text(message),
      autoCloseDuration: const Duration(seconds: 3),
      backgroundColor: Colors.grey[800],
      foregroundColor: Colors.white,
      alignment: Alignment.bottomCenter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            'Edit Event',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Event Name',
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _venueController,
                  label: 'Venue',
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter a venue' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _cityController,
                        label: 'City',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter a city';
                          return !_isCityValid ? 'Enter a valid Indian city' : null;
                        },
                        onChanged: _debounceCityValidation,
                        suffix: _isValidatingCity
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(
                                _isCityValid ? Icons.check_circle : Icons.error,
                                color: _isCityValid ? Colors.green : Colors.red,
                                size: 20,
                              ),
                      ),
                    ),
                    IconButton(
                      icon: _isFetchingLocation
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              Icons.my_location,
                              color: _fetchedCity != null ? Colors.white : Colors.white54,
                              size: 20,
                            ),
                      onPressed: _isFetchingLocation || _fetchedCity != null
                          ? null
                          : () => _getCurrentLocation(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectDate(context),
                        child: _buildDateTimeField(
                          label: 'Start Date',
                          value: DateFormat('MMM dd, yyyy').format(_selectedDate),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectTime(context),
                        child: _buildDateTimeField(
                          label: 'Start Time',
                          value: _selectedTime.format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _selectEndDate(context),
                        child: _buildDateTimeField(
                          label: 'End Date',
                          value: _selectedEndDate == null
                              ? 'Select End Date'
                              : DateFormat('MMM dd, yyyy').format(_selectedEndDate!),
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _entryFeeController,
                  label: 'Entry Fee',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter an entry fee';
                    final fee = double.tryParse(value);
                    return fee == null || fee < 0 ? 'Enter a valid amount' : null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: TextEditingController(text: widget.tournament.gameFormat),
                  label: 'Game Format',
                  enabled: false,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: TextEditingController(text: widget.tournament.gameType),
                  label: 'Game Type',
                  enabled: false,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _maxParticipantsController,
                  label: 'Max Participants',
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter max participants';
                    final max = int.tryParse(value);
                    if (max == null || max <= 0) return 'Enter a valid number';
                    if (max < widget.tournament.participants.length) {
                      return 'Cannot set max less than current participants (${widget.tournament.participants.length})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _rulesController,
                  label: 'Rules',
                  maxLines: 5,
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Enter the rules' : null,
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  title: 'Bring Own Equipment',
                  subtitle: 'Participants must bring their own equipment',
                  value: _bringOwnEquipment,
                  onChanged: (value) => setState(() => _bringOwnEquipment = value),
                ),
                _buildSwitchTile(
                  title: 'Cost Shared',
                  subtitle: 'Costs are shared among participants',
                  value: _costShared,
                  onChanged: (value) => setState(() => _costShared = value),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _isLoading ? null : _updateTournament,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isLoading ? Colors.grey[700] : Colors.blueGrey[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text(
                              'Update Event',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        cursorColor: Colors.white,
        keyboardType: keyboardType,
        maxLines: maxLines,
        enabled: enabled,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          suffixIcon: suffix,
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildDateTimeField({required String label, required String value}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (label == 'Start Date' && _selectedDate.isBefore(DateTime.now()))
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 20,
            ),
          if (label == 'End Date' && _selectedEndDate != null && _selectedEndDate!.isBefore(_selectedDate))
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueGrey,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }
}