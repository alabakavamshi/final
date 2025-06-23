import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:game_app/models/tournament.dart';
import 'package:game_app/widgets/tournament_card.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

class TournamentDiscoveryScreen extends StatefulWidget {
  const TournamentDiscoveryScreen({super.key});

  @override
  State<TournamentDiscoveryScreen> createState() => _TournamentDiscoveryScreenState();
}

class _TournamentDiscoveryScreenState extends State<TournamentDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterCity;
  String? _filterGameFormat;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _sortBy = 'date'; // Default sorting by date
  bool _isRefreshing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _fetchCreatorNames(List<Tournament> tournaments) async {
    final creatorUids = tournaments.map((t) => t.createdBy).toSet().toList();
    final Map<String, String> creatorNames = {};

    try {
      final List<Future<DocumentSnapshot>> userFutures = creatorUids
          .map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get())
          .toList();
      final userDocs = await Future.wait(userFutures);

      for (var doc in userDocs) {
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          creatorNames[doc.id] = data['displayName'] ?? 'Unknown User';
        } else {
          creatorNames[doc.id] = 'Unknown User';
        }
      }
    } catch (e) {
      print('Error fetching creator names: $e');
      for (var uid in creatorUids) {
        creatorNames[uid] = 'Unknown User';
      }
    }

    return creatorNames;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String? tempCity = _filterCity;
        String? tempGameFormat = _filterGameFormat;
        DateTime? tempStartDate = _filterStartDate;
        DateTime? tempEndDate = _filterEndDate;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
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
                          'Filter Tournaments',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'City',
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      style: GoogleFonts.poppins(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter city (e.g., Hyderabad)',
                        hintStyle: GoogleFonts.poppins(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        tempCity = value.isEmpty ? null : value.trim();
                      },
                      controller: TextEditingController(text: tempCity),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Game Format',
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: tempGameFormat,
                      hint: Text(
                        'Select Game Format',
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                      items: [null, 'Singles', 'Doubles', 'Mixed Doubles', 'Women\'s Doubles']
                          .map((format) => DropdownMenuItem(
                                value: format,
                                child: Text(
                                  format ?? 'Any',
                                  style: GoogleFonts.poppins(color: Colors.white),
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          tempGameFormat = value;
                        });
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      dropdownColor: const Color(0xFF1B263B),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Date Range',
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.blue,
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1A237E),
                                        onSurface: Colors.white,
                                      ),
                                      dialogBackgroundColor: const Color(0xFF0D1B2A),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  tempStartDate = picked;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tempStartDate == null
                                    ? 'Start Date'
                                    : DateFormat('MMM dd, yyyy').format(tempStartDate!),
                                style: GoogleFonts.poppins(
                                  color: tempStartDate == null ? Colors.white70 : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: tempStartDate ?? DateTime.now(),
                                firstDate: tempStartDate ?? DateTime.now(),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.blue,
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1A237E),
                                        onSurface: Colors.white,
                                      ),
                                      dialogBackgroundColor: const Color(0xFF0D1B2A),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  tempEndDate = picked;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tempEndDate == null
                                    ? 'End Date'
                                    : DateFormat('MMM dd, yyyy').format(tempEndDate!),
                                style: GoogleFonts.poppins(
                                  color: tempEndDate == null ? Colors.white70 : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() {
                                tempCity = null;
                                tempGameFormat = null;
                                tempStartDate = null;
                                tempEndDate = null;
                              });
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.1),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Clear Filters',
                              style: GoogleFonts.poppins(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _filterCity = tempCity;
                                _filterGameFormat = tempGameFormat;
                                _filterStartDate = tempStartDate;
                                _filterEndDate = tempEndDate;
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Apply',
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShimmerLoading() {
    return Column(
      children: List.generate(3, (index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Shimmer.fromColors(
          baseColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.3),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _isRefreshing = true;
            });
            await Future.delayed(const Duration(seconds: 1)); // Simulate refresh
            setState(() {
              _isRefreshing = false;
            });
          },
          color: Colors.white,
          backgroundColor: Colors.blue,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Discover Tournaments',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_list, color: Colors.white70),
                      onPressed: _showFilterDialog,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.search, color: Colors.white70, size: 20),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            hintText: 'Search tournaments...',
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                            border: InputBorder.none,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.toLowerCase().trim();
                              print('Search: $_searchQuery');
                            });
                          },
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                                print('Search cleared');
                              });
                            },
                            child: const Icon(Icons.clear, color: Colors.white70, size: 20),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sort By',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _sortBy,
                      items: [
                        DropdownMenuItem(
                          value: 'date',
                          child: Text(
                            'Date',
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'name',
                          child: Text(
                            'Name',
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'participants',
                          child: Text(
                            'Participants',
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _sortBy = value!;
                        });
                      },
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      dropdownColor: const Color(0xFF1B263B),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('tournaments')
                    .where('status', isEqualTo: 'open')
                    .snapshots(),
                builder: (context, snapshot) {
                  print('StreamBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');
                  if (snapshot.connectionState == ConnectionState.waiting || _isRefreshing) {
                    return _buildShimmerLoading();
                  }
                  if (snapshot.hasError) {
                    print('Firestore error: ${snapshot.error}');
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'Error loading tournaments',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    print('No tournaments found in Firestore');
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No tournaments found.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    );
                  }

                  final tournaments = snapshot.data!.docs
                      .map((doc) {
                        try {
                          return Tournament.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
                        } catch (e) {
                          print('Error parsing tournament: $e');
                          return null;
                        }
                      })
                      .where((t) => t != null)
                      .cast<Tournament>()
                      .toList();

                  // Apply filters
                  final filteredTournaments = tournaments.where((tournament) {
                    final name = tournament.name.toLowerCase();
                    final venue = tournament.venue.toLowerCase();
                    final city = tournament.city.toLowerCase();
                    final startDateTime = DateTime(
                      tournament.startDate.year,
                      tournament.startDate.month,
                      tournament.startDate.day,
                      tournament.startTime.hour,
                      tournament.startTime.minute,
                    );
                    bool isFuture = startDateTime.isAfter(DateTime.now());

                    bool matchesSearch = name.contains(_searchQuery) ||
                        venue.contains(_searchQuery) ||
                        city.contains(_searchQuery);

                    bool matchesCity = _filterCity == null ||
                        tournament.city.toLowerCase().contains(_filterCity!.toLowerCase());

                    bool matchesGameFormat = _filterGameFormat == null ||
                        tournament.gameFormat == _filterGameFormat;

                    bool matchesDateRange = true;
                    if (_filterStartDate != null) {
                      matchesDateRange = startDateTime.isAfter(_filterStartDate!);
                    }
                    if (_filterEndDate != null) {
                      matchesDateRange = matchesDateRange &&
                          startDateTime.isBefore(_filterEndDate!.add(const Duration(days: 1)));
                    }

                    return matchesSearch &&
                        matchesCity &&
                        matchesGameFormat &&
                        matchesDateRange &&
                        isFuture;
                  }).toList();

                  // Apply sorting
                  if (_sortBy == 'date') {
                    filteredTournaments.sort((a, b) {
                      final aDateTime = DateTime(
                        a.startDate.year,
                        a.startDate.month,
                        a.startDate.day,
                        a.startTime.hour,
                        a.startTime.minute,
                      );
                      final bDateTime = DateTime(
                        b.startDate.year,
                        b.startDate.month,
                        b.startDate.day,
                        b.startTime.hour,
                        b.startTime.minute,
                      );
                      return aDateTime.compareTo(bDateTime);
                    });
                  } else if (_sortBy == 'name') {
                    filteredTournaments.sort((a, b) => a.name.compareTo(b.name));
                  } else if (_sortBy == 'participants') {
                    filteredTournaments.sort((a, b) => b.participants.length.compareTo(a.participants.length));
                  }

                  if (filteredTournaments.isEmpty) {
                    print('No matching tournaments after filtering');
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No matching tournaments found.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    );
                  }

                  print('Displaying ${filteredTournaments.length} tournaments');
                  return FutureBuilder<Map<String, String>>(
                    future: _fetchCreatorNames(filteredTournaments),
                    builder: (context, creatorSnapshot) {
                      if (creatorSnapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmerLoading();
                      }
                      if (creatorSnapshot.hasError) {
                        print('Error fetching creator names: ${creatorSnapshot.error}');
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'Error loading creator names',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        );
                      }

                      final creatorNames = creatorSnapshot.data ?? {};
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: filteredTournaments.map((tournament) {
                          final creatorName = creatorNames[tournament.createdBy] ?? 'Unknown User';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TournamentCard(
                              tournament: tournament,
                              creatorName: creatorName,
                              isCreator: false, // Set this appropriately if you have the current user's UID
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}