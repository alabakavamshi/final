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
  late TextEditingController _nameController;
  late TextEditingController _venueController;
  late TextEditingController _cityController;
  late TextEditingController _entryFeeController;
  late TextEditingController _rulesController;
  late TextEditingController _maxParticipantsController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  DateTime? _selectedEndDate;
  late String _gameFormat;
  late String _gameType;
  late bool _bringOwnEquipment;
  late bool _costShared;
  late List<Map<String, dynamic>> _matches;
  bool _isLoading = false;

  // Default badminton rules
  static const String _defaultBadmintonRules = '''
  1. Matches are best of 3 games, each played to 21 points with a 2-point lead required to win.
  2. A rally point system is used; a point is scored on every serve.
  3. Players change sides after each game and at 11 points in the third game.
  4. A 60-second break is allowed between games, and a 120-second break at 11 points in a game.
  5. Service must be diagonal, below the waist, and the shuttle must land within the opponent's court.
  6. Faults include: shuttle landing out of bounds, double hits, or player touching the net.
  7. Respect the umpire's decisions and maintain sportsmanship at all times.
  ''';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tournament.name);
    _venueController = TextEditingController(text: widget.tournament.venue);
    _cityController = TextEditingController(text: widget.tournament.city);
    _entryFeeController = TextEditingController(text: widget.tournament.entryFee.toString());
    _rulesController = TextEditingController(
      text: widget.tournament.rules.isEmpty ? _defaultBadmintonRules : widget.tournament.rules,
    );
    _maxParticipantsController = TextEditingController(text: widget.tournament.maxParticipants.toString());
    _selectedDate = widget.tournament.eventDate;
    _selectedTime = TimeOfDay(hour: widget.tournament.eventDate.hour, minute: widget.tournament.eventDate.minute);
    _selectedEndDate = widget.tournament.endDate;
    _gameFormat = widget.tournament.gameFormat;
    _gameType = widget.tournament.gameType;
    _bringOwnEquipment = widget.tournament.bringOwnEquipment;
    _costShared = widget.tournament.costShared;
    _matches = List.from(widget.tournament.matches);
  }

  @override
  void dispose() {
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

  Future<bool> _checkAndRequestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Location Services Disabled'),
        description: const Text('Please enable location services.'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return false;
    }

    // Check location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('Permission Denied'),
          description: const Text('Location permissions are denied.'),
          autoCloseDuration: const Duration(seconds: 3),
          backgroundColor: Colors.grey[800],
          foregroundColor: Colors.white,
          alignment: Alignment.bottomCenter,
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Permission Denied Forever'),
        description: const Text('Location permissions are permanently denied. Please enable them in settings.'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
      return false;
    }

    return true;
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check and request location permissions
      bool hasPermission = await _checkAndRequestLocationPermission();
      if (!hasPermission) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get the current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Convert coordinates to a city name
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        String? city = placemark.locality;

        if (city != null && city.isNotEmpty) {
          setState(() {
            _cityController.text = city;
          });
          toastification.show(
            context: context,
            type: ToastificationType.success,
            title: const Text('Location Fetched'),
            description: Text('City set to $city.'),
            autoCloseDuration: const Duration(seconds: 3),
            backgroundColor: Colors.grey[800],
            foregroundColor: Colors.white,
            alignment: Alignment.bottomCenter,
          );
        } else {
          throw Exception('City not found in location data');
        }
      } else {
        throw Exception('No placemarks found');
      }
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Location Error'),
        description: Text('Failed to fetch current location: $e'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateTournament() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedEndDate == null) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('End Date Required'),
        description: const Text('Please select an end date.'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
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
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Invalid Date Range'),
        description: const Text('End date must be on or after start date.'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
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
        entryFee: double.parse(_entryFeeController.text.trim()),
        status: widget.tournament.status,
        createdBy: widget.tournament.createdBy,
        createdAt: widget.tournament.createdAt,
        participants: widget.tournament.participants,
        rules: _rulesController.text.trim(),
        maxParticipants: int.parse(_maxParticipantsController.text.trim()),
        gameFormat: _gameFormat,
        gameType: _gameType,
        bringOwnEquipment: _bringOwnEquipment,
        costShared: _costShared,
        matches: _matches,
        teams: widget.tournament.teams,
      );

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .update(updatedTournament.toFirestore());

      toastification.show(
        context: context,
        type: ToastificationType.success,
        title: const Text('Event Updated'),
        description: Text('"${updatedTournament.name}" has been updated.'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );

      Navigator.pop(context);
    } catch (e) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        title: const Text('Update Failed'),
        description: Text('Failed to update event: $e'),
        autoCloseDuration: const Duration(seconds: 3),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        alignment: Alignment.bottomCenter,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
              // Tournament Details
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    labelText: 'Event Name',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Enter a name' : null,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _venueController,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    labelText: 'Venue',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Enter a venue' : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextFormField(
                        controller: _cityController,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        cursorColor: Colors.white,
                        decoration: const InputDecoration(
                          labelText: 'City',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty ? 'Enter a city' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isLoading ? null : _fetchCurrentLocation,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isLoading ? Colors.grey[700] : Colors.blueGrey[700],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectDate(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          DateFormat('MMM dd, yyyy').format(_selectedDate),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _selectedTime.format(context),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectEndDate(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _selectedEndDate == null
                              ? 'Select End Date'
                              : DateFormat('MMM dd, yyyy').format(_selectedEndDate!),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _entryFeeController,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: Colors.white,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Entry Fee',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an entry fee';
                    }
                    final fee = double.tryParse(value);
                    if (fee == null || fee < 0) {
                      return 'Enter a valid entry fee';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _gameFormat,
                  items: ['Singles', 'Doubles', 'Mixed Doubles', "Women's Doubles"]
                      .map((format) => DropdownMenuItem(
                            value: format,
                            child: Text(
                              format,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _gameFormat = value!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Game Format',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _gameType,
                  items: ['Tournament', 'Friendly', 'League']
                      .map((type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _gameType = value!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Game Type',
                    labelStyle: GoogleFonts.poppins(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _maxParticipantsController,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  cursorColor: Colors.white,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Participants',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter the maximum number of participants';
                    }
                    final max = int.tryParse(value);
                    if (max == null || max <= 0) {
                      return 'Enter a valid number';
                    }
                    if (max < widget.tournament.participants.length) {
                      return 'Cannot set max participants less than current participants (${widget.tournament.participants.length})';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _rulesController,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    labelText: 'Rules',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Enter the rules' : null,
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: Text(
                  'Matches',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: Colors.white.withOpacity(0.05),
                collapsedBackgroundColor: Colors.white.withOpacity(0.05),
                children: _matches.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'No matches scheduled yet.',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ]
                    : _matches.asMap().entries.map((entry) {
                        final index = entry.key;
                        final match = entry.value;
                        return ListTile(
                          title: Text(
                            match['team1'] != null
                                ? 'Team Match: Round ${match['round']}'
                                : 'Singles Match: Round ${match['round']}',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            match['team1'] != null
                                ? 'Team 1: ${match['team1'].join(', ')} vs Team 2: ${match['team2']?.join(', ') ?? 'TBD'}'
                                : 'Player 1: ${match['player1']} vs Player 2: ${match['player2'] ?? 'TBD'}',
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _matches.removeAt(index);
                              });
                            },
                          ),
                        );
                      }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(
                  'Bring Own Equipment',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  'Participants must bring their own equipment',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                value: _bringOwnEquipment,
                onChanged: (value) {
                  setState(() {
                    _bringOwnEquipment = value;
                  });
                },
                activeColor: Colors.blueGrey,
              ),
              SwitchListTile(
                title: Text(
                  'Cost Shared',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  'Costs are shared among participants',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                value: _costShared,
                onChanged: (value) {
                  setState(() {
                    _costShared = value;
                  });
                },
                activeColor: Colors.blueGrey,
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
}