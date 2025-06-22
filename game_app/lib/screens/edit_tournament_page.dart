// ignore_for_file: unused_import

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:toastification/toastification.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

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
  DateTime? _selectedEndDate;
  late String _gameFormat;
  late String _gameType;
  late bool _bringOwnEquipment;
  late bool _costShared;
  bool _isLoading = false;
  String? _fetchedCity;
  final bool _isFetchingLocation = false;
  bool _isCityValid = true;
  bool _isValidatingCity = false;
  Timer? _debounceTimer;

  final Map<String, String> _validCities = {
    'hyderabad': 'Hyderabad',
    'mumbai': 'Mumbai',
    'delhi': 'Delhi',
    'bengaluru': 'Bengaluru',
    'chennai': 'Chennai',
    'kolkata': 'Kolkata',
    'pune': 'Pune',
    'ahmedabad': 'Ahmedabad',
    'jaipur': 'Jaipur',
    'lucknow': 'Lucknow',
    'karimnagar': 'Karimnagar',
  };

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
    _selectedDate = widget.tournament.eventDate;
    _selectedTime = TimeOfDay(hour: widget.tournament.eventDate.hour, minute: widget.tournament.eventDate.minute);
    _selectedEndDate = widget.tournament.endDate;
    _gameFormat = _gameFormatOptions.contains(widget.tournament.gameFormat)
        ? widget.tournament.gameFormat
        : _gameFormatOptions[0]; // Default to 'Men\'s Singles'
    _gameType = _gameTypeOptions.contains(widget.tournament.gameType)
        ? widget.tournament.gameType
        : _gameTypeOptions[0]; // Default to 'Knockout'
    _bringOwnEquipment = widget.tournament.bringOwnEquipment;
    _costShared = widget.tournament.costShared;
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
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
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? _selectedDate,
      firstDate: _selectedDate,
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

    final normalizedCity = city.trim();
    final normalizedLower = normalizedCity.toLowerCase();

    if (_validCities.containsKey(normalizedLower)) {
      if (mounted) {
        setState(() {
          _cityController.text = _validCities[normalizedLower]!;
          _isCityValid = true;
          _isValidatingCity = false;
        });
      }
      return;
    }

    try {
      List<Location> locations = await locationFromAddress('$normalizedCity, India');
      if (locations.isNotEmpty) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          locations.first.latitude,
          locations.first.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final fetchedCity = place.locality?.toLowerCase() ?? place.administrativeArea?.toLowerCase();
          if (fetchedCity == normalizedLower || _validCities.containsValue(place.locality)) {
            if (mounted) {
              setState(() {
                _cityController.text = place.locality ?? normalizedCity;
                _isCityValid = true;
                _isValidatingCity = false;
              });
            }
            return;
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
      if (_validCities.containsKey(normalizedLower)) {
        if (mounted) {
          setState(() {
            _cityController.text = _validCities[normalizedLower]!;
            _isCityValid = true;
            _isValidatingCity = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isCityValid = false;
            _isValidatingCity = false;
            _cityController.clear();
          });
          _showErrorToast('Invalid City', 'Geocoding failed for "$normalizedCity"');
        }
      }
    }
  }

  void _debounceCityValidation(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 2000), () {
      _validateCityWithGeocoding(value);
    });
  }

  Future<void> _updateTournament() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedEndDate == null) {
      _showErrorToast('End Date Required', 'Please select an end date.');
      return;
    }

    final eventDateTime = DateTime(
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

    if (endDate.isBefore(eventDateTime)) {
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
        eventDate: eventDateTime,
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
    return Scaffold(
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
              _buildCityFieldWithLocation(),
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
              _buildDropdown(
                label: 'Game Format',
                value: _gameFormat,
                items: _gameFormatOptions,
                onChanged: (value) => setState(() => _gameFormat = value!),
                validator: (value) => value == null ? 'Select a game format' : null,
              ),
              const SizedBox(height: 16),
              _buildDropdown(
                label: 'Game Type',
                value: _gameType,
                items: _gameTypeOptions,
                onChanged: (value) => setState(() => _gameType = value!),
                validator: (value) => value == null ? 'Select a game type' : null,
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
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

  Widget _buildCityFieldWithLocation() {
    return Stack(
      children: [
        _buildTextField(
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
        if (!_isFetchingLocation)
          Positioned(
            right: 20,
            top: 4,
            child: IconButton(
              icon: Icon(
                Icons.my_location,
                color: _fetchedCity != null ? Colors.white : Colors.white54,
                size: 20,
              ),
              onPressed: _fetchedCity != null
                  ? () {
                      setState(() {
                        _cityController.text = _fetchedCity!;
                        _isCityValid = _validCities.containsValue(_fetchedCity);
                      });
                    }
                  : null,
            ),
          ),
      ],
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
      child: Text(
        value,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items.map((item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w400,
                ),
              ),
            )).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          border: InputBorder.none,
        ),
        dropdownColor: Colors.black,
        validator: validator,
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